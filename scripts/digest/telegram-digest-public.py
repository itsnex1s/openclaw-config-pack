#!/usr/bin/env python3
"""
Telegram Public Channel Digest — scrapes public channels via t.me/s/<channel>,
filters noise, summarizes via Gemini, sends digest to a Telegram topic.

No Telethon, no API ID/hash, no authentication required.

Usage:
    python3 telegram-digest-public.py              # Full run
    python3 telegram-digest-public.py --dry-run    # Collect & summarize, don't send
    python3 telegram-digest-public.py --preview    # Collect only, no Gemini

Prerequisites:
    pip install httpx beautifulsoup4 lxml google-generativeai
    (or use requirements-public.txt in scripts/digest/)

See docs/TELEGRAM-DIGEST-PUBLIC.md for full setup instructions.
"""

import io
import json
import os
import re
import sys
import time
import logging
from datetime import datetime, timedelta, timezone
from pathlib import Path

# Ensure UTF-8 output on Windows
if sys.stdout.encoding != "utf-8":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
if sys.stderr.encoding != "utf-8":
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

import httpx
from bs4 import BeautifulSoup
import google.generativeai as genai

# ============================================================
# Configuration
# ============================================================

OPENCLAW_HOME = Path(os.environ.get("OPENCLAW_HOME", Path.home() / ".openclaw"))
DIGEST_DIR = OPENCLAW_HOME / "scripts" / "digest"
LOGS_DIR = OPENCLAW_HOME / "logs"

CHANNELS_CONFIG = DIGEST_DIR / "public-channels.json"

# Env vars
BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
GROUP_ID = int(os.environ.get("TELEGRAM_GROUP_ID", os.environ.get("TELEGRAM_CHAT_ID", "0")))
DIGEST_TOPIC_ID = int(os.environ.get("DIGEST_PUBLIC_TOPIC_ID", os.environ.get("DIGEST_TOPIC_ID", "0")))
GOOGLE_API_KEY = os.environ.get("GOOGLE_API_KEY", "")
DIGEST_LANGUAGE = os.environ.get("DIGEST_LANGUAGE", "en").lower()
REQUEST_DELAY = float(os.environ.get("DIGEST_REQUEST_DELAY", "2.0"))

# Defaults
DEFAULT_LOOKBACK_HOURS = 24
DEFAULT_MAX_MESSAGES_PER_CHANNEL = 200
DEFAULT_MAX_TOTAL_TOKENS = 80000
MAX_MSG_LENGTH = 500
MIN_MSG_LENGTH = 20
TG_MAX_MESSAGE_LENGTH = 4096
MAX_PAGES_PER_CHANNEL = 5

# HTTP
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
RETRY_SLEEP = 30

# Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("telegram-digest-public")

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
# Text cleaning
# ============================================================


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
# Scrape public channel
# ============================================================


def fetch_page(client: httpx.Client, channel: str, before: int | None = None) -> httpx.Response | None:
    """Fetch a page from t.me/s/<channel>, with retry on 429."""
    url = f"https://t.me/s/{channel}"
    if before is not None:
        url += f"?before={before}"

    try:
        resp = client.get(url)
        if resp.status_code == 429:
            log.warning(f"Rate limited on {channel}, sleeping {RETRY_SLEEP}s...")
            time.sleep(RETRY_SLEEP)
            resp = client.get(url)
            if resp.status_code == 429:
                log.error(f"Still rate limited on {channel}, skipping")
                return None
        resp.raise_for_status()
        return resp
    except httpx.HTTPStatusError as e:
        log.warning(f"HTTP {e.response.status_code} for {channel}: {e}")
        return None
    except httpx.RequestError as e:
        log.warning(f"Request error for {channel}: {e}")
        return None


def parse_messages(html: str, channel: str, cutoff: datetime) -> tuple[list[dict], int | None]:
    """
    Parse messages from t.me/s/<channel> HTML.
    Returns (messages, oldest_msg_id) where oldest_msg_id can be used for pagination.
    """
    soup = BeautifulSoup(html, "lxml")
    messages = []
    oldest_id = None

    # Check if channel has preview disabled
    error_el = soup.select_one(".tgme_channel_history_unavailable")
    if error_el:
        return [], None

    widgets = soup.select(".tgme_widget_message")
    for widget in widgets:
        # Extract message ID from data-post="channel/123"
        data_post = widget.get("data-post", "")
        if "/" not in data_post:
            continue
        msg_id_str = data_post.split("/")[-1]
        try:
            msg_id = int(msg_id_str)
        except ValueError:
            continue

        # Track oldest for pagination
        if oldest_id is None or msg_id < oldest_id:
            oldest_id = msg_id

        # Extract date
        time_el = widget.select_one("time[datetime]")
        if not time_el:
            continue
        try:
            msg_date = datetime.fromisoformat(time_el["datetime"].replace("Z", "+00:00"))
        except (ValueError, KeyError):
            continue

        # Skip messages older than cutoff
        if msg_date < cutoff:
            continue

        # Extract text
        text_el = widget.select_one(".tgme_widget_message_text")
        if not text_el:
            continue
        text = text_el.get_text(separator="\n").strip()
        if not text:
            continue

        messages.append({
            "id": msg_id,
            "date": msg_date,
            "text": text,
        })

    return messages, oldest_id


def scrape_channel(client: httpx.Client, channel: str, cutoff: datetime, max_messages: int) -> list[str]:
    """Scrape messages from a public channel, paginating as needed."""
    all_messages: list[dict] = []
    seen_ids: set[int] = set()
    before: int | None = None

    for page in range(MAX_PAGES_PER_CHANNEL):
        if page > 0:
            time.sleep(REQUEST_DELAY)

        resp = fetch_page(client, channel, before=before)
        if resp is None:
            break

        messages, oldest_id = parse_messages(resp.text, channel, cutoff)

        if not messages and page == 0:
            # Channel may have preview disabled or no messages
            log.warning(f"No messages found for {channel} (preview disabled?)")
            break

        new_count = 0
        for msg in messages:
            if msg["id"] not in seen_ids:
                seen_ids.add(msg["id"])
                all_messages.append(msg)
                new_count += 1

        if new_count == 0:
            # No new messages on this page
            break

        if len(all_messages) >= max_messages:
            break

        # Check if we got messages older than cutoff — stop paginating
        if oldest_id is not None:
            before = oldest_id
        else:
            break

    # Sort by date (newest first), then process
    all_messages.sort(key=lambda m: m["date"], reverse=True)

    # Filter and clean
    result: list[str] = []
    seen_texts: set[str] = set()

    for msg in all_messages[:max_messages]:
        text = msg["text"]

        # Min length filter
        if len(text) < MIN_MSG_LENGTH:
            continue

        # Deduplicate (normalize whitespace before comparing)
        text_key = re.sub(r"\s+", " ", text[:100]).strip().lower()
        if text_key in seen_texts:
            continue
        seen_texts.add(text_key)

        # Clean
        cleaned = clean_text(text)
        if cleaned:
            result.append(cleaned)

    return result


# ============================================================
# Collect from all channels
# ============================================================


def collect_messages(config: dict) -> dict[str, list[str]]:
    """Collect and filter messages from all configured public channels."""
    channels = config.get("channels", [])
    lookback = config.get("lookbackHours", DEFAULT_LOOKBACK_HOURS)
    max_per_channel = config.get("maxMessagesPerChannel", DEFAULT_MAX_MESSAGES_PER_CHANNEL)
    max_tokens = config.get("maxTotalTokens", DEFAULT_MAX_TOTAL_TOKENS)

    cutoff = datetime.now(timezone.utc) - timedelta(hours=lookback)
    result: dict[str, list[str]] = {}
    total_chars = 0
    token_limit = max_tokens * 4  # rough char-to-token ratio

    client = httpx.Client(
        headers={"User-Agent": USER_AGENT},
        follow_redirects=True,
        timeout=30.0,
    )

    try:
        for i, raw_channel in enumerate(channels):
            # Strip @ prefix if present
            channel = raw_channel.lstrip("@").strip()
            if not channel:
                continue

            if i > 0:
                time.sleep(REQUEST_DELAY)

            log.info(f"Collecting from: {channel}")

            messages = scrape_channel(client, channel, cutoff, max_per_channel)

            # Apply token budget
            budget_messages: list[str] = []
            for msg in messages:
                if total_chars + len(msg) > token_limit:
                    log.warning(f"Token limit reached at channel {channel}")
                    break
                budget_messages.append(msg)
                total_chars += len(msg)

            if budget_messages:
                result[channel] = budget_messages
                log.info(f"  -> {len(budget_messages)} messages from {channel}")

            if total_chars > token_limit:
                log.warning("Total token limit reached, stopping collection")
                break
    finally:
        client.close()

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
    if DIGEST_LANGUAGE == "ru":
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
        log.error("Missing TELEGRAM_BOT_TOKEN, TELEGRAM_GROUP_ID, or DIGEST_PUBLIC_TOPIC_ID/DIGEST_TOPIC_ID")
        sys.exit(1)

    today = datetime.now().strftime("%Y-%m-%d")
    header = f"<b>Public Channel Digest — {today}</b>\n\n"
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


def run_digest(dry_run: bool = False, preview: bool = False):
    """Main digest pipeline."""
    if not preview and not dry_run:
        if not GOOGLE_API_KEY:
            log.error("GOOGLE_API_KEY not set")
            sys.exit(1)
    if not preview:
        if not GOOGLE_API_KEY:
            log.error("GOOGLE_API_KEY not set")
            sys.exit(1)

    config = load_config()
    channels = config.get("channels", [])
    if not channels:
        log.error("No channels configured in public-channels.json")
        sys.exit(1)

    log.info(f"Starting public digest: {len(channels)} channels, dry_run={dry_run}, preview={preview}")

    # Collect
    channel_messages = collect_messages(config)

    if not channel_messages:
        log.warning("No messages collected from any channel")
        if not dry_run and not preview:
            send_to_telegram("No new messages from tracked public channels in the last 24h.")
        return

    total = sum(len(msgs) for msgs in channel_messages.values())
    log.info(f"Collected {total} messages from {len(channel_messages)} channels")

    if preview:
        print("\n" + "=" * 60)
        print("PREVIEW — Collected messages (no Gemini):")
        print("=" * 60)
        for channel, msgs in channel_messages.items():
            print(f"\n## {channel} ({len(msgs)} messages)")
            for msg in msgs[:10]:
                print(f"  - {msg[:120]}...")
        print("=" * 60)
        print(f"\nChannels: {len(channel_messages)}")
        print(f"Messages: {total}")
        return

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
        digest_file = digest_dir / f"{today}-public.md"
        with open(digest_file, "w", encoding="utf-8") as f:
            f.write(f"# Public Channel Digest — {today}\n\n")
            f.write(summary)
        log.info(f"Saved to {digest_file}")


def main():
    if "--help" in sys.argv or "-h" in sys.argv:
        print(__doc__)
    elif "--preview" in sys.argv:
        run_digest(preview=True)
    elif "--dry-run" in sys.argv:
        run_digest(dry_run=True)
    else:
        run_digest()


if __name__ == "__main__":
    main()
