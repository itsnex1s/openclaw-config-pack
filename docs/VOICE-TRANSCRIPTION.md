# Voice Message Transcription

Automatic voice message transcription using local GPU-accelerated [whisper.cpp](https://github.com/ggerganov/whisper.cpp).

---

## How It Works

```
Voice message in Telegram
    |
    v
[voice-transcriber plugin] --> downloads audio via Bot API
    |
    v
[transcribe.sh] --> ffmpeg (OGG -> WAV) --> whisper-cli (GPU/CPU)
    |
    v
Transcript injected into message --> agent sees it as text
    |
    v (Voice topic only)
Saved to topics/voice/transcripts/YYYY-MM-DD.md
```

- **Voice topic (7)**: transcript is saved to daily file + agent processes it
- **Any other topic**: transcript is injected as text, agent responds normally

---

## Setup

### 1. Install prerequisites

```bash
# FFmpeg (required for OGG -> WAV conversion)
sudo apt-get install -y ffmpeg

# CUDA toolkit (optional, for GPU acceleration)
# See: https://developer.nvidia.com/cuda-downloads
# Verify: nvidia-smi
```

### 2. Build whisper.cpp

```bash
cd ~
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp

# With CUDA (recommended if you have NVIDIA GPU):
cmake -B build -DGGML_CUDA=1
cmake --build build -j$(nproc) --config Release

# Without CUDA (CPU only, slower):
# cmake -B build
# cmake --build build -j$(nproc) --config Release

# Verify
./build/bin/whisper-cli --help
```

### 3. Download model

```bash
cd ~/whisper.cpp

# Large v3 turbo (~1.6GB, best quality, fast with GPU)
sh ./models/download-ggml-model.sh large-v3-turbo

# Or smaller models for limited hardware:
# sh ./models/download-ggml-model.sh base        # ~142MB
# sh ./models/download-ggml-model.sh small       # ~466MB
# sh ./models/download-ggml-model.sh medium      # ~1.5GB
```

### 4. Test transcription

```bash
# Record or use any audio file
~/.openclaw/scripts/tools/transcribe.sh /path/to/audio.ogg en

# Or test whisper directly
~/whisper.cpp/build/bin/whisper-cli \
  -m ~/whisper.cpp/models/ggml-large-v3-turbo.bin \
  -f audio.wav -l en
```

### 5. Install the plugin

The installer copies the plugin automatically if you choose to install extensions. To install manually:

```bash
cp -r extensions/voice-transcriber \
  ~/.openclaw/workspace/.openclaw/extensions/

cp scripts/tools/transcribe.sh ~/.openclaw/scripts/tools/
chmod +x ~/.openclaw/scripts/tools/transcribe.sh
```

### 6. Enable in config

Add to `openclaw.json` under `plugins.entries`:

```json
{
  "plugins": {
    "entries": {
      "voice-transcriber": {
        "enabled": true,
        "config": {
          "voiceTopicId": "7",
          "transcriptsPath": "topics/voice/transcripts",
          "language": "en"
        }
      }
    }
  }
}
```

### 7. Restart gateway

```bash
# Restart to load the new plugin
tmux send-keys -t gw C-c
# Wait for restart, then verify:
grep "voice-transcriber" /tmp/gw.log
```

You should see:
```
[voice-transcriber] Plugin loaded (topic: 7, lang: en)
[voice-transcriber] Hooks registered
```

---

## Configuration

### Plugin config (`openclaw.json`)

| Key | Default | Description |
|-----|---------|-------------|
| `voiceTopicId` | `"7"` | Topic ID where transcripts are saved to file |
| `transcriptsPath` | `"topics/voice/transcripts"` | Workspace-relative path for daily transcript files |
| `language` | `"en"` | Default language code (`en`, `ru`, `de`, `fr`, etc.) |

### Environment variables

| Variable | Required | Description |
|----------|----------|-------------|
| `TELEGRAM_BOT_TOKEN` | Yes | For downloading voice files from Telegram |
| `VOICE_TOPIC_ID` | No | Override voice topic ID (default: from plugin config) |
| `WHISPER_DIR` | No | Path to whisper.cpp (default: `~/whisper.cpp`) |
| `WHISPER_MODEL` | No | Path to model file (default: `~/whisper.cpp/models/ggml-large-v3-turbo.bin`) |
| `WHISPER_CLI` | No | Path to whisper-cli binary (default: `~/whisper.cpp/build/bin/whisper-cli`) |

### Using a different model

To use a smaller/different model, set `WHISPER_MODEL` in your `.env`:

```bash
# In ~/.openclaw/credentials/.env
WHISPER_MODEL=$HOME/whisper.cpp/models/ggml-base.bin
```

Or override in `transcribe.sh` environment.

---

## Transcript Format

Daily files in `topics/voice/transcripts/`:

```markdown
## 14:30

Transcribed text from first voice message...

## 15:45

Transcribed text from second voice message...
```

---

## Performance

| GPU | Model | Speed |
|-----|-------|-------|
| RTX 3070 (8GB) | large-v3-turbo | ~0.3s per second of audio |
| RTX 3060 (12GB) | large-v3-turbo | ~0.4s per second of audio |
| CPU only (8 cores) | base | ~1s per second of audio |
| CPU only (8 cores) | large-v3-turbo | ~8s per second of audio |

Model load time: ~3-4s on first run (cached after).

---

## Manual Transcription Tool

The plugin registers a `transcribe_audio` tool the agent can call:

```json
{
  "name": "transcribe_audio",
  "parameters": {
    "audioUrl": "https://...",
    "audioPath": "/path/to/file.ogg",
    "language": "en"
  }
}
```

---

## Troubleshooting

### Plugin says "Script not found"

```bash
# Verify transcribe.sh exists and is executable
ls -la ~/.openclaw/scripts/tools/transcribe.sh
chmod +x ~/.openclaw/scripts/tools/transcribe.sh
```

### CUDA not found

```bash
# Add CUDA to your PATH
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

# Verify
nvidia-smi
```

### FFmpeg not installed

```bash
sudo apt-get install -y ffmpeg
ffmpeg -version
```

### Model not downloaded

```bash
cd ~/whisper.cpp
sh ./models/download-ggml-model.sh large-v3-turbo
ls -lh models/ggml-large-v3-turbo.bin
# Should be ~1.6GB
```

### Transcription is slow (CPU fallback)

If whisper.cpp was built without CUDA, it falls back to CPU. Rebuild:

```bash
cd ~/whisper.cpp
rm -rf build
cmake -B build -DGGML_CUDA=1
cmake --build build -j$(nproc) --config Release
```

### GPU out of memory

Use a smaller model:

```bash
# Download base model (~142MB, needs ~500MB VRAM)
sh ~/whisper.cpp/models/download-ggml-model.sh base

# Update .env
echo 'WHISPER_MODEL=$HOME/whisper.cpp/models/ggml-base.bin' >> ~/.openclaw/credentials/.env
```

### Voice messages not being transcribed

1. Check plugin loaded: `grep "voice-transcriber" /tmp/gw.log`
2. Check for errors: `grep -i "error" /tmp/gw.log | grep voice`
3. Verify bot token is set: `echo $TELEGRAM_BOT_TOKEN`
4. Test manually: `~/.openclaw/scripts/tools/transcribe.sh test.ogg en`

---

## File Structure

```
~/whisper.cpp/                         # Whisper installation
├── build/bin/whisper-cli              # Main binary
└── models/
    └── ggml-large-v3-turbo.bin        # Model (~1.6GB)

~/.openclaw/
├── scripts/
│   └── tools/
│       └── transcribe.sh              # Wrapper script
└── workspace/
    ├── .openclaw/extensions/voice-transcriber/
    │   ├── index.ts                   # Plugin code
    │   ├── openclaw.plugin.json       # Manifest
    │   └── package.json
    └── topics/voice/transcripts/
        └── YYYY-MM-DD.md             # Daily transcripts
```

---

## Dependencies

| Dependency | Required | Purpose |
|-----------|----------|---------|
| [whisper.cpp](https://github.com/ggerganov/whisper.cpp) | Yes | Speech-to-text engine |
| ffmpeg | Yes | OGG to WAV conversion |
| CUDA Toolkit | No | GPU acceleration (10-20x faster) |
| NVIDIA GPU | No | For CUDA support |
