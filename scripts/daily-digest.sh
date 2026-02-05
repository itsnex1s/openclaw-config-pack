#!/bin/bash
# daily-digest.sh — Generate and send daily task digest to Telegram
#
# Usage:
#   ./daily-digest.sh              # Morning digest
#   ./daily-digest.sh --preview    # Preview without sending
#   ./daily-digest.sh --evening    # Evening summary
#   ./daily-digest.sh --weekly     # Weekly review
#
# Cron:
#   0 8 * * * ~/.openclaw/scripts/daily-digest.sh
#   0 20 * * * ~/.openclaw/scripts/daily-digest.sh --evening
#   0 10 * * 0 ~/.openclaw/scripts/daily-digest.sh --weekly
#
# Required env vars:
#   TELEGRAM_BOT_TOKEN, TELEGRAM_GROUP_ID, TELEGRAM_TOPIC_DAILY
#
# See docs/TELEGRAM-DIGEST.md for setup.

set -e

# ============================================================
# Configuration
# ============================================================

OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
WORKSPACE="$OPENCLAW_HOME/workspace"

# Load credentials
if [ -f "$OPENCLAW_HOME/credentials/.env" ]; then
    set -a
    source "$OPENCLAW_HOME/credentials/.env"
    set +a
fi

# Fallback: security-alerts.env (legacy)
if [ -f "$OPENCLAW_HOME/security-alerts.env" ]; then
    source "$OPENCLAW_HOME/security-alerts.env"
fi

DAILY_TOPIC_ID="${TELEGRAM_TOPIC_DAILY:-12}"
WEATHER_CITY="${WEATHER_CITY:-London}"

# Dates
TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)
DAY_OF_WEEK=$(date +%A)
DATE_DISPLAY=$(date +"%B %-d, %Y")

# ============================================================
# Data collection functions
# ============================================================

count_tasks() {
    local file="$1"
    local pattern="$2"
    grep -cE "$pattern" "$file" 2>/dev/null || echo "0"
}

get_tasks() {
    local file="$1"
    local pattern="$2"
    local limit="${3:-5}"
    grep -E "$pattern" "$file" 2>/dev/null | head -$limit | \
        sed 's/^- \[ \] /• /' | \
        sed 's/^- \[x\] /• ✅ /'
}

get_overdue() {
    local todo_file="$WORKSPACE/topics/tasks/TODO.md"
    [ ! -f "$todo_file" ] && return

    grep -E "@due\([0-9]{4}-[0-9]{2}-[0-9]{2}\)" "$todo_file" 2>/dev/null | \
    while IFS= read -r line; do
        due_date=$(echo "$line" | grep -oE "@due\([0-9]{4}-[0-9]{2}-[0-9]{2}\)" | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2}")
        if [[ -n "$due_date" && "$due_date" < "$TODAY" ]]; then
            echo "$line" | sed 's/^- \[ \] /• ⏰ /'
        fi
    done | head -3
}

get_focus() {
    local memory_file="$WORKSPACE/MEMORY.md"
    [ ! -f "$memory_file" ] && echo "Not set" && return

    grep -A 5 "## 🎯" "$memory_file" 2>/dev/null | \
        grep "^-" | head -1 | sed 's/^- //' || echo "Not set"
}

count_done_yesterday() {
    local done_file="$WORKSPACE/topics/tasks/DONE.md"
    [ ! -f "$done_file" ] && echo "0" && return

    awk "/## $YESTERDAY/,/## [0-9]{4}-[0-9]{2}-[0-9]{2}/" "$done_file" 2>/dev/null | \
        grep -c "^\- \[x\]" || echo "0"
}

count_voice() {
    local voice_file="$WORKSPACE/topics/voice/transcripts/$YESTERDAY.md"
    [ ! -f "$voice_file" ] && echo "0" && return
    grep -c "^## " "$voice_file" 2>/dev/null || echo "0"
}

count_new_ideas() {
    local ideas_file="$WORKSPACE/topics/ideas/IDEAS.md"
    [ ! -f "$ideas_file" ] && echo "0" && return

    grep -c "$TODAY\|$YESTERDAY" "$ideas_file" 2>/dev/null || echo "0"
}

get_weather() {
    local weather
    weather=$(curl -s --max-time 5 "https://wttr.in/${WEATHER_CITY}?format=%c+%t+(%f)+%w" 2>/dev/null)
    if [ -z "$weather" ] || echo "$weather" | grep -qi "unknown\|error\|sorry"; then
        echo "unavailable"
        return
    fi
    echo "$weather"
}

# ============================================================
# Digest generators
# ============================================================

generate_morning_digest() {
    local todo_file="$WORKSPACE/topics/tasks/TODO.md"

    local tasks_count=$(count_tasks "$todo_file" "^- \[ \]")
    local done_count=$(count_done_yesterday)
    local voice_count=$(count_voice)
    local ideas_count=$(count_new_ideas)
    local focus=$(get_focus)

    local urgent_tasks=$(get_tasks "$todo_file" "P1\|@due\($TODAY\)" 3)
    local other_tasks=$(get_tasks "$todo_file" "^- \[ \]" 5)
    local overdue=$(get_overdue)
    local overdue_count=$(echo "$overdue" | grep -c "•" 2>/dev/null || echo "0")

    local weather=$(get_weather)

    DIGEST="☀️ <b>Good morning! $DAY_OF_WEEK, $DATE_DISPLAY</b>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🌤 <b>Weather ($WEATHER_CITY)</b>
$weather

━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ "$tasks_count" -gt 0 ]; then
        DIGEST="$DIGEST

📋 <b>Tasks ($tasks_count)</b>
$other_tasks"
    else
        DIGEST="$DIGEST

📋 <b>Tasks</b>
No active tasks ✨"
    fi

    if [ "$overdue_count" -gt 0 ] && [ -n "$overdue" ]; then
        DIGEST="$DIGEST

⚠️ <b>Overdue ($overdue_count)</b>
$overdue"
    fi

    DIGEST="$DIGEST

━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ "$ideas_count" -gt 0 ]; then
        DIGEST="$DIGEST

💡 <b>New ideas ($ideas_count)</b>"
    fi

    DIGEST="$DIGEST

📊 <b>Yesterday</b>
• ✅ Completed: $done_count
• 🎤 Voice messages: $voice_count

━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🎯 <b>Focus of the day</b>
$focus

━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Have a great day! 🚀"

    echo "$DIGEST"
}

generate_evening_digest() {
    local done_file="$WORKSPACE/topics/tasks/DONE.md"
    local todo_file="$WORKSPACE/topics/tasks/TODO.md"

    local done_today=$(awk "/## $TODAY/,/## [0-9]{4}-[0-9]{2}-[0-9]{2}/" "$done_file" 2>/dev/null | \
        grep "^\- \[x\]" | head -5 | sed 's/^- \[x\] /• ✅ /')
    local done_count=$(echo "$done_today" | grep -c "•" 2>/dev/null || echo "0")

    local not_done=$(get_tasks "$todo_file" "@due\($TODAY\)" 3)
    local not_done_count=$(echo "$not_done" | grep -c "•" 2>/dev/null || echo "0")

    local tomorrow=$(date -d "tomorrow" +%Y-%m-%d 2>/dev/null || date -v+1d +%Y-%m-%d)
    local tomorrow_tasks=$(get_tasks "$todo_file" "@due\($tomorrow\)\|P1" 3)

    DIGEST="🌙 <b>Evening Summary — $DATE_DISPLAY</b>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ <b>Completed today ($done_count)</b>"

    if [ -n "$done_today" ]; then
        DIGEST="$DIGEST
$done_today"
    else
        DIGEST="$DIGEST
No tasks marked as done"
    fi

    if [ "$not_done_count" -gt 0 ] && [ -n "$not_done" ]; then
        DIGEST="$DIGEST

❌ <b>Not completed ($not_done_count)</b>
$not_done"
    fi

    DIGEST="$DIGEST

━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 <b>Tomorrow</b>"

    if [ -n "$tomorrow_tasks" ]; then
        DIGEST="$DIGEST
$tomorrow_tasks"
    else
        DIGEST="$DIGEST
No tasks scheduled"
    fi

    DIGEST="$DIGEST

━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Rest well! 😴"

    echo "$DIGEST"
}

generate_weekly_digest() {
    local done_file="$WORKSPACE/topics/tasks/DONE.md"

    local week_done=$(grep -c "\[x\]" "$done_file" 2>/dev/null || echo "0")

    DIGEST="📊 <b>Weekly Review</b>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ <b>Completed this week: $week_done tasks</b>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━

💡 <b>Ideas</b>
Check topics/ideas/IDEAS.md

━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🎯 <b>Focus for next week</b>
$(get_focus)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Have a great week! 🚀"

    echo "$DIGEST"
}

# ============================================================
# Send to Telegram
# ============================================================

send_to_telegram() {
    local message="$1"

    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_GROUP_ID" ]; then
        echo "ERROR: Telegram credentials not configured"
        echo "Set TELEGRAM_BOT_TOKEN and TELEGRAM_GROUP_ID in credentials/.env"
        return 1
    fi

    local response=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_GROUP_ID}" \
        -d "message_thread_id=${DAILY_TOPIC_ID}" \
        -d "parse_mode=HTML" \
        --data-urlencode "text=$message")

    if echo "$response" | grep -q '"ok":true'; then
        echo "Sent to Telegram (topic $DAILY_TOPIC_ID)"
    else
        echo "Failed to send: $response"
        return 1
    fi
}

save_digest() {
    local message="$1"
    local type="$2"

    local dir="$WORKSPACE/topics/daily"
    mkdir -p "$dir"

    local file="$dir/$TODAY.md"

    echo "# $type - $TODAY" > "$file"
    echo "" >> "$file"
    echo "$message" | sed 's/<[^>]*>//g' >> "$file"

    echo "Saved to $file"
}

# ============================================================
# Main
# ============================================================

main() {
    local mode="${1:-morning}"
    local preview=false

    case "$1" in
        --preview)
            preview=true
            mode="morning"
            ;;
        --evening)
            mode="evening"
            ;;
        --weekly)
            mode="weekly"
            ;;
        --help|-h)
            echo "Usage: $0 [--preview|--evening|--weekly]"
            exit 0
            ;;
    esac

    echo "=== Daily Digest ($mode) ==="
    echo "Date: $TODAY"
    echo ""

    case "$mode" in
        morning)
            digest=$(generate_morning_digest)
            ;;
        evening)
            digest=$(generate_evening_digest)
            ;;
        weekly)
            digest=$(generate_weekly_digest)
            ;;
    esac

    if [ "$preview" = true ]; then
        echo "=== PREVIEW ==="
        echo "$digest" | sed 's/<[^>]*>//g'
        echo ""
        echo "=== END PREVIEW ==="
    else
        save_digest "$digest" "$mode"
        send_to_telegram "$digest"
    fi

    echo ""
    echo "Done!"
}

main "$@"
