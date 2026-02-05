#!/bin/bash
# telegram-digest-cron.sh — cron wrapper for Telegram channel digest
#
# Cron:
#   30 8 * * * ~/.openclaw/scripts/digest/telegram-digest-cron.sh

set -e

OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
VENV="$OPENCLAW_HOME/scripts/digest/venv"
LOG_DIR="$OPENCLAW_HOME/logs"

mkdir -p "$LOG_DIR"

# Load environment
if [ -f "$OPENCLAW_HOME/credentials/.env" ]; then
    set -a
    source "$OPENCLAW_HOME/credentials/.env"
    set +a
fi

# Activate venv and run
if [ -d "$VENV" ]; then
    source "$VENV/bin/activate"
fi

python3 "$OPENCLAW_HOME/scripts/digest/telegram-digest.py" \
    >> "$LOG_DIR/telegram-digest.log" 2>&1
