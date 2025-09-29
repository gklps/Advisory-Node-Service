#!/bin/bash

# Auto-start script for Advisory Node Service after VM reboot
# This script should be added to crontab with @reboot

set -e

# Configuration
APP_DIR="$HOME/advisory-node-deploy"
LOG_FILE="$APP_DIR/logs/auto-start.log"

# Ensure log directory exists
mkdir -p "$APP_DIR/logs"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_message "=== Auto-start script initiated after reboot ==="

# Wait for system to stabilize (PostgreSQL to start)
log_message "Waiting for system to stabilize..."
sleep 30

# Check if PostgreSQL is running
while ! sudo systemctl is-active --quiet postgresql; do
    log_message "Waiting for PostgreSQL to start..."
    sleep 10
done

log_message "PostgreSQL is running"

# Check if supervisor is running
while ! sudo systemctl is-active --quiet supervisor; do
    log_message "Waiting for Supervisor to start..."
    sleep 10
done

log_message "Supervisor is running"

# Wait a bit more for services to initialize
sleep 15

# Start Advisory Node services
log_message "Starting Advisory Node services..."
sudo supervisorctl start advisory-testnet advisory-mainnet

# Wait for services to start
sleep 10

# Check service status
TESTNET_STATUS=$(sudo supervisorctl status advisory-testnet | awk '{print $2}')
MAINNET_STATUS=$(sudo supervisorctl status advisory-mainnet | awk '{print $2}')

log_message "Testnet status: $TESTNET_STATUS"
log_message "Mainnet status: $MAINNET_STATUS"

# Test health endpoints
sleep 15

if curl -s http://localhost:8080/api/quorum/health > /dev/null 2>&1; then
    log_message "✅ Testnet health check passed"
else
    log_message "❌ Testnet health check failed"
fi

if curl -s http://localhost:8081/api/quorum/health > /dev/null 2>&1; then
    log_message "✅ Mainnet health check passed"
else
    log_message "❌ Mainnet health check failed"
fi

log_message "=== Auto-start script completed ==="
