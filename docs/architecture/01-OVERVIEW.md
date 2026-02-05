# OpenClaw: System Overview

Personal AI assistant running on WSL2 with Telegram integration, Cloudflare tunnel, and OpenRouter LLM.

## Defense in Depth (9 Layers)

```
Layer 1: Cloudflare Tunnel     — Zero Trust, DDoS, WAF
Layer 2: UFW Firewall          — deny incoming, allow outgoing
Layer 3: Loopback Binding      — Gateway on 127.0.0.1:18789
Layer 4: Telegram Allowlist    — dmPolicy: allowlist
Layer 5: Input Validation      — Regex injection patterns (5 rules)
Layer 6: CIF + prompt-guard    — 22 patterns, 3-strike graduated response
Layer 7: Agent Identity        — SOUL.md CRITICAL rules
Layer 8: Docker Sandbox        — Execution isolation, no network, caps dropped
Layer 9: Systemd Hardening     — NoNewPrivileges, ProtectKernel*, MemoryMax
```

## Runtime Architecture

| Component | Location | Runtime |
|-----------|----------|---------|
| Gateway | `~/openclaw/` | Node.js via systemd |
| Workspace | `~/.openclaw/workspace/` | Agent context |
| QMD Search | `~/qmd-tool/` | Bun MCP server |
| Whisper | `~/whisper.cpp/` | CUDA (RTX 3070) |
| Tunnel | cloudflared | Go binary |

## File Structure

```
~/.openclaw/
├── openclaw.json             # Main config
├── credentials/              # API keys (chmod 600)
│   ├── .env                  # All secrets
│   └── backup-passphrase     # Backup key
├── workspace/                # Agent workspace
│   ├── SECURITY.md           # Cognitive Integrity Framework
│   ├── SOUL.md               # Agent identity + CRITICAL rules
│   ├── MEMORY.md             # Global memory
│   ├── topics/               # Topic memories
│   └── .openclaw/
│       ├── extensions/       # Custom plugins
│       └── skills/           # prompt-guard, skill-guard
├── scripts/                  # Automation
├── backups/                  # GPG encrypted (chmod 700)
└── logs/                     # Gateway logs

~/openclaw/                   # Source code (read-only, git pull)
~/qmd-tool/                   # QMD search
~/whisper.cpp/                # Voice transcription (CUDA)
```

## Requirements

| Component | Requirement |
|-----------|-------------|
| OS | Windows 10/11 + WSL2 (systemd) |
| RAM | 4 GB min (2 GB for gateway) |
| GPU | NVIDIA (optional, for whisper) |
| Node.js | 20+ |

## Links

- [OpenClaw Docs](https://docs.openclaw.ai)
- [OpenRouter](https://openrouter.ai)
- [OWASP LLM Top 10](https://owasp.org/www-project-top-10-for-large-language-model-applications/)
