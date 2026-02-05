# Telegram Public Channel Digest

Automatic daily digest from **public** Telegram channels via web scraping (no Telethon, no API credentials, no authentication).

Summarized via Gemini and sent to a dedicated Telegram topic.

---

## How It Works

```
Cron (08:45) → telegram-digest-public.py
    |
    v
HTTP GET https://t.me/s/<channel> (httpx)
    |
    v
Parse HTML with BeautifulSoup (lxml)
    |
    v
Paginate via ?before=<msg_id> (max 5 pages)
    |
    v
Filter: skip short (<20 chars), deduplicate, trim to 500 chars
    |
    v
Apply token budget (80K default)
    |
    v
Send to Gemini API → summary per channel
    |
    v
Post to Telegram topic via Bot API (chunked if >4096 chars)
    |
    v
Save to topics/channel-digest/YYYY-MM-DD-public.md
```

---

## Telethon vs Public Variant

| Feature | Telethon (`telegram-digest.py`) | Public (`telegram-digest-public.py`) |
|---------|--------------------------------|--------------------------------------|
| Authentication | API ID + Hash + session | None |
| Channel access | Any subscribed channel | Public channels only |
| Protocol | MTProto (Telethon) | HTTP scraping (httpx) |
| Media types | Stickers, polls, voice, etc. | Text + captions only |
| Private channels | Yes | No |
| Preview-disabled | Yes | No (skipped with warning) |
| Rate limiting | Telegram MTProto limits | HTTP 429 + `DIGEST_REQUEST_DELAY` |
| Dependencies | `telethon` | `httpx`, `beautifulsoup4`, `lxml` |
| Setup complexity | High (auth, session file) | Low (just add channels) |

Use both variants together — they save to separate files (`YYYY-MM-DD.md` vs `YYYY-MM-DD-public.md`) and can target separate topic IDs.

---

## Setup

### 1. Install Python dependencies

```bash
cd ~/.openclaw/scripts/digest
source venv/bin/activate   # reuse existing venv, or create one
pip install -r requirements-public.txt
```

If you don't have a venv yet:

```bash
cd ~/.openclaw/scripts/digest
python3 -m venv venv
source venv/bin/activate
pip install -r requirements-public.txt
```

### 2. Configure channels

Edit `~/.openclaw/scripts/digest/public-channels.json`:

```json
{
  "channels": [
    "durov",
    "telegram"
  ],
  "maxMessagesPerChannel": 200,
  "lookbackHours": 24,
  "maxTotalTokens": 80000
}
```

Channels are specified as usernames (without `@`). Leading `@` is stripped automatically.

### 3. Add environment variables

Edit `~/.openclaw/credentials/.env`:

```bash
# Required
GOOGLE_API_KEY=your_google_api_key_here
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrsTUVwxyz
TELEGRAM_GROUP_ID=-1001234567890

# Topic ID for public digest (falls back to DIGEST_TOPIC_ID)
DIGEST_PUBLIC_TOPIC_ID=121

# Optional
DIGEST_LANGUAGE=en              # en or ru
DIGEST_REQUEST_DELAY=2.0        # seconds between HTTP requests
```

### 4. Test

```bash
source ~/.openclaw/credentials/.env

# Preview: collect messages only, no Gemini call
python3 ~/.openclaw/scripts/digest/telegram-digest-public.py --preview

# Dry run: collect + summarize, don't send to Telegram
python3 ~/.openclaw/scripts/digest/telegram-digest-public.py --dry-run

# Full run
python3 ~/.openclaw/scripts/digest/telegram-digest-public.py
```

### 5. Add cron job

```bash
crontab -e
```

Add:

```
45 8 * * * ~/.openclaw/scripts/digest/telegram-digest-public-cron.sh >> ~/.openclaw/logs/telegram-digest-public.log 2>&1
```

---

## Configuration

### Channel Config (`scripts/digest/public-channels.json`)

| Key | Default | Description |
|-----|---------|-------------|
| `channels` | `[]` | List of public channel usernames |
| `maxMessagesPerChannel` | `200` | Max messages to collect per channel |
| `lookbackHours` | `24` | How far back to collect |
| `maxTotalTokens` | `80000` | Token budget for Gemini context |

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `GOOGLE_API_KEY` | Yes | Google AI API key for Gemini |
| `TELEGRAM_BOT_TOKEN` | Yes | Bot token for sending messages |
| `TELEGRAM_GROUP_ID` | Yes | Target Telegram group ID |
| `DIGEST_PUBLIC_TOPIC_ID` | No | Topic ID (falls back to `DIGEST_TOPIC_ID`) |
| `DIGEST_LANGUAGE` | No | Summary language: `en` or `ru` (default: `en`) |
| `DIGEST_REQUEST_DELAY` | No | Seconds between HTTP requests (default: `2.0`) |

---

## Limitations

1. **Public channels only** — channels must have a public `t.me/<username>` with web preview enabled
2. **Preview-disabled channels** — some channels disable web preview; these are skipped with a warning
3. **Text only** — media-only posts (photos without caption, stickers, voice) are not captured
4. **HTML structure** — depends on Telegram's `t.me/s/` page structure; may break if Telegram changes their frontend
5. **Pagination depth** — max 5 pages per channel (~100 messages); very active channels may miss older messages within the 24h window
6. **Rate limiting** — Telegram may return HTTP 429; the script retries once after 30s, then skips

---

## Message Filtering

### What gets filtered OUT:

- Messages shorter than 20 characters
- Duplicate messages (same first 100 chars)
- Media-only posts (no text content in HTML)

### What gets KEPT:

- Text messages
- Photo/video captions (if rendered in HTML)
- Forwarded text messages
- Any text content visible on the public preview page

### Context optimization:

- Each message trimmed to 500 characters
- Max 200 messages per channel (configurable)
- Total token limit ~80K (configurable)
- Bot @mentions removed
- Whitespace normalized

---

## Troubleshooting

### "No messages found for channel (preview disabled?)"

The channel either has web preview disabled or the username is incorrect.

```bash
# Verify the channel is accessible
curl -s "https://t.me/s/channel_username" | grep -c "tgme_widget_message"
# Should return a number > 0
```

### "Rate limited on channel"

Telegram returned HTTP 429. The script retries once after 30 seconds. If it persists:

- Increase `DIGEST_REQUEST_DELAY` to `5.0` or higher
- Reduce the number of channels
- Run at a different time

### "Config not found"

```bash
# Check config exists
ls -la ~/.openclaw/scripts/digest/public-channels.json

# Verify JSON is valid
python3 -c "import json; json.load(open('$HOME/.openclaw/scripts/digest/public-channels.json'))"
```

### Gemini API errors

```bash
# Verify key
echo $GOOGLE_API_KEY

# Test with dry-run
python3 ~/.openclaw/scripts/digest/telegram-digest-public.py --dry-run
```

### Empty digest

- Check that channels have posts within the last 24 hours
- Try `--preview` to see what messages are collected
- Verify channel usernames are correct (no `@` needed, just the username)

---

## File Structure

```
~/.openclaw/
├── credentials/
│   └── .env                              # API keys, tokens
├── scripts/
│   └── digest/
│       ├── telegram-digest-public.py         # Public channel scraper
│       ├── telegram-digest-public-cron.sh    # Cron wrapper
│       ├── public-channels.json              # Public channel list
│       ├── requirements-public.txt           # Python dependencies
│       ├── telegram-digest.py                # Telethon variant (separate)
│       ├── telegram-digest-cron.sh           # Telethon cron wrapper
│       ├── channels.json                     # Telethon channel list
│       ├── requirements.txt                  # Telethon dependencies
│       └── venv/                             # Shared Python venv
├── workspace/
│   └── topics/
│       └── channel-digest/
│           ├── YYYY-MM-DD.md            # Telethon digest
│           └── YYYY-MM-DD-public.md     # Public digest
└── logs/
    ├── telegram-digest.log              # Telethon cron log
    └── telegram-digest-public.log       # Public cron log
```

---

## Cron Pipeline

Both digest variants run independently alongside the daily task digest:

```cron
0  8 * * *  ~/.openclaw/scripts/notify/daily-digest.sh                  # Tasks + weather
30 8 * * *  ~/.openclaw/scripts/digest/telegram-digest-cron.sh         # Private channels (Telethon)
45 8 * * *  ~/.openclaw/scripts/digest/telegram-digest-public-cron.sh  # Public channels (scraping)
```

Each posts to its own topic and can fail independently without affecting the others.
