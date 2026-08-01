#!/usr/bin/env bash
# sonarr_backup_to_telegram.sh
#
# Meant to run INSIDE the Sonarr container, placed at config/Backups/.
# Triggers a Sonarr backup via the API, waits for it to finish,
# sends the resulting archive to Telegram, and prunes old manual
# backups, keeping only the last N.

set -euo pipefail

# ─── Paths (derived from this script's own location) ───────────
# This script lives at <config>/Backups/sonarr_backup_to_telegram.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../config/Backups
CONFIG_DIR="$(dirname "$SCRIPT_DIR")"                        # .../config

BACKUP_DIR="$SCRIPT_DIR/manual"                              # .../config/Backups/manual
KEEP_LAST=5                                                   # how many recent manual backups to keep

# Secrets file lives under the config volume too, so it survives
# container recreation (unlike /etc, which is part of the writable
# layer and gets wiped when the container is recreated, not just restarted).
ENV_FILE="$SCRIPT_DIR/.secrets/backup-telegram.env"
# ────────────────────────────────────────────────────────────────

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Secrets file not found: ${ENV_FILE}" >&2
  exit 1
fi

# Make sure the file isn't world/group readable
PERMS=$(stat -c '%a' "$ENV_FILE")
if [[ "$PERMS" != "600" ]]; then
  echo "Warning: ${ENV_FILE} should have 600 permissions (currently ${PERMS}). Fix with: chmod 600 ${ENV_FILE}" >&2
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

: "${SONARR_URL:?SONARR_URL is not set in ${ENV_FILE}}"
: "${SONARR_API_KEY:?SONARR_API_KEY is not set in ${ENV_FILE}}"
: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN is not set in ${ENV_FILE}}"
: "${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID is not set in ${ENV_FILE}}"

log() { echo "[$(date '+%F %T')] $*"; }

# 1. Trigger the backup via the API
log "Triggering Sonarr backup..."
CMD_JSON=$(curl -sf -X POST "${SONARR_URL}/api/v3/command" \
  -H "X-Api-Key: ${SONARR_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"name":"Backup"}')

CMD_ID=$(echo "$CMD_JSON" | jq -r '.id')
if [[ -z "$CMD_ID" || "$CMD_ID" == "null" ]]; then
  log "Failed to start the backup command. API response: $CMD_JSON"
  exit 1
fi

# 2. Wait for completion (~60 second timeout)
log "Waiting for command id=${CMD_ID} to complete..."
for i in $(seq 1 20); do
  STATUS=$(curl -sf "${SONARR_URL}/api/v3/command/${CMD_ID}" \
    -H "X-Api-Key: ${SONARR_API_KEY}" | jq -r '.status')
  if [[ "$STATUS" == "completed" ]]; then
    log "Backup completed."
    break
  fi
  if [[ "$STATUS" == "failed" ]]; then
    log "Backup command failed."
    exit 1
  fi
  sleep 3
done

if [[ "$STATUS" != "completed" ]]; then
  log "Timed out waiting for the backup to complete."
  exit 1
fi

# 3. Find the newest file in the manual backups folder
LATEST=$(find "$BACKUP_DIR" -maxdepth 1 -name "*.zip" -printf '%T@ %p\n' \
  | sort -n | tail -1 | cut -d' ' -f2-)

if [[ -z "$LATEST" ]]; then
  log "No backup file found in ${BACKUP_DIR}"
  exit 1
fi

log "Found backup: ${LATEST}"

# 4. Send it to Telegram
log "Sending to Telegram..."
RESP=$(curl -sf -F chat_id="${TELEGRAM_CHAT_ID}" \
  -F document=@"${LATEST}" \
  -F caption="Sonarr backup $(date '+%d.%m.%Y %H:%M')" \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument")

if echo "$RESP" | jq -e '.ok == true' >/dev/null; then
  log "Sent successfully."
else
  log "Telegram send failed: $RESP"
  exit 1
fi

# 5. Prune old manual backups, keeping KEEP_LAST files
log "Pruning old backups (keeping last ${KEEP_LAST})..."
find "$BACKUP_DIR" -maxdepth 1 -name "*.zip" -printf '%T@ %p\n' \
  | sort -n | head -n -"${KEEP_LAST}" | cut -d' ' -f2- \
  | xargs -r rm -v

log "Done."