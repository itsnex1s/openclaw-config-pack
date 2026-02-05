#!/bin/bash
# telegram-digest-public-cron.sh — cron wrapper for public channel digest
#
# Cron:
#   45 8 * * * ~/.openclaw/scripts/digest/telegram-digest-public-cron.sh

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

python3 "$OPENCLAW_HOME/scripts/digest/telegram-digest-public.py" \
    >> "$LOG_DIR/telegram-digest-public.log" 2>&1
