#!/usr/bin/env bash
# OpenClaw Config Pack — Interactive Installer
# Copies configuration, workspace, and scripts to ~/.openclaw/
set -euo pipefail

# ============================================================
# Script directory detection (works from any location)
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════╗"
echo "║   OpenClaw Config Pack — Installer       ║"
echo "║   9-Layer Security Configuration         ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "Source:      $SCRIPT_DIR"
echo "Destination: $OPENCLAW_HOME"
echo ""

# ============================================================
# Pre-flight checks
# ============================================================
if [ ! -f "$SCRIPT_DIR/config/openclaw.json.template" ]; then
    echo -e "${RED}ERROR: openclaw.json.template not found in $SCRIPT_DIR/config/${NC}"
    echo "Are you running this from the openclaw-config-pack directory?"
    exit 1
fi

# ============================================================
# Confirm
# ============================================================
read -rp "Install to $OPENCLAW_HOME? [Y/n] " CONFIRM
if [[ "${CONFIRM,,}" == "n" ]]; then
    echo "Aborted."
    exit 0
fi

# ============================================================
# Create directory structure
# ============================================================
echo ""
echo -e "${YELLOW}[1/7] Creating directory structure...${NC}"

mkdir -p "$OPENCLAW_HOME"/{config,credentials,logs,workspace,scripts/{digest,notify,maintenance,tools},cloudflared,backups}
mkdir -p "$OPENCLAW_HOME"/workspace/.openclaw/{skills,extensions}

echo -e "${GREEN}  ✓ Directories created${NC}"

# ============================================================
# Generate gateway credentials
# ============================================================
echo -e "${YELLOW}[2/7] Generating credentials...${NC}"

if command -v openssl >/dev/null 2>&1; then
    GW_PASSWORD=$(openssl rand -base64 32 | tr -d '=/+' | head -c 44)
    GW_TOKEN=$(openssl rand -hex 32)
else
    GW_PASSWORD=$(head -c 64 /dev/urandom | base64 | tr -d '=/+' | head -c 44)
    GW_TOKEN=$(head -c 32 /dev/urandom | xxd -p | head -c 64)
fi

echo -e "${GREEN}  ✓ Gateway password generated (${#GW_PASSWORD} chars)${NC}"
echo -e "${GREEN}  ✓ Gateway token generated${NC}"

# ============================================================
# Copy configuration
# ============================================================
echo -e "${YELLOW}[3/7] Copying configuration...${NC}"

# openclaw.json (from template)
if [ ! -f "$OPENCLAW_HOME/config/openclaw.json" ]; then
    cp "$SCRIPT_DIR/config/openclaw.json.template" "$OPENCLAW_HOME/config/openclaw.json"
    echo -e "${GREEN}  ✓ openclaw.json created (edit YOUR_* placeholders!)${NC}"
else
    echo -e "${YELLOW}  ⊘ openclaw.json already exists, skipping${NC}"
fi

# Symlink for non-Docker deployments (tmux/systemd expect ~/.openclaw/openclaw.json)
if [ ! -e "$OPENCLAW_HOME/openclaw.json" ]; then
    ln -s "$OPENCLAW_HOME/config/openclaw.json" "$OPENCLAW_HOME/openclaw.json"
    echo -e "${GREEN}  ✓ Symlink: openclaw.json → config/openclaw.json${NC}"
fi

# .env
if [ ! -f "$OPENCLAW_HOME/credentials/.env" ]; then
    sed "s|your-secure-password-minimum-32-characters|${GW_PASSWORD}|" \
        "$SCRIPT_DIR/config/.env.example" > "$OPENCLAW_HOME/credentials/.env"
    echo -e "${GREEN}  ✓ .env created with generated password${NC}"
else
    echo -e "${YELLOW}  ⊘ .env already exists, skipping${NC}"
fi

# security-alerts.env
if [ ! -f "$OPENCLAW_HOME/security-alerts.env" ]; then
    cp "$SCRIPT_DIR/config/security-alerts.env.example" "$OPENCLAW_HOME/security-alerts.env"
    echo -e "${GREEN}  ✓ security-alerts.env created${NC}"
fi

# cloudflared config
if [ ! -f "$OPENCLAW_HOME/cloudflared/config.yml" ]; then
    cp "$SCRIPT_DIR/deploy/cloudflared/config.yml" "$OPENCLAW_HOME/cloudflared/config.yml"
    echo -e "${GREEN}  ✓ cloudflared config copied${NC}"
fi

# docker-compose
if [ ! -f "$OPENCLAW_HOME/docker-compose.yml" ]; then
    cp "$SCRIPT_DIR/deploy/docker-compose.yml" "$OPENCLAW_HOME/docker-compose.yml"
    echo -e "${GREEN}  ✓ docker-compose.yml copied${NC}"
fi

# ============================================================
# Copy workspace (SOUL.md, SECURITY.md, skills)
# ============================================================
echo -e "${YELLOW}[4/7] Copying workspace files...${NC}"

# Core files
cp "$SCRIPT_DIR/workspace/SOUL.md" "$OPENCLAW_HOME/workspace/SOUL.md"
cp "$SCRIPT_DIR/workspace/SECURITY.md" "$OPENCLAW_HOME/workspace/SECURITY.md"
echo -e "${GREEN}  ✓ SOUL.md, SECURITY.md${NC}"

# Skills — interactive selection
echo ""
echo "  Available skills:"
echo "    1. prompt-guard    — Input injection defense"
echo "    2. skill-guard     — Third-party skill audit"
echo "    3. memory-manager  — Memory organization"
echo "    4. task-manager    — Task management (P1/P2/P3)"
echo "    5. voice-router    — Voice transcript routing"
echo "    6. weekly-review   — Weekly progress summary"
echo ""
read -rp "  Install all skills? [Y/n] " INSTALL_SKILLS

if [[ "${INSTALL_SKILLS,,}" != "n" ]]; then
    for skill in prompt-guard skill-guard memory-manager task-manager voice-router weekly-review; do
        mkdir -p "$OPENCLAW_HOME/workspace/.openclaw/skills/$skill"
        cp "$SCRIPT_DIR/workspace/skills/$skill/SKILL.md" \
           "$OPENCLAW_HOME/workspace/.openclaw/skills/$skill/SKILL.md"
    done
    echo -e "${GREEN}  ✓ All 6 skills installed${NC}"
else
    echo "  Select skills to install (space-separated numbers, e.g. '1 2 3'):"
    read -rp "  > " SKILL_CHOICES
    SKILL_MAP=("prompt-guard" "skill-guard" "memory-manager" "task-manager" "voice-router" "weekly-review")
    for num in $SKILL_CHOICES; do
        idx=$((num - 1))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#SKILL_MAP[@]}" ]; then
            skill="${SKILL_MAP[$idx]}"
            mkdir -p "$OPENCLAW_HOME/workspace/.openclaw/skills/$skill"
            cp "$SCRIPT_DIR/workspace/skills/$skill/SKILL.md" \
               "$OPENCLAW_HOME/workspace/.openclaw/skills/$skill/SKILL.md"
            echo -e "${GREEN}  ✓ $skill${NC}"
        fi
    done
fi

# Extensions — optional
echo ""
read -rp "  Install extensions (voice-transcriber, bookmarks, telegram-digest, task-manager)? [y/N] " INSTALL_EXT

if [[ "${INSTALL_EXT,,}" == "y" ]]; then
    for ext in voice-transcriber bookmarks telegram-digest task-manager; do
        mkdir -p "$OPENCLAW_HOME/workspace/.openclaw/extensions/$ext"
        cp "$SCRIPT_DIR/extensions/$ext/"* "$OPENCLAW_HOME/workspace/.openclaw/extensions/$ext/"
    done
    echo -e "${GREEN}  ✓ Extensions installed (4)${NC}"
    echo ""
    echo -e "  ${YELLOW}Note:${NC} voice-transcriber requires whisper.cpp."
    echo "  See docs/VOICE-TRANSCRIPTION.md for setup instructions."
fi

# ============================================================
# Copy scripts
# ============================================================
echo -e "${YELLOW}[5/7] Copying scripts...${NC}"

# Digest scripts + config
for f in telegram-digest.py telegram-digest-public.py \
         telegram-digest-cron.sh telegram-digest-public-cron.sh \
         channels.json public-channels.json \
         requirements.txt requirements-public.txt; do
    cp "$SCRIPT_DIR/scripts/digest/$f" "$OPENCLAW_HOME/scripts/digest/$f"
done

# Notification scripts
for f in daily-digest.sh task-ping.sh crypto-prices.sh; do
    cp "$SCRIPT_DIR/scripts/notify/$f" "$OPENCLAW_HOME/scripts/notify/$f"
done

# Maintenance scripts
for f in backup.sh clean-logs.sh daily-check.sh security-monitor.sh; do
    cp "$SCRIPT_DIR/scripts/maintenance/$f" "$OPENCLAW_HOME/scripts/maintenance/$f"
done

# Tool scripts
for f in transcribe.sh init-topics.sh; do
    cp "$SCRIPT_DIR/scripts/tools/$f" "$OPENCLAW_HOME/scripts/tools/$f"
done

echo -e "${GREEN}  ✓ Scripts copied (4 subdirectories: digest, notify, maintenance, tools)${NC}"

# Digest venv hint
echo ""
echo -e "  ${YELLOW}Note:${NC} Channel digest requires Python + dependencies."
echo "  To set up:"
echo "    cd $OPENCLAW_HOME/scripts/digest"
echo "    python3 -m venv venv"
echo "    source venv/bin/activate"
echo "    pip install -r requirements.txt          # Telethon variant"
echo "    pip install -r requirements-public.txt   # Public variant"
echo "  See docs/TELEGRAM-DIGEST.md and docs/TELEGRAM-DIGEST-PUBLIC.md for details."

# ============================================================
# Set permissions
# ============================================================
echo -e "${YELLOW}[6/7] Setting permissions...${NC}"

# Directories: 700
chmod 700 "$OPENCLAW_HOME"
find "$OPENCLAW_HOME" -type d -exec chmod 700 {} \;

# Credential files: 600
chmod 600 "$OPENCLAW_HOME/credentials/.env" 2>/dev/null || true
chmod 600 "$OPENCLAW_HOME/security-alerts.env" 2>/dev/null || true

# Config files: 600
chmod 600 "$OPENCLAW_HOME/config/openclaw.json" 2>/dev/null || true

# Workspace files: 600
find "$OPENCLAW_HOME/workspace" -type f -exec chmod 600 {} \;

# Scripts: 700
find "$OPENCLAW_HOME/scripts" -name "*.sh" -exec chmod 700 {} \;

echo -e "${GREEN}  ✓ Permissions set (dirs: 700, files: 600, scripts: 700)${NC}"

# ============================================================
# Systemd service (optional)
# ============================================================
echo -e "${YELLOW}[7/7] Systemd service...${NC}"
read -rp "  Install systemd service? [y/N] " INSTALL_SERVICE

if [[ "${INSTALL_SERVICE,,}" == "y" ]]; then
    SERVICE_FILE="$SCRIPT_DIR/deploy/systemd/openclaw.service"
    CURRENT_USER=$(whoami)

    # Replace placeholder with current user
    sed "s/YOUR_USER/$CURRENT_USER/g" "$SERVICE_FILE" | \
        sudo tee /etc/systemd/system/openclaw.service > /dev/null

    sudo systemctl daemon-reload
    echo -e "${GREEN}  ✓ Service installed (User=$CURRENT_USER)${NC}"
    echo "    Start with: sudo systemctl start openclaw"
    echo "    Enable on boot: sudo systemctl enable openclaw"
else
    echo -e "  ⊘ Skipped"
fi

# ============================================================
# Initialize workspace structure
# ============================================================
echo ""
read -rp "Initialize workspace topic structure? [Y/n] " INIT_TOPICS
if [[ "${INIT_TOPICS,,}" != "n" ]]; then
    bash "$OPENCLAW_HOME/scripts/tools/init-topics.sh"
fi

# ============================================================
# Verification
# ============================================================
echo ""
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}  Installation complete!${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo ""
echo "  Directory: $OPENCLAW_HOME"
echo ""

# Check key files exist
CHECKS=0
TOTAL=0
for f in config/openclaw.json credentials/.env workspace/SOUL.md workspace/SECURITY.md docker-compose.yml; do
    TOTAL=$((TOTAL + 1))
    if [ -f "$OPENCLAW_HOME/$f" ]; then
        echo -e "  ${GREEN}✓${NC} $f"
        CHECKS=$((CHECKS + 1))
    else
        echo -e "  ${RED}✗${NC} $f"
    fi
done

SKILL_COUNT=$(find "$OPENCLAW_HOME/workspace/.openclaw/skills" -name "SKILL.md" 2>/dev/null | wc -l)
echo -e "  ${GREEN}✓${NC} Skills installed: $SKILL_COUNT"

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Edit $OPENCLAW_HOME/config/openclaw.json"
echo "     Replace all YOUR_* placeholders with your values"
echo ""
echo "  2. Edit $OPENCLAW_HOME/credentials/.env"
echo "     Add your API keys and tokens"
echo ""
echo "  3. Start OpenClaw:"
echo "     docker compose -f $OPENCLAW_HOME/docker-compose.yml up -d"
echo ""
echo -e "  ${YELLOW}Gateway password:${NC} $GW_PASSWORD"
echo -e "  ${YELLOW}Gateway token:${NC}    $GW_TOKEN"
echo ""
echo -e "  ${RED}Save these credentials now! They won't be shown again.${NC}"
echo ""
