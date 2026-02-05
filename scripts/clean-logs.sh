#!/bin/bash
# clean-logs.sh - OpenClaw log and session cleanup
# Run via cron: 0 3 * * * ~/.openclaw/scripts/clean-logs.sh

set -e

OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
DAYS_TO_KEEP="${DAYS_TO_KEEP:-1}"

echo "=== OpenClaw Log Cleanup ==="
echo "Home: $OPENCLAW_HOME"
echo "Keep days: $DAYS_TO_KEEP"
echo ""

# Check directory exists
if [ ! -d "$OPENCLAW_HOME" ]; then
    echo "ERROR: $OPENCLAW_HOME not found"
    exit 1
fi

# Delete old logs
echo "Cleaning old logs..."
find "$OPENCLAW_HOME/logs" -name "*.log" -mtime +$DAYS_TO_KEEP -delete 2>/dev/null || true
find "$OPENCLAW_HOME/logs" -name "*.jsonl" -mtime +$DAYS_TO_KEEP -delete 2>/dev/null || true

# Delete old session transcripts
echo "Cleaning old session transcripts..."
find "$OPENCLAW_HOME/sessions" -name "*.jsonl" -mtime +$DAYS_TO_KEEP -delete 2>/dev/null || true
find "$OPENCLAW_HOME/sessions" -type d -empty -delete 2>/dev/null || true

# Clean cache
echo "Cleaning cache..."
rm -rf "$OPENCLAW_HOME/cache/"* 2>/dev/null || true

# Check for secret leaks in remaining logs
echo ""
echo "=== Security Check ==="

PATTERNS=(
    "sk-or-"
    "sk-ant-"
    "bot[0-9]\\+:"
    "ghp_"
    "AKIA"
)

ISSUES=0
for pattern in "${PATTERNS[@]}"; do
    FOUND=$(grep -r "$pattern" "$OPENCLAW_HOME/logs" 2>/dev/null | wc -l || echo 0)
    if [ "$FOUND" -gt 0 ]; then
        echo "WARNING: Found $FOUND potential secrets matching '$pattern'"
        ISSUES=$((ISSUES + 1))
    fi
done

if [ "$ISSUES" -eq 0 ]; then
    echo "OK: No secrets found in logs"
else
    echo ""
    echo "!!! $ISSUES security issues found !!!"
    echo "Consider deleting affected log files manually"
fi

# Statistics
echo ""
echo "=== Statistics ==="
echo "Logs size: $(du -sh "$OPENCLAW_HOME/logs" 2>/dev/null | cut -f1 || echo "0")"
echo "Sessions size: $(du -sh "$OPENCLAW_HOME/sessions" 2>/dev/null | cut -f1 || echo "0")"
echo "Total size: $(du -sh "$OPENCLAW_HOME" 2>/dev/null | cut -f1 || echo "0")"

echo ""
echo "Cleanup complete!"
