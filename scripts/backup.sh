#!/usr/bin/env bash
# OpenClaw encrypted backup script
# GPG symmetric encryption, 30-day rotation
# No external dependencies beyond gpg and tar (standard on Ubuntu)
#
# Usage:
#   ./backup.sh                  — interactive (prompts for passphrase)
#   BACKUP_PASSPHRASE=xxx ./backup.sh  — non-interactive (for cron)
#
# Cron example (Sunday 03:00):
#   0 3 * * 0 BACKUP_PASSPHRASE="your-passphrase" ~/.openclaw/scripts/backup.sh >> ~/.openclaw/logs/backup.log 2>&1

set -euo pipefail

# --- Configuration ---
OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/.openclaw/backups}"
PASSPHRASE_FILE="${OPENCLAW_DIR}/credentials/backup-passphrase"
RETENTION_DAYS=30

# --- Load passphrase from file if not set via env ---
if [ -z "${BACKUP_PASSPHRASE:-}" ] && [ -f "${PASSPHRASE_FILE}" ]; then
    BACKUP_PASSPHRASE="$(cat "${PASSPHRASE_FILE}")"
fi
DATE_TAG="$(date +%Y%m%d-%H%M%S)"
BACKUP_NAME="openclaw-backup-${DATE_TAG}"
ARCHIVE_PATH="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
ENCRYPTED_PATH="${ARCHIVE_PATH}.gpg"

# --- Preflight checks ---
if ! command -v gpg >/dev/null 2>&1; then
    echo "ERROR: gpg is not installed. Install with: sudo apt install gnupg" >&2
    exit 1
fi

if ! command -v tar >/dev/null 2>&1; then
    echo "ERROR: tar is not installed." >&2
    exit 1
fi

if [ ! -d "${OPENCLAW_DIR}" ]; then
    echo "ERROR: OpenClaw directory not found: ${OPENCLAW_DIR}" >&2
    exit 1
fi

# --- Create backup directory ---
mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

# --- Collect files to back up ---
BACKUP_ITEMS=()

# Config files
[ -d "${OPENCLAW_DIR}/config" ] && BACKUP_ITEMS+=("${OPENCLAW_DIR}/config")

# Workspace (SOUL.md, SECURITY.md, skills, MEMORY.md, shared)
[ -d "${OPENCLAW_DIR}/workspace" ] && BACKUP_ITEMS+=("${OPENCLAW_DIR}/workspace")

# Cloudflare tunnel config (not credentials - those rotate)
[ -f "${OPENCLAW_DIR}/cloudflared/config.yml" ] && BACKUP_ITEMS+=("${OPENCLAW_DIR}/cloudflared/config.yml")

# Docker compose
[ -f "${OPENCLAW_DIR}/docker-compose.yml" ] && BACKUP_ITEMS+=("${OPENCLAW_DIR}/docker-compose.yml")

# Credentials (encrypted separately for safety)
[ -d "${OPENCLAW_DIR}/credentials" ] && BACKUP_ITEMS+=("${OPENCLAW_DIR}/credentials")

if [ ${#BACKUP_ITEMS[@]} -eq 0 ]; then
    echo "ERROR: No files found to back up." >&2
    exit 1
fi

echo "[$(date)] Starting backup: ${BACKUP_NAME}"
echo "  Items: ${#BACKUP_ITEMS[@]}"

# --- Create tar archive ---
tar -czf "${ARCHIVE_PATH}" "${BACKUP_ITEMS[@]}" 2>/dev/null

# --- Encrypt with GPG (symmetric) ---
if [ -n "${BACKUP_PASSPHRASE:-}" ]; then
    # Non-interactive mode (cron)
    echo "${BACKUP_PASSPHRASE}" | gpg --batch --yes --passphrase-fd 0 \
        --symmetric --cipher-algo AES256 \
        --output "${ENCRYPTED_PATH}" \
        "${ARCHIVE_PATH}"
else
    # Interactive mode
    gpg --symmetric --cipher-algo AES256 \
        --output "${ENCRYPTED_PATH}" \
        "${ARCHIVE_PATH}"
fi

# --- Remove unencrypted archive ---
rm -f "${ARCHIVE_PATH}"

# --- Set permissions ---
chmod 600 "${ENCRYPTED_PATH}"

BACKUP_SIZE=$(du -h "${ENCRYPTED_PATH}" | cut -f1)
echo "  Encrypted backup: ${ENCRYPTED_PATH} (${BACKUP_SIZE})"

# --- Rotate old backups ---
DELETED_COUNT=0
if [ -d "${BACKUP_DIR}" ]; then
    while IFS= read -r old_backup; do
        rm -f "${old_backup}"
        DELETED_COUNT=$((DELETED_COUNT + 1))
    done < <(find "${BACKUP_DIR}" -name "openclaw-backup-*.tar.gz.gpg" -mtime "+${RETENTION_DAYS}" -type f 2>/dev/null)
fi

echo "  Rotated: ${DELETED_COUNT} old backup(s) removed (>${RETENTION_DAYS} days)"
echo "[$(date)] Backup complete."
