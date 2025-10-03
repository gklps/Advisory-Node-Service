#!/bin/bash

# Quick service diagnostic and fix script

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "========================================="
echo "Advisory Node Service Diagnostic & Fix"
echo "========================================="
echo ""

# Check current location
print_status "Current directory: $(pwd)"
print_status "User: $(whoami)"
print_status "Home: $HOME"
echo ""

# Check if we have the deployment directory
DEPLOY_DIR="$HOME/advisory-node-deploy"
if [ ! -d "$DEPLOY_DIR" ]; then
    print_error "Deployment directory not found: $DEPLOY_DIR"
    print_error "Please run the setup script first"
    exit 1
fi

print_status "Found deployment directory: $DEPLOY_DIR"
echo ""

# Check supervisor status
print_status "Checking Supervisor status..."
if systemctl is-active --quiet supervisor; then
    print_status "✅ Supervisor is running"
else
    print_warning "❌ Supervisor is not running - starting it..."
    sudo systemctl start supervisor
    sudo systemctl enable supervisor
fi

# Check PostgreSQL status
print_status "Checking PostgreSQL status..."
if systemctl is-active --quiet postgresql; then
    print_status "✅ PostgreSQL is running"
else
    print_warning "❌ PostgreSQL is not running - starting it..."
    sudo systemctl start postgresql
    sudo systemctl enable postgresql
fi

echo ""

# Check if supervisor configs exist
print_status "Checking Supervisor configurations..."
if [ -f "/etc/supervisor/conf.d/advisory-testnet.conf" ]; then
    print_status "✅ Testnet supervisor config exists"
else
    print_error "❌ Testnet supervisor config missing"
fi

if [ -f "/etc/supervisor/conf.d/advisory-mainnet.conf" ]; then
    print_status "✅ Mainnet supervisor config exists"
else
    print_error "❌ Mainnet supervisor config missing"
fi

echo ""

# Check supervisor services
print_status "Checking Supervisor services..."
sudo supervisorctl reread
sudo supervisorctl update

echo ""
print_status "Current supervisor status:"
sudo supervisorctl status

echo ""

# Check if binary exists
print_status "Checking application binary..."
if [ -f "$DEPLOY_DIR/advisory-node" ]; then
    print_status "✅ Binary exists: $DEPLOY_DIR/advisory-node"
    ls -lh "$DEPLOY_DIR/advisory-node"
else
    print_error "❌ Binary missing: $DEPLOY_DIR/advisory-node"
    
    # Try to build it
    print_status "Attempting to build binary..."
    cd "$DEPLOY_DIR"
    
    if [ -f "main.go" ]; then
        go build -o advisory-node main.go
        print_status "✅ Built from main.go"
    elif [ -f "main_db.go" ]; then
        go build -o advisory-node main_db.go
        print_status "✅ Built from main_db.go"
    else
        print_error "❌ No main Go file found to build"
        ls -la
        exit 1
    fi
fi

echo ""

# Check environment files
print_status "Checking environment files..."
if [ -f "$DEPLOY_DIR/testnet.env" ]; then
    print_status "✅ Testnet environment file exists"
else
    print_error "❌ Testnet environment file missing"
fi

if [ -f "$DEPLOY_DIR/mainnet.env" ]; then
    print_status "✅ Mainnet environment file exists"
else
    print_error "❌ Mainnet environment file missing"
fi

echo ""

# Check startup scripts
print_status "Checking startup scripts..."
if [ -f "$DEPLOY_DIR/start-testnet.sh" ]; then
    print_status "✅ Testnet startup script exists"
    chmod +x "$DEPLOY_DIR/start-testnet.sh"
else
    print_error "❌ Testnet startup script missing"
fi

if [ -f "$DEPLOY_DIR/start-mainnet.sh" ]; then
    print_status "✅ Mainnet startup script exists"
    chmod +x "$DEPLOY_DIR/start-mainnet.sh"
else
    print_error "❌ Mainnet startup script missing"
fi

echo ""

# Start services
print_status "Starting Advisory Node services..."
sudo supervisorctl start advisory-testnet advisory-mainnet

echo ""
print_status "Waiting for services to start..."
sleep 10

# Check service status
print_status "Service status after restart:"
sudo supervisorctl status advisory-testnet advisory-mainnet

echo ""

# Test connectivity
print_status "Testing service connectivity..."

# Test testnet
if curl -s --connect-timeout 5 http://localhost:8080/api/quorum/health >/dev/null 2>&1; then
    print_status "✅ Testnet (port 8080) is responding"
    curl -s http://localhost:8080/api/quorum/health | head -3
else
    print_warning "❌ Testnet (port 8080) is not responding"
    print_status "Checking testnet logs:"
    sudo supervisorctl tail advisory-testnet | tail -10
fi

echo ""

# Test mainnet
if curl -s --connect-timeout 5 http://localhost:8081/api/quorum/health >/dev/null 2>&1; then
    print_status "✅ Mainnet (port 8081) is responding"
    curl -s http://localhost:8081/api/quorum/health | head -3
else
    print_warning "❌ Mainnet (port 8081) is not responding"
    print_status "Checking mainnet logs:"
    sudo supervisorctl tail advisory-mainnet | tail -10
fi

echo ""

# Show recent logs
print_status "Recent error logs (if any):"
if [ -f "$DEPLOY_DIR/logs/advisory-testnet.err.log" ]; then
    echo "Testnet errors:"
    tail -5 "$DEPLOY_DIR/logs/advisory-testnet.err.log" 2>/dev/null || echo "No recent errors"
fi

if [ -f "$DEPLOY_DIR/logs/advisory-mainnet.err.log" ]; then
    echo "Mainnet errors:"
    tail -5 "$DEPLOY_DIR/logs/advisory-mainnet.err.log" 2>/dev/null || echo "No recent errors"
fi

echo ""

# Check ports
print_status "Checking port usage:"
print_status "Port 8080 usage:"
lsof -i:8080 || echo "Port 8080 is free"

print_status "Port 8081 usage:"
lsof -i:8081 || echo "Port 8081 is free"

echo ""
echo "========================================="
echo "Diagnostic Complete"
echo "========================================="
echo ""

print_status "If services are still not working, check the logs:"
echo "  sudo supervisorctl tail -f advisory-testnet"
echo "  sudo supervisorctl tail -f advisory-mainnet"
echo ""

print_status "Manual restart commands:"
echo "  sudo supervisorctl restart advisory-testnet advisory-mainnet"
echo "  sudo systemctl restart supervisor"
echo ""

print_status "Test commands:"
echo "  curl http://localhost:8080/api/quorum/health"
echo "  curl http://localhost:8081/api/quorum/health"
