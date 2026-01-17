#!/bin/bash
set -e

# Add this near the beginning of your init.sh script, after the set -e command
export PATH="/usr/local/bin:${PATH}"

# Also add this function to check and install bench if needed
ensure_bench_available() {
    if ! command -v bench &> /dev/null; then
        log "Bench not found. Installing globally..."
        pip install frappe-bench
    fi
}

# Call this function before any bench commands
ensure_bench_available

# Color codes for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Colo

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

BENCH_DIR="/home/frappe/frappe-bench"

# Environment variables with defaults
SITE_NAME=${SITE_NAME:-site.localhost}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-123}
FRAPPE_REPO=${FRAPPE_REPO:-https://github.com/frappe/frappe}
FRAPPE_BRANCH=${FRAPPE_BRANCH:-v15.77.0}
ERPNEXT_REPO=${ERPNEXT_REPO:-https://github.com/frappe/erpnext}
ERPNEXT_BRANCH=${ERPNEXT_BRANCH:-v15.75.1}
HRMS_REPO=${HRMS_REPO:-https://github.com/frappe/hrms}
HRMS_BRANCH=${HRMS_BRANCH:-version-15}
CRM_REPO=${CRM_REPO:-https://github.com/frappe/crm}
CRM_BRANCH=${CRM_BRANCH:-v1.52.2}
PAYMENT_REPO=${PAYMENT_REPO:-https://github.com/frappe/payments}
PAYMENT_BRANCH=${PAYMENT_BRANCH:-version-15}
INDIA_COMPLIANCE_REPO=${INDIA_COMPLIANCE_REPO:-https://github.com/frappe/india_compliance}
INDIA_COMPLIANCE_BRANCH=${INDIA_COMPLIANCE_BRANCH:-v15.20.1}
FRAPPE_S3_ATTACHMENT_REPO=${FRAPPE_S3_ATTACHMENT_REPO:-https://github.com/zerodha/frappe-attachments-s3}
FRAPPE_S3_ATTACHMENT_BRANCH=${FRAPPE_S3_ATTACHMENT_BRANCH:-master}

# Function to restore the latest backup if available
restore_latest_backup() {
    local backup_dir="/home/frappe/backups"
    log "Checking for existing backups in $backup_dir to restore..."

    # Check if backup directory has any .sql.gz files
    if [ -d "$backup_dir" ] && [ -n "$(find "$backup_dir" -maxdepth 1 -name '*.sql.gz' -print -quit)" ]; then
        # Find the latest backup file
        local latest_backup
        latest_backup=$(ls -t "$backup_dir"/*.sql.gz | head -1)

        if [ -f "$latest_backup" ]; then
            log_warning "Latest backup found: $(basename "$latest_backup")."
            log "Attempting to restore site '$SITE_NAME' from this backup."

            # Restore the database
            log "Restoring database... This may take a few minutes."
            if bench --site "$SITE_NAME" --force restore "$latest_backup"; then
                log_success "Database restored successfully."
            else
                log_error "Failed to restore database. Continuing with fresh installation."
                return 1 # Indicate failure
            fi

            # Run migration
            log "Running database migration after restore..."
            bench --site "$SITE_NAME" migrate
            log_success "Migration complete."

            # Also restore the associated files backup
            local backup_basename=$(basename "$latest_backup" .sql.gz)
            local files_backup=$(find "$backup_dir" -name "${backup_basename}*-files.tar.gz" | head -1)

            if [ -f "$files_backup" ]; then
                log_warning "Found corresponding file backup: $(basename "$files_backup")"
                log "Restoring site files..."
                if tar -xzf "$files_backup" -C "$BENCH_DIR/sites/$SITE_NAME"; then
                    log_success "Site files restored successfully."
                else
                    log_error "Failed to restore site files."
                    # Continue anyway, as the database is the most critical part
                fi
            fi
            return 0 # Indicate restore was successful
        fi
    fi

    log "No suitable backup found. Proceeding with a fresh installation."
    return 1 # Indicate no restore was performed
}

# Check for a complete installation. If found, start the bench and exit.
if [ -d "/home/frappe/frappe-bench/apps/frappe" ]; then
    log "Complete bench installation found. Starting services..."
    cd frappe-bench
    bench use $SITE_NAME
    bench start
    exit 0
fi

export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin/:${PATH}"

# --- Robust Bench Initialization ---
# To avoid issues with initializing in a pre-existing volume-mounted directory,
# we initialize in a temporary directory and then move the contents.

TEMP_BENCH_DIR="/home/frappe/temp-bench"

log "Initializing new bench in a temporary directory ($TEMP_BENCH_DIR)..."

# Clean up any previous temporary directory
rm -rf "$TEMP_BENCH_DIR"

bench init --frappe-path "$FRAPPE_REPO" --frappe-branch "$FRAPPE_BRANCH" --skip-redis-config-generation "$TEMP_BENCH_DIR"

log "Moving initialized bench to the persistent volume ($BENCH_DIR)..."
# Use shopt to include dotfiles in the move, then move and clean up.
shopt -s dotglob
mv "$TEMP_BENCH_DIR"/* "$BENCH_DIR"/
rm -rf "$TEMP_BENCH_DIR"

cd "$BENCH_DIR"

log "Ensuring all Python dependencies are installed..."
# This command reinstalls all apps in editable mode and their requirements.
# It's a robust way to fix potential ModuleNotFoundError issues.
bench setup requirements
# Configure services
log "Configuring services..."
bench set-mariadb-host mariadb
bench set-redis-cache-host redis://redis:6379
bench set-redis-queue-host redis://redis:6379
bench set-redis-socketio-host redis://redis:6379

# Remove redis and watch from Procfile
sed -i '/redis/d' ./Procfile
# # sed -i '/watch/d' ./Procfile

bench get-app --branch $ERPNEXT_BRANCH $ERPNEXT_REPO
bench get-app --branch $HRMS_BRANCH $HRMS_REPO
bench get-app --branch $CRM_BRANCH $CRM_REPO
bench get-app --branch $PAYMENT_BRANCH $PAYMENT_REPO
bench get-app --branch $INDIA_COMPLIANCE_BRANCH $INDIA_COMPLIANCE_REPO
bench get-app --branch $FRAPPE_S3_ATTACHMENT_BRANCH $FRAPPE_S3_ATTACHMENT_REPO

bench new-site $SITE_NAME \
    --force \
    --mariadb-root-password $MYSQL_ROOT_PASSWORD \
    --admin-password $ADMIN_PASSWORD \
    --no-mariadb-socket

# Attempt to restore from backup, otherwise perform a fresh install
if restore_latest_backup; then
    log_success "Site restored from backup successfully."
else
    log "Performing a fresh installation of apps..."
    bench --site $SITE_NAME install-app erpnext
    bench --site $SITE_NAME install-app hrms
    bench --site $SITE_NAME install-app crm
    bench --site $SITE_NAME install-app payments
    bench --site $SITE_NAME install-app india_compliance
    bench --site $SITE_NAME install-app frappe_s3_attachment
    log_success "All apps installed successfully."
fi

bench --site $SITE_NAME set-config developer_mode 1
bench --site $SITE_NAME clear-cache
bench use $SITE_NAME

bench start