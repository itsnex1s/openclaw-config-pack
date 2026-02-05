# Operations & Maintenance

## Update Process

```
1. Stop gateway         sudo systemctl stop openclaw
2. Backup               ~/.openclaw/scripts/maintenance/backup.sh
3. Fetch updates        cd ~/openclaw && git fetch --tags
4. Compare versions     CURRENT=$(git describe --tags)
                        LATEST=$(git tag --sort=-v:refname | head -1)
5. Checkout             git checkout $LATEST
6. Install deps         pnpm install --frozen-lockfile
7. Build                pnpm build
8. Validate             node --import tsx dist/entry.js doctor
9. Start gateway        sudo systemctl start openclaw
10. Verify              sudo systemctl status openclaw
                        tail -f ~/.openclaw/logs/gateway.log
```

## Backup & Restore

**Backup** (GPG AES-256, runs Sunday 03:00):

```bash
~/.openclaw/scripts/maintenance/backup.sh
# Creates: ~/.openclaw/backups/openclaw-backup-YYYYMMDD-HHMMSS.tar.gz.gpg
# Passphrase: ~/.openclaw/credentials/backup-passphrase
# Rotation: 30 days
```

What is backed up:
- `openclaw.json` — config
- `credentials/` — API keys
- `workspace/` — memory, topics, plugins, skills

What is NOT backed up (restored via `git clone`):
- `~/openclaw/` — source code

**Restore:**

```bash
# 1. Clone OpenClaw
git clone https://github.com/openclaw/openclaw.git ~/openclaw
cd ~/openclaw && pnpm install && pnpm build

# 2. Decrypt & restore
gpg --batch --passphrase-file ~/.openclaw/credentials/backup-passphrase \
    -d backup.tar.gz.gpg | tar xzf - -C ~/

# 3. Start
sudo systemctl start openclaw
```

## Cron Schedule (adjust to your timezone)

| Time | Script | Description |
|------|--------|-------------|
| `0 8 * * *` | daily-digest.sh | Morning task digest |
| `30 8 * * *` | telegram-digest-cron.sh | Channel digest via Gemini |
| `0 10,18 * * *` | task-ping.sh | Open tasks summary |
| `0 20 * * *` | daily-digest.sh --evening | Evening task digest |
| `*/15 * * * *` | security-monitor.sh | Real-time log monitoring |
| `0 3 * * *` | clean-logs.sh | Log rotation + leak detection |
| `0 3 * * 0` | backup.sh | Encrypted backup (Sunday) |

## Credential Rotation Schedule

| Credential | Interval | Last Rotated |
|------------|----------|-------------|
| OpenRouter API key | 90 days | — |
| Gateway password | 90 days | — |
| Telegram bot token | 180 days | — |
| Cloudflare token | 180 days | — |
| Backup passphrase | 180 days | — |

## Systemd Service

```
Unit:           openclaw.service
ExecStart:      node --max-old-space-size=1536 dist/index.js gateway --bind loopback --port 18789
MemoryMax:      2G
CPUQuota:       80%
Hardening:      NoNewPrivileges, ProtectKernel*, LockPersonality, PrivateTmp
```

Commands:
```bash
sudo systemctl start openclaw
sudo systemctl stop openclaw
sudo systemctl status openclaw
journalctl -u openclaw -f
```

## Update Checklist

```
[ ] Stop gateway (systemctl stop openclaw)
[ ] Run backup (backup.sh)
[ ] git fetch --tags && git checkout <new-version>
[ ] pnpm install && pnpm build
[ ] Check CHANGELOG.md for breaking changes
[ ] openclaw doctor
[ ] Start gateway (systemctl start openclaw)
[ ] Check logs for plugin errors
[ ] Test Telegram bot
```
