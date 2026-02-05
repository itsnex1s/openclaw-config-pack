# WSL2 Setup Guide

OpenClaw config pack is designed to run on WSL2 with systemd. This guide covers the complete setup from scratch.

---

## Prerequisites

- Windows 10 (build 19041+) or Windows 11
- Administrator access
- 4 GB+ free RAM for WSL2

---

## 1. Install WSL2

Open **PowerShell as Administrator**:

```powershell
wsl --install -d Ubuntu-24.04
```

Restart Windows when prompted. After reboot, Ubuntu will open and ask for a username and password.

Verify installation:

```bash
wsl --version
# WSL version: 2.x.x
# Kernel version: 5.15+
```

---

## 2. Enable systemd

Systemd is required for the openclaw service and cron jobs.

Inside WSL2:

```bash
sudo tee /etc/wsl.conf > /dev/null << 'EOF'
[boot]
systemd=true

[interop]
appendWindowsPath=false

[automount]
enabled=true
options="metadata,umask=22,fmask=11"
EOF
```

Restart WSL2 from PowerShell:

```powershell
wsl --shutdown
wsl
```

Verify systemd is running:

```bash
systemctl --no-pager status
# Should show "State: running"
```

---

## 3. Install dependencies

```bash
sudo apt update && sudo apt install -y \
  curl git jq gnupg openssl ufw \
  docker.io docker-compose-v2

# Add yourself to docker group (no sudo for docker)
sudo usermod -aG docker $USER
newgrp docker
```

Optional — for voice transcription:

```bash
sudo apt install -y ffmpeg build-essential cmake
```

Optional — for channel digest:

```bash
sudo apt install -y python3 python3-venv python3-pip
```

---

## 4. Clone and install

**Important:** Clone to the Linux filesystem, not `/mnt/c/` or `/mnt/d/`. The Windows filesystem (NTFS) has slow I/O and `chmod` does not work correctly on it.

```bash
cd ~
git clone https://github.com/YOUR_USER/openclaw-config-pack.git
cd openclaw-config-pack
chmod +x install.sh
./install.sh
```

The installer creates `~/.openclaw/` with all files and correct permissions (dirs: 700, credentials: 600, scripts: 700).

### If you edit config on Windows

You can keep a copy on Windows for editing, then sync to WSL2:

```bash
# One-time copy from Windows path
cp /mnt/d/path/to/openclaw-config-pack/config/openclaw.json.template \
   ~/.openclaw/config/openclaw.json

# Set permissions (NTFS mount doesn't preserve them)
chmod 600 ~/.openclaw/config/openclaw.json
chmod 600 ~/.openclaw/credentials/.env
```

---

## 5. Configure

### 5.1 Edit config

```bash
nano ~/.openclaw/config/openclaw.json
```

Replace all `YOUR_*` placeholders:
- `YOUR_TELEGRAM_ID` — your Telegram user ID (get from @userinfobot)
- `YOUR_GROUP_ID` — your group ID (starts with `-100`)
- Topic IDs — match your Telegram forum topics

### 5.2 Add credentials

```bash
nano ~/.openclaw/credentials/.env
```

Fill in API keys: `OPENCLAW_GATEWAY_PASSWORD`, `TELEGRAM_BOT_TOKEN`, `OPENROUTER_API_KEY`, etc.

### 5.3 Verify permissions

```bash
ls -la ~/.openclaw/credentials/
# -rw------- 1 user user ... .env

ls -la ~/.openclaw/config/
# -rw------- 1 user user ... openclaw.json
```

---

## 6. Firewall

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 127.0.0.1
sudo ufw enable
sudo ufw status
```

Verify no services are exposed:

```bash
ss -tlnp | grep -v 127.0.0.1
# Should be empty — nothing listening on 0.0.0.0
```

---

## 7. Start OpenClaw

### Option A: Docker (recommended)

```bash
cd ~/.openclaw
docker compose up -d
docker compose logs -f --tail=50
```

### Option B: Systemd service

```bash
# Install service (the installer offers this, or manually):
sudo cp ~/openclaw-config-pack/deploy/systemd/openclaw.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable openclaw
sudo systemctl start openclaw

# Check status
systemctl status openclaw
journalctl -u openclaw -f --no-pager
```

---

## 8. Set up cron jobs

Verify cron is running:

```bash
systemctl status cron
# If inactive:
sudo systemctl enable --now cron
```

Add scheduled jobs:

```bash
crontab -e
```

Paste:

```cron
# Daily digest (morning + evening)
0 8 * * * ~/.openclaw/scripts/daily-digest.sh >> ~/.openclaw/logs/daily-digest.log 2>&1
0 20 * * * ~/.openclaw/scripts/daily-digest.sh --evening >> ~/.openclaw/logs/daily-digest.log 2>&1

# Task ping
0 10 * * * ~/.openclaw/scripts/task-ping.sh >> ~/.openclaw/logs/task-ping.log 2>&1
0 18 * * * ~/.openclaw/scripts/task-ping.sh >> ~/.openclaw/logs/task-ping.log 2>&1

# Security monitor (every 15 min)
*/15 * * * * ~/.openclaw/scripts/security-monitor.sh >> ~/.openclaw/logs/security-monitor.log 2>&1

# Log cleanup + leak detection (daily 03:00)
0 3 * * * ~/.openclaw/scripts/clean-logs.sh >> ~/.openclaw/logs/clean-logs.log 2>&1

# Encrypted backup (Sunday 03:30)
30 3 * * 0 BACKUP_PASSPHRASE="CHANGE_ME" ~/.openclaw/scripts/backup.sh >> ~/.openclaw/logs/backup.log 2>&1

# Crypto & NFT prices (daily 10:00)
0 10 * * * ~/.openclaw/scripts/crypto-prices.sh >> ~/.openclaw/logs/crypto-prices.log 2>&1

# Channel digest (daily 08:30, optional)
# 30 8 * * * ~/.openclaw/scripts/telegram-digest-cron.sh >> ~/.openclaw/logs/telegram-digest.log 2>&1
```

**Note:** Cron jobs survive WSL2 restarts as long as systemd is enabled. If you run `wsl --shutdown` from Windows, cron resumes automatically on next WSL2 start.

---

## 9. WSL2 auto-start (optional)

By default, WSL2 shuts down after all terminals close. To keep it running (so cron and systemd services persist):

### Option A: Windows Task Scheduler

Create a task that runs at login:

```
Program: wsl.exe
Arguments: -d Ubuntu-24.04 -- bash -c "sleep infinity"
```

Set it to run whether user is logged on or not.

### Option B: wsl.conf keepalive

In `/etc/wsl.conf`:

```ini
[boot]
command="nohup sleep infinity &"
```

---

## 10. GPU setup for voice transcription (optional)

If you have an NVIDIA GPU and want fast whisper.cpp transcription:

### 10.1 Install NVIDIA drivers on Windows

Download and install the latest Game Ready or Studio driver from [nvidia.com/drivers](https://www.nvidia.com/drivers). WSL2 uses the Windows driver — do NOT install drivers inside WSL2.

### 10.2 Install CUDA toolkit in WSL2

```bash
# NVIDIA CUDA toolkit for WSL2
wget https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt update
sudo apt install -y cuda-toolkit

# Verify
nvidia-smi
```

### 10.3 Build whisper.cpp with CUDA

```bash
git clone https://github.com/ggerganov/whisper.cpp.git ~/whisper.cpp
cd ~/whisper.cpp
cmake -B build -DGGML_CUDA=1
cmake --build build -j$(nproc) --config Release

# Download model
sh ./models/download-ggml-model.sh large-v3-turbo

# Test
./build/bin/whisper-cli -m models/ggml-large-v3-turbo.bin -f samples/jfk.wav
```

---

## Troubleshooting

### systemd not working

```bash
# Check WSL version (must be 2)
wsl.exe --version

# Verify wsl.conf has systemd=true
cat /etc/wsl.conf

# Restart WSL2 from PowerShell
wsl --shutdown
```

### chmod has no effect

You are likely on a Windows-mounted filesystem (`/mnt/c/`, `/mnt/d/`). Move files to the Linux filesystem:

```bash
# Check current filesystem
df -h ~/.openclaw
# Should show /dev/sdX, NOT drvfs or 9p

# If on Windows mount, move to Linux FS
mv ~/.openclaw ~/openclaw-backup
mkdir ~/.openclaw
cp -a ~/openclaw-backup/* ~/.openclaw/
chmod 700 ~/.openclaw
find ~/.openclaw -type f -exec chmod 600 {} \;
find ~/.openclaw/scripts -name "*.sh" -exec chmod 700 {} \;
```

### Port 18789 not accessible from Windows

The gateway binds to `127.0.0.1` (loopback) by design. To access from Windows:

```bash
# WSL2 localhost forwarding usually works automatically
# Test from Windows PowerShell:
curl http://localhost:18789/health
```

If it does not work, check Windows `.wslconfig`:

```ini
# %USERPROFILE%\.wslconfig
[wsl2]
localhostForwarding=true
```

### Cron jobs not running after restart

```bash
# Verify cron is active
systemctl is-active cron

# If not, enable it
sudo systemctl enable --now cron

# Check cron logs
grep CRON /var/log/syslog | tail -20
```

### Docker not starting

```bash
# Check docker service
systemctl status docker

# Start if needed
sudo systemctl enable --now docker

# Verify
docker ps
```

### WSL2 runs out of memory

Create or edit `%USERPROFILE%\.wslconfig` on Windows:

```ini
[wsl2]
memory=4GB
swap=2GB
localhostForwarding=true
```

Then restart WSL2:

```powershell
wsl --shutdown
```

---

## Quick reference

| Action | Command |
|--------|---------|
| Start OpenClaw | `cd ~/.openclaw && docker compose up -d` |
| Stop OpenClaw | `cd ~/.openclaw && docker compose down` |
| View logs | `docker compose -f ~/.openclaw/docker-compose.yml logs -f` |
| Check status | `systemctl status openclaw` |
| Restart WSL2 | PowerShell: `wsl --shutdown` |
| Check open ports | `ss -tlnp` |
| Firewall status | `sudo ufw status` |
| Run digest preview | `~/.openclaw/scripts/daily-digest.sh --preview` |
| Backup now | `BACKUP_PASSPHRASE="..." ~/.openclaw/scripts/backup.sh` |
