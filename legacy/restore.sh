#!/bin/bash
set -e

# Color codes for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} RESTORE: $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] RESTORE SUCCESS:${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] RESTORE ERROR:${NC} $1"
}

# Check for backup file argument
if [ -z "$1" ]; then
    log_error "No backup file specified."
    echo "Usage: ./restore.sh <backup-file-name>"
    echo "The backup file must be located in the ./persistent/backups directory."
    exit 1
fi

BACKUP_FILE_NAME=$1
BACKUP_DIR="/home/frappe/backups"
BACKUP_FILE_PATH="$BACKUP_DIR/$BACKUP_FILE_NAME"
SITE_NAME=${SITE_NAME:-site.localhost}

# Verify that the backup file exists
if [ ! -f "$BACKUP_FILE_PATH" ]; then
    log_error "Backup file not found: $BACKUP_FILE_PATH"
    exit 1
fi

log "Starting restore process for site: $SITE_NAME"
log "Using backup file: $BACKUP_FILE_PATH"

# Navigate to the bench directory
cd /home/frappe/frappe-bench

# Restore the database
log "Restoring database... This may take a few minutes."
if bench --site "$SITE_NAME" --force restore "$BACKUP_FILE_PATH"; then
    log_success "Database restored successfully."
else
    log_error "Failed to restore database."
    exit 1
fi

# Run migration to apply schema changes
log "Running database migration..."
bench --site "$SITE_NAME" migrate

log_success "Restore and migration complete. Your site is ready."

# Also restore the files if a corresponding backup exists
if [[ "$BACKUP_FILE_NAME" == *".sql.gz"* ]]; then
    backup_basename=$(basename "$BACKUP_FILE_NAME" .sql.gz)
    files_backup=$(find "$BACKUP_DIR" -name "${backup_basename}*-files.tar.gz" | head -1)

    if [ -f "$files_backup" ]; then
        log "Found corresponding file backup: $(basename "$files_backup")"
        log "Restoring site files..."
        if tar -xzf "$files_backup" -C "/home/frappe/frappe-bench/sites/$SITE_NAME"; then
            log_success "Site files restored successfully."
        else
            log_error "Failed to restore site files."
        fi
    fi
fi
