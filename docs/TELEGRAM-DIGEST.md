# Telegram Channel Digest

Automatic daily digest from subscribed Telegram channels, summarized via Gemini and sent to a dedicated topic.

Also includes a daily task digest (morning/evening/weekly) based on your TODO.md.

---

## How It Works

### Channel Digest

```
Cron (08:30) → telegram-digest.py (Telethon)
    |
    v
Connects as userbot (MTProto, read-only)
    |
    v
Reads channels from digest-channels.json (last 24h)
    |
    v
Filters noise (stickers, voice, GIF, service msgs, short msgs)
    |
    v
Deduplicates, cleans, limits to token budget
    |
    v
Sends to Gemini API → summary per channel
    |
    v
Posts to Telegram topic via Bot API
    |
    v
Saves to topics/channel-digest/YYYY-MM-DD.md
```

### Daily Task Digest

```
Cron (08:00 / 20:00) → daily-digest.sh
    |
    v
Reads TODO.md, DONE.md, IDEAS.md, MEMORY.md
    |
    v
Morning: weather, tasks, overdue, focus
Evening: completed today, not done, tomorrow
Weekly:  week summary, ideas review
    |
    v
Posts to Telegram Daily topic via Bot API
```

---

## Setup: Channel Digest

### 1. Get Telegram API credentials

Go to https://my.telegram.org/apps and create an application.

You'll get:
- `api_id` (number)
- `api_hash` (string)

### 2. Add to .env

```bash
nano ~/.openclaw/credentials/.env
```

Add:

```bash
TELEGRAM_API_ID=12345678
TELEGRAM_API_HASH=your_api_hash_here
GOOGLE_API_KEY=your_google_api_key_here
DIGEST_TOPIC_ID=121
```

### 3. Create Python virtual environment

```bash
cd ~/.openclaw/scripts
python3 -m venv digest-venv
source digest-venv/bin/activate
pip install -r requirements-digest.txt
```

### 4. Authenticate with Telegram

First run requires interactive login (phone number + code):

```bash
source ~/.openclaw/credentials/.env
python3 ~/.openclaw/scripts/telegram-digest.py --auth
```

This creates `~/.openclaw/credentials/telethon.session`. The session is reused for all future runs.

```bash
chmod 600 ~/.openclaw/credentials/telethon.session
```

### 5. Configure channels

Edit `~/.openclaw/scripts/digest-channels.json`:

```json
{
  "channels": [
    "@channel_username",
    "@another_channel",
    -1001234567890
  ],
  "maxMessagesPerChannel": 200,
  "lookbackHours": 24,
  "maxTotalTokens": 80000
}
```

Channels can be specified as `@username` or numeric ID.

### 6. Test

```bash
# Preview without sending
python3 ~/.openclaw/scripts/telegram-digest.py --dry-run

# Full run
python3 ~/.openclaw/scripts/telegram-digest.py
```

### 7. Add cron job

```bash
crontab -e
```

Add:

```
30 8 * * * ~/.openclaw/scripts/telegram-digest-cron.sh
```

---

## Setup: Daily Task Digest

### 1. Configure topic ID

Add to `~/.openclaw/credentials/.env`:

```bash
TELEGRAM_TOPIC_DAILY=12
WEATHER_CITY=London
```

### 2. Test

```bash
~/.openclaw/scripts/daily-digest.sh --preview
```

### 3. Add cron jobs

```bash
crontab -e
```

Add:

```
# Morning digest at 08:00
0 8 * * * ~/.openclaw/scripts/daily-digest.sh >> ~/.openclaw/logs/daily-digest.log 2>&1

# Evening summary at 20:00
0 20 * * * ~/.openclaw/scripts/daily-digest.sh --evening >> ~/.openclaw/logs/daily-digest.log 2>&1

# Weekly review on Sundays at 10:00
0 10 * * 0 ~/.openclaw/scripts/daily-digest.sh --weekly >> ~/.openclaw/logs/daily-digest.log 2>&1
```

---

## Configuration

### Channel Digest (`digest-channels.json`)

| Key | Default | Description |
|-----|---------|-------------|
| `channels` | `[]` | List of channel usernames or IDs |
| `maxMessagesPerChannel` | `200` | Max messages to collect per channel |
| `lookbackHours` | `24` | How far back to collect |
| `maxTotalTokens` | `80000` | Token budget for Gemini context |

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `TELEGRAM_API_ID` | Yes (digest) | Telegram API app ID |
| `TELEGRAM_API_HASH` | Yes (digest) | Telegram API app hash |
| `GOOGLE_API_KEY` | Yes (digest) | Google AI API key for Gemini |
| `TELEGRAM_BOT_TOKEN` | Yes | Bot token for sending messages |
| `TELEGRAM_GROUP_ID` | Yes | Target Telegram group ID |
| `DIGEST_TOPIC_ID` | Yes (digest) | Topic ID for channel digests |
| `TELEGRAM_TOPIC_DAILY` | Yes (daily) | Topic ID for daily digests |
| `WEATHER_CITY` | No | City for weather (default: `London`) |
| `DIGEST_LANGUAGE` | No | Summary language: `en` or `ru` (default: `en`) |

### OpenClaw Plugin Config (`openclaw.json`)

The `telegram-digest` plugin provides in-chat commands:

```json
{
  "plugins": {
    "entries": {
      "telegram-digest": { "enabled": true }
    }
  }
}
```

Plugin commands (in the Channel Digest topic):
- `digest` / `run` / `trigger` — manually trigger digest collection
- `channels` / `list` — show tracked channels and config

---

## Message Filtering

### What gets filtered OUT:

- Stickers
- Voice / video notes
- GIF / animations
- Contacts, locations, dice
- Service messages (join/leave, pin, title change)
- Empty messages (no text, no media caption)
- Duplicates (same text in one channel)
- Messages shorter than 20 characters

### What gets KEPT:

- Text messages
- Photo/video captions
- Forwarded text messages
- Polls (converted to text: "Poll: {question} | Options: {1}, {2}, ...")

### Context optimization:

- Each message trimmed to 500 characters
- Max 200 messages per channel
- Total token limit ~80K (configurable)
- Bot @mentions removed
- Whitespace normalized

---

## Daily Digest Modes

### Morning (default)

Shows:
- Weather forecast
- Active tasks from TODO.md
- Overdue tasks
- Yesterday's stats (completed, voice messages)
- Focus of the day from MEMORY.md

### Evening (`--evening`)

Shows:
- Tasks completed today
- Tasks not completed (due today)
- Tomorrow's scheduled tasks

### Weekly (`--weekly`)

Shows:
- Total completed tasks this week
- Ideas reminder
- Next week's focus

---

## Security Notes

1. **Telethon is read-only** — only calls `get_entity()` and `iter_messages()`, never sends messages via userbot
2. **Bot API for sending** — all outgoing messages go through the bot token
3. **Session file** — stored in `~/.openclaw/credentials/` with `chmod 600`
4. **API credentials** — in `.env` with `chmod 600`, never committed to git
5. **Rate limiting** — max 200 messages/channel, runs once daily
6. **Telegram ToS** — reading your own subscribed channels is within normal usage

---

## File Structure

```
~/.openclaw/
├── credentials/
│   ├── .env                        # API keys, tokens
│   └── telethon.session            # Telethon auth (chmod 600)
├── scripts/
│   ├── telegram-digest.py          # Channel digest collector
│   ├── telegram-digest-cron.sh     # Cron wrapper
│   ├── daily-digest.sh             # Task digest (morning/evening/weekly)
│   ├── digest-channels.json        # Channel list
│   ├── requirements-digest.txt     # Python dependencies
│   └── digest-venv/                # Python virtual environment
├── workspace/
│   ├── topics/
│   │   ├── channel-digest/
│   │   │   └── YYYY-MM-DD.md      # Saved channel digests
│   │   ├── daily/
│   │   │   └── YYYY-MM-DD.md      # Saved daily digests
│   │   └── tasks/
│   │       ├── TODO.md             # Active tasks
│   │       └── DONE.md             # Completed tasks
│   └── .openclaw/extensions/telegram-digest/
│       ├── index.ts                # OpenClaw plugin
│       ├── openclaw.plugin.json    # Manifest
│       └── package.json
└── logs/
    └── telegram-digest.log         # Cron output
```

---

## Troubleshooting

### "TELEGRAM_API_ID not set"

```bash
# Verify .env has the values
grep TELEGRAM_API ~/.openclaw/credentials/.env

# Make sure cron wrapper sources .env
cat ~/.openclaw/scripts/telegram-digest-cron.sh
```

### "No channels configured"

```bash
# Check config exists
cat ~/.openclaw/scripts/digest-channels.json

# Channels must be an array of strings/numbers
```

### "Cannot resolve channel"

The userbot must be subscribed to the channel. Join the channel first, then retry.

### Telethon session expired

```bash
# Re-authenticate
source ~/.openclaw/credentials/.env
python3 ~/.openclaw/scripts/telegram-digest.py --auth
```

### Gemini API errors

```bash
# Verify key
echo $GOOGLE_API_KEY

# Test with dry-run (still calls Gemini but doesn't send to Telegram)
python3 ~/.openclaw/scripts/telegram-digest.py --dry-run
```

### Daily digest not showing tasks

```bash
# Check TODO.md exists
cat ~/.openclaw/workspace/topics/tasks/TODO.md

# Preview digest
~/.openclaw/scripts/daily-digest.sh --preview
```

---

## Dependencies

| Dependency | Required For | Purpose |
|-----------|-------------|---------|
| [Telethon](https://github.com/LonamiWebs/Telethon) | Channel digest | Read Telegram channels via MTProto |
| [google-generativeai](https://ai.google.dev/) | Channel digest | Summarization via Gemini |
| curl | Daily digest | Weather (wttr.in) + Telegram Bot API |
| cron | Both | Scheduled execution |
