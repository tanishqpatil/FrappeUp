#!/bin/bash
set -e

# Color codes for logging
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} SHUTDOWN: $1"
}

log "Performing pre-shutdown backup..."

# Check the status of the frappe container
container_status=$(docker-compose ps -q frappe | xargs -r docker inspect -f '{{.State.Status}}' 2>/dev/null || echo "not_found")

if [ "$container_status" == "running" ]; then
    # Execute a one-off backup command inside the container
    docker-compose exec frappe bash /workspace/backup.sh now
    log "${GREEN}Pre-shutdown backup complete.${NC}"
else
    log "Frappe container not running. Skipping pre-shutdown backup."
fi

log "Shutting down and removing containers..."
docker-compose down --remove-orphans

log "${GREEN}Shutdown process finished.${NC}"