#!/bin/bash
# Task Status Ping — sends open tasks summary to Tasks topic
# Designed for cron: runs at 10:00 and 18:00

set -euo pipefail

CREDS_FILE="$HOME/.openclaw/credentials/.env"
if [ ! -f "$CREDS_FILE" ]; then
    echo "Error: Credentials file not found: $CREDS_FILE"
    exit 1
fi
source "$CREDS_FILE"

: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN not set}"
: "${TELEGRAM_GROUP_ID:?TELEGRAM_GROUP_ID not set}"
: "${TELEGRAM_TOPIC_TASKS:?TELEGRAM_TOPIC_TASKS not set}"

TODO_FILE="$HOME/.openclaw/workspace/topics/tasks/TODO.md"

if [ ! -f "$TODO_FILE" ]; then
    echo "TODO.md not found"
    exit 0
fi

# Count open tasks
OPEN_COUNT=$(grep -c '\- \[ \]' "$TODO_FILE" 2>/dev/null || echo 0)

if [ "$OPEN_COUNT" -eq 0 ]; then
    echo "No open tasks, skipping ping"
    exit 0
fi

# Extract open tasks (first 15 lines with checkboxes)
TASKS=$(grep '\- \[ \]' "$TODO_FILE" | head -15 | sed 's/^  /  /')

HOUR=$(date +%H)
if [ "$HOUR" -lt 12 ]; then
    GREETING="Morning task status"
else
    GREETING="Evening task status"
fi

MESSAGE="${GREETING}

Open tasks: ${OPEN_COUNT}

${TASKS}

Type \"status\" for details or \"done #N\" to close a task."

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_GROUP_ID}" \
    -d "message_thread_id=${TELEGRAM_TOPIC_TASKS}" \
    -d "parse_mode=Markdown" \
    --data-urlencode "text=${MESSAGE}" > /dev/null

echo "Sent task ping: ${OPEN_COUNT} open tasks"
