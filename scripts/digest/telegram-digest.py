#!/usr/bin/env python3
"""
Telegram Channel Digest — collects messages from subscribed channels,
filters noise, summarizes via Gemini, sends digest to a Telegram topic.

Usage:
    python3 telegram-digest.py              # Full run
    python3 telegram-digest.py --auth       # Interactive auth (first run)
    python3 telegram-digest.py --dry-run    # Collect & summarize, don't send

Prerequisites:
    pip install telethon google-generativeai
    (or use requirements.txt in scripts/digest/)

See docs/TELEGRAM-DIGEST.md for full setup instructions.
"""

import asyncio
import json
import os
import sys
import re
import logging
from datetime import datetime, timedelta, timezone
from pathlib import Path

from telethon import TelegramClient
from telethon.tl.types import (
    MessageService,
    MessageMediaPoll,
    MessageMediaGeo,
    MessageMediaGeoLive,
    MessageMediaContact,
    MessageMediaDice,
)
import google.generativeai as genai

# ============================================================
# Configuration
# ============================================================

OPENCLAW_HOME = Path(os.environ.get("OPENCLAW_HOME", Path.home() / ".openclaw"))
CREDENTIALS_DIR = OPENCLAW_HOME / "credentials"
DIGEST_DIR = OPENCLAW_HOME / "scripts" / "digest"
LOGS_DIR = OPENCLAW_HOME / "logs"

SESSION_FILE = str(CREDENTIALS_DIR / "telethon")
CHANNELS_CONFIG = DIGEST_DIR / "channels.json"

# Env vars
API_ID = int(os.environ.get("TELEGRAM_API_ID", "0"))
API_HASH = os.environ.get("TELEGRAM_API_HASH", "")
BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
GROUP_ID = int(os.environ.get("TELEGRAM_GROUP_ID", os.environ.get("TELEGRAM_CHAT_ID", "0")))
DIGEST_TOPIC_ID = int(os.environ.get("DIGEST_TOPIC_ID", "0"))
GOOGLE_API_KEY = os.environ.get("GOOGLE_API_KEY", "")

# Defaults
DEFAULT_LOOKBACK_HOURS = 24
DEFAULT_MAX_MESSAGES_PER_CHANNEL = 200
DEFAULT_MAX_TOTAL_TOKENS = 80000
MAX_MSG_LENGTH = 500
MIN_MSG_LENGTH = 20
TG_MAX_MESSAGE_LENGTH = 4096

# Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("telegram-digest")

# ============================================================
# Load channel config
# ============================================================


def load_config() -> dict:
    if not CHANNELS_CONFIG.exists():
        log.error(f"Config not found: {CHANNELS_CONFIG}")
        sys.exit(1)
    with open(CHANNELS_CONFIG, "r", encoding="utf-8") as f:
        return json.load(f)


# ============================================================
# Message filtering
# ============================================================


def is_noise(message) -> bool:
    """Return True if the message should be skipped."""
    # Service messages (join/leave, pin, title change, etc.)
    if isinstance(message, MessageService):
        return True

    # Stickers
    if message.sticker:
        return True

    # Voice / video notes
    if message.voice or message.video_note:
        return True

    # GIF / animations
    if message.gif:
        return True

    # Contacts
    if isinstance(message.media, MessageMediaContact):
        return True

    # Geo / live location
    if isinstance(message.media, (MessageMediaGeo, MessageMediaGeoLive)):
        return True

    # Dice
    if isinstance(message.media, MessageMediaDice):
        return True

    return False


def extract_text(message) -> str | None:
    """Extract text content from a message, including poll conversion."""
    # Poll -> convert to readable text
    if isinstance(message.media, MessageMediaPoll):
        poll = message.media.poll
        question = poll.question.text if hasattr(poll.question, "text") else str(poll.question)
        answers = [a.text.text if hasattr(a.text, "text") else str(a.text) for a in poll.answers]
        return f"Poll: {question} | Options: {', '.join(answers)}"

    # Regular text or media caption
    text = message.text or ""
    return text.strip() if text.strip() else None


def clean_text(text: str) -> str:
    """Clean message text for summarization."""
    # Remove bot mentions
    text = re.sub(r"@\w+bot\b", "", text, flags=re.IGNORECASE)
    # Collapse multiple newlines
    text = re.sub(r"\n{3,}", "\n\n", text)
    # Collapse multiple spaces
    text = re.sub(r" {2,}", " ", text)
    # Trim to max length
    if len(text) > MAX_MSG_LENGTH:
        text = text[:MAX_MSG_LENGTH] + "..."
    return text.strip()


# ============================================================
# Collect messages
# ============================================================


async def collect_messages(client: TelegramClient, config: dict) -> dict[str, list[str]]:
    """Collect and filter messages from all configured channels."""
    channels = config.get("channels", [])
    lookback = config.get("lookbackHours", DEFAULT_LOOKBACK_HOURS)
    max_per_channel = config.get("maxMessagesPerChannel", DEFAULT_MAX_MESSAGES_PER_CHANNEL)
    max_tokens = config.get("maxTotalTokens", DEFAULT_MAX_TOTAL_TOKENS)

    cutoff = datetime.now(timezone.utc) - timedelta(hours=lookback)
    result: dict[str, list[str]] = {}
    total_chars = 0
    token_limit = max_tokens * 4  # rough char-to-token ratio

    for channel_id in channels:
        try:
            entity = await client.get_entity(channel_id)
            channel_name = getattr(entity, "title", None) or getattr(entity, "username", None) or str(channel_id)
            log.info(f"Collecting from: {channel_name}")
        except Exception as e:
            log.warning(f"Cannot resolve {channel_id}: {e}")
            continue

        messages: list[str] = []
        seen_texts: set[str] = set()

        async for msg in client.iter_messages(entity, limit=max_per_channel, offset_date=None):
            # Stop if message is older than cutoff
            if msg.date < cutoff:
                break

            # Filter noise
            if is_noise(msg):
                continue

            # Extract text
            text = extract_text(msg)
            if not text:
                continue

            # Min length filter
            if len(text) < MIN_MSG_LENGTH:
                continue

            # Deduplicate
            text_key = text[:100].lower()
            if text_key in seen_texts:
                continue
            seen_texts.add(text_key)

            # Clean
            cleaned = clean_text(text)
            if not cleaned:
                continue

            # Check total limit
            if total_chars + len(cleaned) > token_limit:
                log.warning(f"Token limit reached at channel {channel_name}")
                break

            messages.append(cleaned)
            total_chars += len(cleaned)

        if messages:
            result[channel_name] = messages
            log.info(f"  -> {len(messages)} messages from {channel_name}")

        if total_chars > token_limit:
            log.warning("Total token limit reached, stopping collection")
            break

    return result


# ============================================================
# Format for Gemini
# ============================================================


def format_for_llm(channel_messages: dict[str, list[str]]) -> str:
    """Format collected messages for the LLM prompt."""
    parts = []
    for channel, messages in channel_messages.items():
        section = f"## {channel}\n"
        for msg in messages:
            section += f"- {msg}\n"
        parts.append(section)
    return "\n".join(parts)


# ============================================================
# Summarize via Gemini
# ============================================================

SUMMARIZE_PROMPT_EN = """You are an assistant that creates Telegram channel digests.
Below are messages from channels over the last 24 hours.
Create a brief summary for each channel:
- Main topics and news
- Important announcements
- Key numbers/facts
Format: channel name as heading, then 3-7 bullet points.
Be concise and factual.
If a channel has nothing important — write "no significant updates".
"""

SUMMARIZE_PROMPT_RU = """Ты — помощник, который делает обзор Telegram-каналов.
Ниже — сообщения из каналов за последние 24 часа.
Сделай краткую выжимку по каждому каналу:
- Главные темы и новости
- Важные анонсы
- Ключевые цифры/факты
Формат: заголовок канала, потом 3-7 пунктов.
Пиши на русском, кратко и по делу.
Если в канале ничего важного — напиши "без важных обновлений".
"""


def get_summarize_prompt() -> str:
    """Return summarization prompt based on DIGEST_LANGUAGE env var."""
    lang = os.environ.get("DIGEST_LANGUAGE", "en").lower()
    if lang == "ru":
        return SUMMARIZE_PROMPT_RU
    return SUMMARIZE_PROMPT_EN


def summarize(channel_messages: dict[str, list[str]]) -> str:
    """Send collected messages to Gemini for summarization."""
    genai.configure(api_key=GOOGLE_API_KEY)
    model = genai.GenerativeModel("gemini-2.5-flash")

    content = format_for_llm(channel_messages)
    full_prompt = get_summarize_prompt() + "\n\n" + content

    log.info(f"Sending to Gemini ({len(full_prompt)} chars)...")
    response = model.generate_content(full_prompt)
    return response.text


# ============================================================
# Send to Telegram via Bot API
# ============================================================


def send_to_telegram(text: str) -> None:
    """Send digest to Telegram topic via Bot API."""
    import urllib.request
    import urllib.parse

    if not BOT_TOKEN or not GROUP_ID or not DIGEST_TOPIC_ID:
        log.error("Missing TELEGRAM_BOT_TOKEN, TELEGRAM_GROUP_ID, or DIGEST_TOPIC_ID")
        sys.exit(1)

    today = datetime.now().strftime("%Y-%m-%d")
    header = f"<b>Channel Digest — {today}</b>\n\n"
    full_text = header + text

    # Split into chunks if needed
    chunks = []
    if len(full_text) <= TG_MAX_MESSAGE_LENGTH:
        chunks.append(full_text)
    else:
        current = header
        for line in text.split("\n"):
            if len(current) + len(line) + 1 > TG_MAX_MESSAGE_LENGTH:
                chunks.append(current)
                current = ""
            current += line + "\n"
        if current.strip():
            chunks.append(current)

    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"

    for i, chunk in enumerate(chunks):
        data = urllib.parse.urlencode({
            "chat_id": GROUP_ID,
            "message_thread_id": DIGEST_TOPIC_ID,
            "text": chunk,
            "parse_mode": "HTML",
        }).encode("utf-8")

        req = urllib.request.Request(url, data=data)
        try:
            with urllib.request.urlopen(req) as resp:
                result = json.loads(resp.read())
                if result.get("ok"):
                    log.info(f"Sent chunk {i + 1}/{len(chunks)}")
                else:
                    log.error(f"Telegram API error: {result}")
        except Exception as e:
            log.error(f"Failed to send: {e}")
            raise


# ============================================================
# Main
# ============================================================


async def run_auth():
    """Interactive authentication — first run only."""
    if not API_ID or not API_HASH:
        print("Set TELEGRAM_API_ID and TELEGRAM_API_HASH in .env first.")
        print("Get them at https://my.telegram.org/apps")
        sys.exit(1)

    CREDENTIALS_DIR.mkdir(parents=True, exist_ok=True)
    client = TelegramClient(SESSION_FILE, API_ID, API_HASH)
    await client.start()
    me = await client.get_me()
    print(f"Authenticated as: {me.first_name} (ID: {me.id})")
    await client.disconnect()
    print(f"Session saved to: {SESSION_FILE}.session")
    # Set permissions on session file
    session_path = Path(SESSION_FILE + ".session")
    if session_path.exists():
        os.chmod(session_path, 0o600)


async def run_digest(dry_run: bool = False):
    """Main digest pipeline."""
    if not API_ID or not API_HASH:
        log.error("TELEGRAM_API_ID / TELEGRAM_API_HASH not set")
        sys.exit(1)
    if not GOOGLE_API_KEY:
        log.error("GOOGLE_API_KEY not set")
        sys.exit(1)

    config = load_config()
    channels = config.get("channels", [])
    if not channels:
        log.error("No channels configured in channels.json")
        sys.exit(1)

    log.info(f"Starting digest: {len(channels)} channels, dry_run={dry_run}")

    # Connect as userbot (read-only)
    client = TelegramClient(SESSION_FILE, API_ID, API_HASH)
    await client.start()

    try:
        # Collect
        channel_messages = await collect_messages(client, config)

        if not channel_messages:
            log.warning("No messages collected from any channel")
            if not dry_run:
                send_to_telegram("No new messages from tracked channels in the last 24h.")
            return

        total = sum(len(msgs) for msgs in channel_messages.values())
        log.info(f"Collected {total} messages from {len(channel_messages)} channels")

        # Summarize
        summary = summarize(channel_messages)
        log.info(f"Summary generated ({len(summary)} chars)")

        if dry_run:
            print("\n" + "=" * 60)
            print("DRY RUN — Summary preview:")
            print("=" * 60)
            print(summary)
            print("=" * 60)
            print(f"\nChannels: {len(channel_messages)}")
            print(f"Messages: {total}")
            print(f"Summary length: {len(summary)} chars")
        else:
            send_to_telegram(summary)
            log.info("Digest sent successfully")

            # Save to file
            digest_dir = OPENCLAW_HOME / "workspace" / "topics" / "channel-digest"
            digest_dir.mkdir(parents=True, exist_ok=True)
            today = datetime.now().strftime("%Y-%m-%d")
            digest_file = digest_dir / f"{today}.md"
            with open(digest_file, "w", encoding="utf-8") as f:
                f.write(f"# Channel Digest — {today}\n\n")
                f.write(summary)
            log.info(f"Saved to {digest_file}")

    finally:
        await client.disconnect()


def main():
    if "--auth" in sys.argv:
        asyncio.run(run_auth())
    elif "--dry-run" in sys.argv:
        asyncio.run(run_digest(dry_run=True))
    elif "--help" in sys.argv or "-h" in sys.argv:
        print(__doc__)
    else:
        asyncio.run(run_digest(dry_run=False))


if __name__ == "__main__":
    main()
