#!/bin/bash
# Voice transcription using whisper.cpp
# Usage: transcribe.sh <audio_file> [language]
# Output: transcript text on stdout, ERROR:<CATEGORY>:<detail> on failure
#
# Prerequisites:
#   - whisper.cpp compiled (with or without CUDA)
#   - ffmpeg installed
#   - Model downloaded to ~/whisper.cpp/models/
#
# See docs/VOICE-TRANSCRIPTION.md for setup instructions.

set -uo pipefail

WHISPER_DIR="${WHISPER_DIR:-$HOME/whisper.cpp}"
MODEL="${WHISPER_MODEL:-$WHISPER_DIR/models/ggml-large-v3-turbo.bin}"
WHISPER_CLI="${WHISPER_CLI:-$WHISPER_DIR/build/bin/whisper-cli}"
STDERR_LOG="/tmp/whisper_err_$$.log"
TEMP_WAV=""

cleanup() {
    rm -f "$STDERR_LOG" "$TEMP_WAV"
}
trap cleanup EXIT

# --- Argument check ---
if [ $# -lt 1 ]; then
    echo "ERROR:USAGE:No audio file argument provided"
    exit 0
fi

AUDIO_FILE="$1"
LANGUAGE="${2:-en}"

if [ ! -f "$AUDIO_FILE" ]; then
    echo "ERROR:FILE_NOT_FOUND:$AUDIO_FILE"
    exit 0
fi

# --- Prerequisite checks ---
if ! command -v ffmpeg &>/dev/null; then
    echo "ERROR:FFMPEG_MISSING:ffmpeg not found in PATH"
    exit 0
fi

if [ ! -x "$WHISPER_CLI" ]; then
    echo "ERROR:WHISPER_MISSING:whisper-cli not found at $WHISPER_CLI"
    exit 0
fi

if [ ! -f "$MODEL" ]; then
    echo "ERROR:MODEL_MISSING:Model not found at $MODEL"
    exit 0
fi

# --- Disk space check (100MB minimum) ---
AVAIL_KB=$(df /tmp 2>/dev/null | tail -1 | awk '{print $4}')
if [ -n "$AVAIL_KB" ] && [ "$AVAIL_KB" -lt 102400 ] 2>/dev/null; then
    echo "ERROR:DISK_FULL:Less than 100MB free in /tmp (${AVAIL_KB}KB available)"
    exit 0
fi

# --- CUDA library path (if available) ---
for cuda_dir in /usr/local/cuda/lib64 /usr/local/cuda-*/lib64; do
    if [ -d "$cuda_dir" ]; then
        export LD_LIBRARY_PATH="${cuda_dir}:${LD_LIBRARY_PATH:-}"
        break
    fi
done

# --- Convert OGG/OGA to WAV (Telegram sends voice as OGG) ---
if [[ "$AUDIO_FILE" == *.ogg ]] || [[ "$AUDIO_FILE" == *.oga ]]; then
    TEMP_WAV="/tmp/whisper_$$.wav"
    if ! ffmpeg -i "$AUDIO_FILE" -ar 16000 -ac 1 -c:a pcm_s16le "$TEMP_WAV" -y -loglevel error 2>"$STDERR_LOG"; then
        ERR_DETAIL=$(head -c 500 "$STDERR_LOG")
        echo "ERROR:FFMPEG_FAILED:$ERR_DETAIL"
        exit 0
    fi
    AUDIO_FILE="$TEMP_WAV"
fi

# --- Run whisper ---
TRANSCRIPT=$("$WHISPER_CLI" -m "$MODEL" -f "$AUDIO_FILE" -l "$LANGUAGE" --no-timestamps -np 2>"$STDERR_LOG" | tail -n +1 | grep -v "^$" | head -1)
WHISPER_EXIT=$?

if [ $WHISPER_EXIT -ne 0 ] || [ -z "$TRANSCRIPT" ]; then
    ERR_DETAIL=$(head -c 500 "$STDERR_LOG")
    if echo "$ERR_DETAIL" | grep -qi "out of memory\|OOM"; then
        echo "ERROR:GPU_OOM:$ERR_DETAIL"
    elif echo "$ERR_DETAIL" | grep -qi "cuda\|cublas\|gpu\|nvrm"; then
        echo "ERROR:CUDA_ERROR:$ERR_DETAIL"
    elif [ -z "$TRANSCRIPT" ] && [ $WHISPER_EXIT -eq 0 ]; then
        echo "ERROR:EMPTY_RESULT:Whisper produced no output"
    else
        echo "ERROR:WHISPER_FAILED:$ERR_DETAIL"
    fi
    exit 0
fi

echo "$TRANSCRIPT"
