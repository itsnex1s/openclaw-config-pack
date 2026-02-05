# openclaw-config-pack

Hardened configuration pack for [OpenClaw](https://openclaw.ai) personal AI assistant.

Includes everything needed to deploy OpenClaw with full security configuration: 8 Telegram topic templates, 6 cognitive skills, hardened Docker/systemd deployment, and a 9-layer defense architecture.

---

## 9-Layer Security Architecture

```
Layer 1  │ Cloudflare WAF/DDoS        │ Network perimeter
Layer 2  │ UFW Firewall               │ Host firewall
Layer 3  │ Loopback-only binding      │ Gateway isolation
Layer 4  │ Telegram allowlist         │ User authentication
Layer 5  │ Input filter regex         │ Pattern-based rejection
Layer 6  │ CIF + prompt-guard         │ Cognitive injection defense
Layer 7  │ SOUL.md CRITICAL rules     │ Agent identity constraints
Layer 8  │ Docker sandbox             │ Execution isolation
Layer 9  │ Systemd hardening          │ Process isolation
```

---

## Quick Start

### 1. Clone

```bash
git clone https://github.com/itsnex1s/openclaw-config-pack.git
cd openclaw-config-pack
```

### 2. Run installer

```bash
chmod +x install.sh
./install.sh
```

The installer will:
- Generate a gateway password and token
- Copy workspace files (SOUL.md, SECURITY.md, skills)
- Create `.env` from template
- Set file permissions (chmod 600/700)
- Optionally install the systemd service

### 3. Edit configuration

```bash
nano ~/.openclaw/config/openclaw.json
```

Replace all `YOUR_*` placeholders:
- `YOUR_TELEGRAM_ID` — your Telegram user ID
- `YOUR_GROUP_ID` — your Telegram group ID
- Topic IDs — update to match your group's forum topics

### 4. Add credentials

```bash
nano ~/.openclaw/credentials/.env
```

Fill in your API keys and tokens.

### 5. Start

```bash
# With Docker:
cd ~/.openclaw && docker compose up -d

# Or with systemd:
sudo systemctl start openclaw
```

### 6. Voice transcription (optional)

To enable automatic voice message transcription, see [docs/VOICE-TRANSCRIPTION.md](docs/VOICE-TRANSCRIPTION.md). Quick version:

```bash
# Install ffmpeg
sudo apt-get install -y ffmpeg

# Build whisper.cpp (with CUDA if you have NVIDIA GPU)
git clone https://github.com/ggerganov/whisper.cpp.git ~/whisper.cpp
cd ~/whisper.cpp
cmake -B build -DGGML_CUDA=1    # or without -DGGML_CUDA=1 for CPU
cmake --build build -j$(nproc) --config Release

# Download model
sh ./models/download-ggml-model.sh large-v3-turbo

# Test
~/.openclaw/scripts/transcribe.sh /path/to/voice.ogg en
```

### 7. Channel & daily digest (optional)

To enable automatic channel summaries and daily task digests, see [docs/TELEGRAM-DIGEST.md](docs/TELEGRAM-DIGEST.md). Quick version:

```bash
# Set up Python environment
cd ~/.openclaw/scripts
python3 -m venv digest-venv
source digest-venv/bin/activate
pip install -r requirements-digest.txt

# Add API credentials to .env
# TELEGRAM_API_ID, TELEGRAM_API_HASH, GOOGLE_API_KEY

# Authenticate with Telegram (first run only)
python3 telegram-digest.py --auth

# Test channel digest
python3 telegram-digest.py --dry-run

# Test daily task digest
~/.openclaw/scripts/daily-digest.sh --preview

# Add cron jobs
# 30 8 * * * ~/.openclaw/scripts/telegram-digest-cron.sh
# 0 8 * * * ~/.openclaw/scripts/daily-digest.sh
# 0 20 * * * ~/.openclaw/scripts/daily-digest.sh --evening
```

---

## What's Included

### Configuration (`config/`)

| File | Description |
|------|-------------|
| `openclaw.json.template` | Full config with 8 topic templates, security rules, model config |
| `.env.example` | All environment variables with descriptions |
| `security-alerts.env.example` | Telegram alert bot configuration |

### Workspace (`workspace/`)

Core identity and security files deployed to `~/.openclaw/workspace/`.

| File | Description |
|------|-------------|
| `SOUL.md` | Agent identity, communication style, CRITICAL rules |
| `SECURITY.md` | Cognitive Integrity Framework (CIF) v1.0 — injection defense |

### Skills (`workspace/skills/`)

6 Markdown-based skills that extend agent behavior without code execution.

| Skill | Purpose |
|-------|---------|
| **prompt-guard** | Input message pre-processing, canary detection, encoding awareness |
| **skill-guard** | Security audit tool for evaluating third-party skills |
| **memory-manager** | Memory organization, archiving, cross-topic search |
| **task-manager** | Structured tasks with P1/P2/P3 priorities, deadlines, recurring |
| **voice-router** | Routes voice transcript content to appropriate topics |
| **weekly-review** | Weekly progress summary with trends and focus planning |

### Topic Templates

8 pre-configured Telegram forum topics:

| Topic | Purpose |
|-------|---------|
| General | Quick Q&A, routing to specialized topics |
| Voice | Voice message transcription and routing |
| Ideas | Idea capture with numbered tracking |
| Tasks | Structured task management |
| Daily | Day planning and summaries |
| Project | Per-project context, decisions, notes |
| Research | Structured research with file storage |
| Security | Security alerts (mention-only) |

Plus 2 plugin-driven topics: **Channel Digest** and **Bookmarks**.

### Deploy (`deploy/`)

| File | Description |
|------|-------------|
| `docker-compose.yml` | Hardened: read-only FS, cap_drop ALL, pids_limit 64, user 65534 |
| `systemd/openclaw.service` | Hardened: ProtectKernelTunables, LockPersonality, PrivateTmp |
| `cloudflared/config.yml` | Cloudflare Tunnel zero-trust access |

### Scripts (`scripts/`)

| Script | Purpose | Schedule |
|--------|---------|----------|
| `backup.sh` | GPG AES-256 encrypted backups, 30-day rotation | Sunday 03:00 |
| `clean-logs.sh` | Log rotation + secret leak detection | Daily 03:00 |
| `daily-check.sh` | Container health, security audit, resources | Daily |
| `daily-digest.sh` | Morning/evening/weekly task digest to Telegram | 08:00 + 20:00 |
| `security-monitor.sh` | Log monitoring, critical alerts to Telegram | Every 15 min |
| `task-ping.sh` | Send open tasks summary to Tasks topic | 10:00 + 18:00 |
| `crypto-prices.sh` | Crypto & NFT prices via CoinGecko (no API key) | Daily 10:00 |
| `telegram-digest.py` | Channel digest: collect, summarize via Gemini, send | Daily 08:30 |
| `telegram-digest-cron.sh` | Cron wrapper for channel digest | Daily 08:30 |
| `transcribe.sh` | whisper.cpp wrapper for voice transcription | On demand |
| `init-topics.sh` | Initialize workspace directory structure | Once |

### Extensions (`extensions/`)

Example plugins (TypeScript):

| Plugin | Description |
|--------|-------------|
| `voice-transcriber` | Automatic voice transcription via local whisper.cpp (GPU/CPU) |
| `bookmarks` | Save, list, and summarize web bookmarks |
| `telegram-digest` | Daily digest from subscribed Telegram channels (Telethon + Gemini) |
| `task-manager` | Task management commands: done, status, overdue, priority |

### Documentation (`docs/`)

| Path | Content |
|------|---------|
| `docs/architecture/` | 7 architecture documents (overview, security, components, data flow, plugins, operations, updates) |
| `docs/WSL2-SETUP.md` | Complete WSL2 setup guide (systemd, permissions, cron, GPU) |
| `docs/SECURITY_GUIDE.md` | Comprehensive security guide for OpenClaw deployment |
| `docs/VOICE-TRANSCRIPTION.md` | Voice transcription setup guide (whisper.cpp) |
| `docs/TELEGRAM-DIGEST.md` | Channel digest + daily task digest setup guide |
| `docs/PLUGIN-DEVELOPMENT.md` | Plugin development guide with templates |
| `docs/skills/` | Skill documentation and inter-skill data flow |

---

## Credential Rotation Schedule

| Credential | Rotation | How |
|-----------|----------|-----|
| OpenRouter API key | Every 3 months | openrouter.ai/keys |
| Gateway password | Every 3 months | `openssl rand -base64 32` |
| Telegram bot token | Every 6 months | @BotFather /revoke |
| Backup passphrase | Every 6 months | Update in credentials/ |
| Cloudflare tunnel | Every 12 months | `cloudflared tunnel token` |

---

## File Permissions

After installation, verify:

```bash
# Directories: 700 (owner only)
ls -la ~/.openclaw/

# Credential files: 600 (owner read/write only)
ls -la ~/.openclaw/credentials/

# Workspace: 700 dirs, 600 files
find ~/.openclaw/workspace -type d -exec ls -ld {} \;
```

---

## Not Included

This pack deliberately excludes:
- Real API keys, tokens, or passwords
- Runtime data (MEMORY.md content, topic files, session transcripts)
- Personal planning documents (PLAN.md, STATUS.md, TODO lists)
- Telethon session files

---

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -m 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

For security-related issues, please open a GitHub issue with the `security` label.

---

## License

MIT — see [LICENSE](LICENSE).
