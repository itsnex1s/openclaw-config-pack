#!/bin/bash
# crypto-prices.sh — Fetch crypto & NFT prices and send to Telegram
#
# Usage:
#   ./crypto-prices.sh              # Send prices to Telegram
#   ./crypto-prices.sh --preview    # Preview without sending
#
# Cron:
#   0 10 * * * ~/.openclaw/scripts/notify/crypto-prices.sh >> ~/.openclaw/logs/crypto-prices.log 2>&1
#
# Required env vars:
#   TELEGRAM_BOT_TOKEN, TELEGRAM_GROUP_ID
#
# Optional env vars:
#   CRYPTO_COINS     — comma-separated CoinGecko coin IDs (default: bitcoin,ethereum)
#   CRYPTO_NFTS      — comma-separated CoinGecko NFT IDs (default: empty)
#   TELEGRAM_TOPIC_DAILY — topic ID for daily messages (default: 12)
#
# API: CoinGecko free tier (no key required, 30 calls/min)

set -e

# ============================================================
# Configuration
# ============================================================

OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"

# Load credentials
if [ -f "$OPENCLAW_HOME/credentials/.env" ]; then
    set -a
    source "$OPENCLAW_HOME/credentials/.env"
    set +a
fi

DAILY_TOPIC_ID="${TELEGRAM_TOPIC_DAILY:-12}"
COINS="${CRYPTO_COINS:-bitcoin,ethereum}"
NFTS="${CRYPTO_NFTS:-}"

COINGECKO_API="https://api.coingecko.com/api/v3"
TODAY=$(date +"%Y-%m-%d %H:%M")

# ============================================================
# Helpers
# ============================================================

# Emoji based on 24h change
get_emoji() {
    local change="$1"
    # Remove minus sign for comparison
    local abs="${change#-}"

    if (( $(echo "$change > 5" | bc -l 2>/dev/null || echo 0) )); then
        echo "🚀"
    elif (( $(echo "$change > 0" | bc -l 2>/dev/null || echo 0) )); then
        echo "📈"
    elif (( $(echo "$change > -0.05" | bc -l 2>/dev/null || echo 0) )); then
        echo "➡️"
    elif (( $(echo "$change > -5" | bc -l 2>/dev/null || echo 0) )); then
        echo "📉"
    else
        echo "💥"
    fi
}

# Smart price formatting — adapts decimals based on magnitude
format_price() {
    local price="$1"

    if (( $(echo "$price >= 1000" | bc -l 2>/dev/null || echo 0) )); then
        printf "%8.0f" "$price"
    elif (( $(echo "$price >= 1" | bc -l 2>/dev/null || echo 0) )); then
        printf "%8.2f" "$price"
    elif (( $(echo "$price >= 0.01" | bc -l 2>/dev/null || echo 0) )); then
        printf "%8.4f" "$price"
    else
        printf "%8.6f" "$price"
    fi
}

# Truncate or pad name to fixed width
format_name() {
    local name="$1"
    local width="${2:-5}"
    printf "%-${width}s" "${name:0:$width}"
}

# ============================================================
# Fetch crypto prices
# ============================================================

fetch_crypto() {
    local coins_param="${COINS//,/%2C}"
    local response

    response=$(curl -s --max-time 15 \
        "${COINGECKO_API}/simple/price?ids=${coins_param}&vs_currencies=usd&include_24hr_change=true" 2>/dev/null)

    if [ -z "$response" ] || echo "$response" | grep -q '"error"'; then
        echo "Error fetching crypto prices"
        return 1
    fi

    local output=""
    local IFS=','
    for coin in $COINS; do
        local price=$(echo "$response" | jq -r ".\"${coin}\".usd // empty" 2>/dev/null)
        local change=$(echo "$response" | jq -r ".\"${coin}\".usd_24h_change // 0" 2>/dev/null)

        if [ -z "$price" ] || [ "$price" = "null" ]; then
            continue
        fi

        local emoji=$(get_emoji "$change")
        local formatted_price=$(format_price "$price")
        local name=$(format_name "${coin^^}" 5)
        local formatted_change=$(printf "%+5.1f%%" "$change")

        output="${output}${name} \$ ${formatted_price} ${emoji} ${formatted_change}\n"
    done

    echo -e "$output"
}

# ============================================================
# Fetch NFT floor prices
# ============================================================

fetch_nfts() {
    if [ -z "$NFTS" ]; then
        return
    fi

    local output=""
    local IFS=','
    for nft in $NFTS; do
        local response
        response=$(curl -s --max-time 15 \
            "${COINGECKO_API}/nfts/${nft}" 2>/dev/null)

        if [ -z "$response" ] || echo "$response" | grep -q '"error"'; then
            continue
        fi

        local name=$(echo "$response" | jq -r '.name // empty' 2>/dev/null)
        local floor=$(echo "$response" | jq -r '.floor_price.native_currency // 0' 2>/dev/null)
        local change=$(echo "$response" | jq -r '.floor_price_24h_percentage_change.native_currency // 0' 2>/dev/null)

        if [ -z "$name" ] || [ "$name" = "null" ]; then
            continue
        fi

        local emoji=$(get_emoji "$change")
        local formatted_name=$(format_name "$name" 10)
        local formatted_floor=$(printf "%6.3f" "$floor")
        local formatted_change=$(printf "%+5.1f%%" "$change")

        output="${output}${formatted_name} ${formatted_floor} ETH ${emoji} ${formatted_change}\n"

        # Rate limit: 1s between NFT requests
        sleep 1
    done

    echo -e "$output"
}

# ============================================================
# Build message
# ============================================================

build_message() {
    local crypto_data
    crypto_data=$(fetch_crypto)

    local message="<b>Crypto &amp; NFT Prices</b>
<i>${TODAY}</i>
"

    if [ -n "$crypto_data" ]; then
        message="${message}
<b>Crypto:</b>
<pre>${crypto_data}</pre>"
    fi

    local nft_data
    nft_data=$(fetch_nfts)

    if [ -n "$nft_data" ]; then
        message="${message}
<b>NFT Floor:</b>
<pre>${nft_data}</pre>"
    fi

    message="${message}
<i>CoinGecko</i>"

    echo "$message"
}

# ============================================================
# Send to Telegram
# ============================================================

send_to_telegram() {
    local message="$1"

    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_GROUP_ID" ]; then
        echo "ERROR: TELEGRAM_BOT_TOKEN or TELEGRAM_GROUP_ID not set"
        return 1
    fi

    local response
    response=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_GROUP_ID}" \
        -d "message_thread_id=${DAILY_TOPIC_ID}" \
        -d "parse_mode=HTML" \
        --data-urlencode "text=$message")

    if echo "$response" | grep -q '"ok":true'; then
        echo "$(date +%Y-%m-%d\ %H:%M:%S) ✓ Prices sent to topic ${DAILY_TOPIC_ID}"
    else
        echo "$(date +%Y-%m-%d\ %H:%M:%S) ✗ Failed: $response"
        return 1
    fi
}

# ============================================================
# Main
# ============================================================

main() {
    local preview=false

    case "${1:-}" in
        --preview)
            preview=true
            ;;
        --help|-h)
            echo "Usage: $0 [--preview]"
            echo "  --preview    Show prices without sending to Telegram"
            exit 0
            ;;
    esac

    echo "$(date +%Y-%m-%d\ %H:%M:%S) === Crypto Prices ==="
    echo "  Coins: $COINS"
    [ -n "$NFTS" ] && echo "  NFTs:  $NFTS"

    local message
    message=$(build_message)

    if [ "$preview" = true ]; then
        echo ""
        echo "=== PREVIEW ==="
        echo "$message" | sed 's/<[^>]*>//g'
        echo "=== END PREVIEW ==="
    else
        send_to_telegram "$message"
    fi
}

main "$@"
