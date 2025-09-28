#!/bin/bash
set -e

# Function to log with timestamp
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Configure DNS for proper network connectivity
log "Configuring DNS and network settings..."
if [ -f /app/docker/configure-dns.sh ]; then
    chmod +x /app/docker/configure-dns.sh
    /app/docker/configure-dns.sh
    if [ $? -eq 0 ]; then
        log "DNS configuration completed successfully"
    else
        log "DNS configuration completed with warnings"
    fi
else
    log "Warning: DNS configuration script not found"
fi

if [ "$1" = "updater" ]; then
    log "Starting updater service..."
    
    # Initial setup
    log "Creating necessary directories..."
    mkdir -p /app/logs
    chmod -R 755 /app/logs
    
    # Start cron service
    log "Starting cron service..."
    service cron start || true
    
    # Monitor logs with proper timestamp and labeling
    log "Entering monitoring mode for updates..."
    # Monitor both cron and check-updates logs
    tail -f /app/logs/cron.log | while read line; do
        log "[cron] $line"
    done
else
    # For UI and API services, execute the command directly
    exec "$@"
fi