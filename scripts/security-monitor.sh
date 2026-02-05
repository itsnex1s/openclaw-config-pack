#!/bin/bash
# security-monitor.sh - OpenClaw security monitoring
#
# Sends to Telegram ONLY:
#   1. Critical alerts — real security incidents
#   2. Daily digest (--digest) — daily summary
#
# Usage:
#   ./security-monitor.sh              # Check logs (alert on incidents)
#   ./security-monitor.sh --digest     # Daily security summary
#   ./security-monitor.sh --test       # Test message
#
# Cron:
#   */15 * * * * ~/.openclaw/scripts/security-monitor.sh
#   0 12 * * *   ~/.openclaw/scripts/security-monitor.sh --digest

set -e

# ============================================================
# Configuration
# ============================================================

OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
CONFIG_FILE="${SECURITY_CONFIG:-$OPENCLAW_HOME/security-alerts.env}"
STATE_FILE="$OPENCLAW_HOME/.security-monitor-state"
COUNTERS_FILE="$OPENCLAW_HOME/.security-counters"
LOG_DIR="$OPENCLAW_HOME/logs"
LOCAL_LOG="$LOG_DIR/security-monitor.log"
LOCK_FILE="/tmp/openclaw-security-monitor.lock"

# ============================================================
# Initialization
# ============================================================

mkdir -p "$LOG_DIR"

local_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOCAL_LOG"
}

check_lock() {
    if [ -f "$LOCK_FILE" ]; then
        PID=$(cat "$LOCK_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            exit 0
        fi
    fi
    echo $$ > "$LOCK_FILE"
    trap "rm -f $LOCK_FILE" EXIT
}

load_config() {
    [ ! -f "$CONFIG_FILE" ] && exit 1
    source "$CONFIG_FILE"
    [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_GROUP_ID" ] && exit 1
}

# ============================================================
# Telegram — send only critical + digest
# ============================================================

send_telegram() {
    local text="$1"

    local params="chat_id=${TELEGRAM_GROUP_ID}&parse_mode=HTML"
    [ -n "$TELEGRAM_TOPIC_ID" ] && params+="&message_thread_id=${TELEGRAM_TOPIC_ID}"

    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "$params" \
        --data-urlencode "text=$text" > /dev/null 2>&1
}

# ============================================================
# State tracking
# ============================================================

get_last_position() {
    local key=$(echo "$1" | md5sum | cut -d' ' -f1)
    [ -f "$STATE_FILE" ] && grep "^$key:" "$STATE_FILE" 2>/dev/null | cut -d: -f2 || echo "0"
}

save_position() {
    local key=$(echo "$1" | md5sum | cut -d' ' -f1)
    local position="$2"
    if [ -f "$STATE_FILE" ]; then
        grep -v "^$key:" "$STATE_FILE" > "$STATE_FILE.tmp" 2>/dev/null || true
        mv "$STATE_FILE.tmp" "$STATE_FILE"
    fi
    echo "$key:$position" >> "$STATE_FILE"
}

# Counters for daily digest
increment_counter() {
    local name="$1"
    local count="${2:-1}"
    local today=$(date +%Y-%m-%d)

    # Format: date|name|count
    echo "$today|$name|$count" >> "$COUNTERS_FILE"
}

get_today_counts() {
    local today=$(date +%Y-%m-%d)
    [ ! -f "$COUNTERS_FILE" ] && return

    # Sum by category for today
    grep "^$today|" "$COUNTERS_FILE" 2>/dev/null | \
        awk -F'|' '{counts[$2]+=$3} END {for (k in counts) print k ": " counts[k]}' | \
        sort
}

clean_old_counters() {
    local cutoff=$(date -d "3 days ago" +%Y-%m-%d 2>/dev/null || date -v-3d +%Y-%m-%d)
    [ ! -f "$COUNTERS_FILE" ] && return
    awk -F'|' -v cutoff="$cutoff" '$1 >= cutoff' "$COUNTERS_FILE" > "$COUNTERS_FILE.tmp" 2>/dev/null || true
    mv "$COUNTERS_FILE.tmp" "$COUNTERS_FILE" 2>/dev/null || true
}

# ============================================================
# Log monitoring — critical events only
# ============================================================

monitor_logs() {
    # CRITICAL: send to Telegram immediately
    local critical_patterns=(
        "auth\.failed"
        "allowFrom.*denied"
        "sandbox.*escape"
        "sandbox.*violation"
    )

    # WARN: count in stats, do NOT send to Telegram
    local warn_patterns=(
        "inputFilter.*reject"
        "rejectPatterns.*matched"
        "rate.limit.*exceeded"
    )

    for logfile in "$LOG_DIR"/*.log "$LOG_DIR"/*.jsonl; do
        [ -f "$logfile" ] || continue

        local last_pos=$(get_last_position "$logfile")
        local current_lines=$(wc -l < "$logfile" 2>/dev/null || echo 0)
        [ "$current_lines" -le "$last_pos" ] && continue

        local new_content
        new_content=$(tail -n +"$((last_pos + 1))" "$logfile" 2>/dev/null || true)
        [ -z "$new_content" ] && { save_position "$logfile" "$current_lines"; continue; }

        local fname=$(basename "$logfile")

        # --- Critical: immediate alert ---
        for pattern in "${critical_patterns[@]}"; do
            local matches
            matches=$(echo "$new_content" | grep -iE "$pattern" 2>/dev/null || true)
            [ -z "$matches" ] && continue

            local count=$(echo "$matches" | wc -l)
            local sample=$(echo "$matches" | head -2 | head -c 300)

            local category=""
            case "$pattern" in
                *auth*)    category="AUTH_FAIL" ;;
                *allow*)   category="ALLOWLIST_DENY" ;;
                *sandbox*) category="SANDBOX" ;;
            esac

            increment_counter "$category" "$count"
            local_log "CRITICAL [$category] $count events in $fname"

            send_telegram "🚨 <b>Security Alert</b>

<b>Level:</b> CRITICAL
<b>Category:</b> $category
<b>Events:</b> $count
<b>File:</b> $fname

<pre>$(echo "$sample" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')</pre>"
        done

        # --- Warn: counters only ---
        for pattern in "${warn_patterns[@]}"; do
            local matches
            matches=$(echo "$new_content" | grep -iE "$pattern" 2>/dev/null || true)
            [ -z "$matches" ] && continue

            local count=$(echo "$matches" | wc -l)
            local category=""
            case "$pattern" in
                *inputFilter*|*rejectPatterns*) category="INPUT_FILTERED" ;;
                *rate*)                          category="RATE_LIMITED" ;;
            esac

            increment_counter "$category" "$count"
            local_log "WARN [$category] $count events in $fname"
        done

        save_position "$logfile" "$current_lines"
    done
}

# ============================================================
# System health — critical only
# ============================================================

check_system() {
    local issues=""

    # Disk > 90%
    if [ -d "$OPENCLAW_HOME" ]; then
        local disk=$(df "$OPENCLAW_HOME" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%' || echo "0")
        [ "$disk" -gt 90 ] && issues+="• Disk: ${disk}%\n"
    fi

    # Memory > 95%
    if command -v free &> /dev/null; then
        local mem=$(free 2>/dev/null | grep Mem | awk '{printf "%.0f", $3/$2 * 100}' || echo "0")
        [ "$mem" -gt 95 ] && issues+="• Memory: ${mem}%\n"
    fi

    # Gateway not running
    if ! pgrep -f "openclaw.*gateway" > /dev/null 2>&1; then
        if ! docker ps 2>/dev/null | grep -q openclaw; then
            issues+="• Gateway not running\n"
        fi
    fi

    if [ -n "$issues" ]; then
        local_log "SYSTEM issues: $issues"
        send_telegram "🚨 <b>System Alert</b>

$issues

<i>$(date '+%Y-%m-%d %H:%M:%S')</i>"
    fi
}

# ============================================================
# Daily digest — quiet summary once a day
# ============================================================

send_digest() {
    local counts=$(get_today_counts)
    local today=$(date '+%d.%m.%Y')

    # System status
    local gw_status="stopped"
    if pgrep -f "openclaw.*gateway" > /dev/null 2>&1 || docker ps 2>/dev/null | grep -q openclaw; then
        gw_status="running"
    fi

    local disk=$(df "$OPENCLAW_HOME" 2>/dev/null | tail -1 | awk '{print $5}' || echo "?")
    local uptime_str=$(uptime -p 2>/dev/null || uptime | sed 's/.*up /up /' | cut -d, -f1)

    local text="🔒 <b>Security Digest — $today</b>

<b>System:</b>
• Gateway: $gw_status
• Disk: $disk
• Uptime: $uptime_str"

    if [ -n "$counts" ]; then
        text+="

<b>Events today:</b>
$(echo "$counts" | sed 's/^/• /')"
    else
        text+="

<b>Events today:</b> none"
    fi

    text+="

<i>$(date '+%H:%M:%S')</i>"

    send_telegram "$text"
    local_log "DIGEST sent"
    clean_old_counters
}

# ============================================================
# Main
# ============================================================

main() {
    check_lock
    load_config

    case "${1:-}" in
        --test)
            send_telegram "🧪 <b>Test</b> — security monitor OK.

<i>$(date '+%Y-%m-%d %H:%M:%S')</i>"
            ;;
        --digest)
            send_digest
            ;;
        *)
            monitor_logs
            check_system
            ;;
    esac
}

main "$@"
