#!/bin/bash
set -e

# Color codes for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Colo

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} BACKUP: $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] BACKUP SUCCESS:${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] BACKUP ERROR:${NC} $1"
}

# Configuration
BACKUP_DIR="/home/frappe/backups"
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-123}
SITE_NAME=${SITE_NAME:-site.localhost}
BACKUP_RETENTION_DAYS=14    # Keep 2 weeks of backups
BACKUP_INTERVAL_SECONDS=${BACKUP_INTERVAL_SECONDS:-21600} # Default to 6 hour (21600s)

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Ensure proper permissions for backup directory
chmod 755 "$BACKUP_DIR" 2>/dev/null || true

# Function to create database backup
create_database_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/periodic_db_backup_$timestamp.sql"

    log "Creating periodic database backup..."

    # Check if backup directory is writable
    if [ ! -w "$BACKUP_DIR" ]; then
        log_error "Backup directory is not writable: $BACKUP_DIR"
        log "Attempting to fix permissions..."
        chmod 755 "$BACKUP_DIR" 2>/dev/null || {
            log_error "Cannot fix backup directory permissions"
            return 1
        }
    fi

    # Wait for database to be ready
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if mysql -h mariadb -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1" >/dev/null 2>&1; then
            break
        fi
        log "Waiting for database... attempt $attempt/$max_attempts"
        sleep 10
        ((attempt++))
    done

    if [ $attempt -gt $max_attempts ]; then
        log_error "Database not accessible for backup"
        return 1
    fi

    # Create database backup
    local error_log=$(mktemp)
    if mysqldump -h mariadb -u root -p"$MYSQL_ROOT_PASSWORD" \
        --single-transaction \
        --routines \
        --triggers \
        --all-databases >"$backup_file" 2>"$error_log"; then

        # Compress the backup
        gzip "$backup_file"
        log_success "Database backup created: ${backup_file}.gz"
        # Log warnings if any
        if [ -s "$error_log" ]; then
            log_warning "mysqldump produced warnings: $(cat "$error_log")"
        fi
        rm -f "$error_log"
        return 0
    else
        log_error "Failed to create database backup. Error: $(cat "$error_log")"
        rm -f "$backup_file" "$error_log"
        return 1
    fi
}

# Function to create sites backup
create_sites_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/periodic_sites_backup_$timestamp.tar.gz"

    log "Creating periodic sites backup..."
    
    # Backup from persisted bench location
    local tar_output
    if [ -d "/home/frappe/frappe-bench/sites" ] && [ "$(ls -A /home/frappe/frappe-bench/sites 2>/dev/null)" ]; then
        if ! tar_output=$(tar -czf "$backup_file" -C /home/frappe/frappe-bench/sites . 2>&1); then
            log_error "Failed to create sites backup. Error: $tar_output"
            rm -f "$backup_file"
            return 1
        else
            log_success "Sites backup created: $backup_file"
            return 0
        fi
    else
        log "No sites data found to backup"
        return 0
    fi
}

# Function to create Frappe bench backup using built-in command
create_frappe_backup() {
    local all_sites_backed_up=true

    log "Creating Frappe backup using bench command..."

    # Check if bench is available and sites exist
    if [ -d "/home/frappe/frappe-bench" ]; then
        cd /home/frappe/frappe-bench

        # Process each site
        for site in $(echo "$SITE_NAME" | tr ',' ' '); do
            site=$(echo "$site" | xargs) # trim whitespace

            if [ -d "sites/$site" ]; then
                log "Creating backup for site: $site"

                # Create site backup directly in the persistent backup directory
                if backup_output=$(bench --site "$site" backup --with-files --compress --backup-dir "$BACKUP_DIR" 2>&1); then
                    log_success "Frappe backup for site '$site' created directly in $BACKUP_DIR"
                else
                    log_error "Failed to create Frappe backup for site: $site."
                    log_error "Bench output: $backup_output"
                    all_sites_backed_up=false
                fi
            else
                log "Site directory not found: $site"
            fi
        done
    else
        log "Frappe bench not found, skipping Frappe backup"
        return 1 # Indicate failure as bench is not present
    fi

    if [ "$all_sites_backed_up" = true ]; then
        return 0
    else
        return 1
    fi
}

# Function to cleanup old backups
cleanup_old_backups() {
    log "Cleaning up old backups (older than $BACKUP_RETENTION_DAYS days)..."

    if [ -d "$BACKUP_DIR" ]; then
        # Remove periodic and frappe backups older than retention period
        find "$BACKUP_DIR" -name "periodic_*" -type f -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null || true
        find "$BACKUP_DIR" -name "frappe_*" -type f -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null || true

        log_success "Old backups cleaned up"
    fi
}

# Function to verify backup integrity
verify_backup_integrity() {
    log "Verifying backup integrity..."

    # Check if backup files exist and are not empty
    local backup_count=$(find "$BACKUP_DIR" -name "periodic_*" -type f -size +0 2>/dev/null | wc -l)

    if [ "$backup_count" -gt 0 ]; then
        log_success "Found $backup_count backup files"

        # Test latest database backup
        local latest_db_backup=$(ls -t "$BACKUP_DIR"/periodic_db_backup_*.sql.gz 2>/dev/null | head -1)
        if [ -n "$latest_db_backup" ]; then
            if zcat "$latest_db_backup" | head -10 | grep -q "MySQL dump" 2>/dev/null; then
                log_success "Latest database backup integrity verified"
            else
                log_error "Latest database backup may be corrupted"
            fi
        fi

        # Test latest sites backup
        local latest_sites_backup=$(ls -t "$BACKUP_DIR"/periodic_sites_backup_*.tar.gz 2>/dev/null | head -1)
        if [ -n "$latest_sites_backup" ]; then
            if tar -tzf "$latest_sites_backup" >/dev/null 2>&1; then
                log_success "Latest sites backup integrity verified"
            else
                log_error "Latest sites backup may be corrupted"
            fi
        fi
    else
        log_error "No backup files found"
    fi
}

# Main backup function
perform_backup() {
    log "Starting periodic backup process..."

    local backup_success=0

    # Create database backup
    if create_database_backup; then
        ((backup_success++))
    fi

    # Create sites backup
    if create_sites_backup; then
        ((backup_success++))
    fi

    # Create Frappe backup
    if create_frappe_backup; then
        ((backup_success++))
    fi

    # Cleanup old backups
    cleanup_old_backups

    # Verify backup integrity
    verify_backup_integrity

    if [ $backup_success -gt 0 ]; then
        log_success "Periodic backup completed successfully ($backup_success backups created)"
        return 0
    else
        log_error "Periodic backup failed - no backups were created"
        return 1
    fi
}

# Main execution logic
main() {
    # If called with "now", perform a single backup and exit.
    # This is used for on-demand backups like the shutdown hook.
    if [ "$1" == "now" ]; then
        log "Performing on-demand backup..."
        perform_backup
        log_success "On-demand backup finished."
        exit 0
    fi

    # --- Default behavior for the long-running backup service ---
    log "Backup service started. Will perform a backup every $BACKUP_INTERVAL_SECONDS seconds."

    # Create an initial backup on startup (after a delay to ensure services are ready)
    log "Waiting for services to be ready..."
    sleep 300 # Wait 5 minutes for services to be fully ready

    # Periodic backup loop
    while true; do
        log "Performing periodic backup..."
        perform_backup

        log "Next backup in $BACKUP_INTERVAL_SECONDS seconds..."
        sleep "$BACKUP_INTERVAL_SECONDS"
    done
}

# Pass all script arguments to the main function
main "$@"
