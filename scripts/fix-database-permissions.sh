#!/bin/bash

# Fix database permissions for Advisory Node Service

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
echo "Database Permissions Fix"
echo "========================================="
echo ""

# Read database credentials from environment file
DEPLOY_DIR="$HOME/advisory-node-deploy"
if [ -f "$DEPLOY_DIR/testnet.env" ]; then
    # Extract database user from env file
    DB_USER=$(grep "^DB_USER=" "$DEPLOY_DIR/testnet.env" | cut -d'=' -f2)
    DB_PASSWORD=$(grep "^DB_PASSWORD=" "$DEPLOY_DIR/testnet.env" | cut -d'=' -f2)
    TESTNET_DB=$(grep "^DB_NAME=" "$DEPLOY_DIR/testnet.env" | cut -d'=' -f2)
    
    print_status "Found database configuration:"
    print_status "  Database User: $DB_USER"
    print_status "  Testnet DB: $TESTNET_DB"
else
    print_error "Environment file not found: $DEPLOY_DIR/testnet.env"
    exit 1
fi

if [ -f "$DEPLOY_DIR/mainnet.env" ]; then
    MAINNET_DB=$(grep "^DB_NAME=" "$DEPLOY_DIR/mainnet.env" | cut -d'=' -f2)
    print_status "  Mainnet DB: $MAINNET_DB"
else
    print_error "Environment file not found: $DEPLOY_DIR/mainnet.env"
    exit 1
fi

echo ""

# Fix database permissions
print_status "Fixing database permissions..."

print_status "Setting up database permissions for $DB_USER..."

# Connect as postgres user and fix permissions
sudo -u postgres psql << EOF
-- Grant necessary permissions to advisory_user for testnet database
\c $TESTNET_DB
GRANT ALL PRIVILEGES ON DATABASE $TESTNET_DB TO $DB_USER;
GRANT ALL PRIVILEGES ON SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;

-- Grant necessary permissions to advisory_user for mainnet database
\c $MAINNET_DB
GRANT ALL PRIVILEGES ON DATABASE $MAINNET_DB TO $DB_USER;
GRANT ALL PRIVILEGES ON SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;

-- Make advisory_user the owner of the databases (optional but recommended)
ALTER DATABASE $TESTNET_DB OWNER TO $DB_USER;
ALTER DATABASE $MAINNET_DB OWNER TO $DB_USER;

\q
EOF

print_status "✅ Database permissions fixed successfully!"
echo ""

# Test database connectivity
print_status "Testing database connectivity..."

# Test testnet database
print_status "Testing testnet database connection..."
if PGPASSWORD="$DB_PASSWORD" psql -h localhost -U "$DB_USER" -d "$TESTNET_DB" -c "SELECT current_database(), current_user;" >/dev/null 2>&1; then
    print_status "✅ Testnet database connection successful"
else
    print_error "❌ Testnet database connection failed"
fi

# Test mainnet database
print_status "Testing mainnet database connection..."
if PGPASSWORD="$DB_PASSWORD" psql -h localhost -U "$DB_USER" -d "$MAINNET_DB" -c "SELECT current_database(), current_user;" >/dev/null 2>&1; then
    print_status "✅ Mainnet database connection successful"
else
    print_error "❌ Mainnet database connection failed"
fi

echo ""

# Restart services
print_status "Restarting Advisory Node services..."

# Stop services first
sudo supervisorctl stop advisory-testnet advisory-mainnet

# Wait a moment
sleep 2

# Start services
sudo supervisorctl start advisory-testnet advisory-mainnet

# Wait for services to start
print_status "Waiting for services to start..."
sleep 10

# Check service status
print_status "Service status:"
sudo supervisorctl status advisory-testnet advisory-mainnet

echo ""

# Test service endpoints
print_status "Testing service endpoints..."

# Test testnet
print_status "Testing testnet (port 8080)..."
for i in {1..5}; do
    if curl -s --connect-timeout 5 http://localhost:8080/api/quorum/health >/dev/null 2>&1; then
        print_status "✅ Testnet service is responding!"
        curl -s http://localhost:8080/api/quorum/health | head -3
        break
    else
        print_warning "Attempt $i: Testnet not responding yet, waiting..."
        sleep 3
    fi
done

echo ""

# Test mainnet
print_status "Testing mainnet (port 8081)..."
for i in {1..5}; do
    if curl -s --connect-timeout 5 http://localhost:8081/api/quorum/health >/dev/null 2>&1; then
        print_status "✅ Mainnet service is responding!"
        curl -s http://localhost:8081/api/quorum/health | head -3
        break
    else
        print_warning "Attempt $i: Mainnet not responding yet, waiting..."
        sleep 3
    fi
done

echo ""

# Check for any remaining errors
print_status "Checking for recent errors..."
if [ -f "$DEPLOY_DIR/logs/advisory-testnet.err.log" ]; then
    RECENT_ERRORS=$(tail -5 "$DEPLOY_DIR/logs/advisory-testnet.err.log" 2>/dev/null | grep -v "^$" | wc -l)
    if [ "$RECENT_ERRORS" -gt 0 ]; then
        print_warning "Recent testnet errors found:"
        tail -5 "$DEPLOY_DIR/logs/advisory-testnet.err.log"
    else
        print_status "✅ No recent testnet errors"
    fi
fi

if [ -f "$DEPLOY_DIR/logs/advisory-mainnet.err.log" ]; then
    RECENT_ERRORS=$(tail -5 "$DEPLOY_DIR/logs/advisory-mainnet.err.log" 2>/dev/null | grep -v "^$" | wc -l)
    if [ "$RECENT_ERRORS" -gt 0 ]; then
        print_warning "Recent mainnet errors found:"
        tail -5 "$DEPLOY_DIR/logs/advisory-mainnet.err.log"
    else
        print_status "✅ No recent mainnet errors"
    fi
fi

echo ""
echo "========================================="
echo "Database Permissions Fix Complete"
echo "========================================="
echo ""

print_status "Your services should now be running properly!"
echo ""
print_status "Test commands:"
echo "  curl http://localhost:8080/api/quorum/health"
echo "  curl http://localhost:8081/api/quorum/health"
echo ""
print_status "Management commands:"
echo "  ~/advisory-node-deploy/manage.sh status"
echo "  ~/advisory-node-deploy/manage.sh logs testnet"
echo "  ~/advisory-node-deploy/manage.sh logs mainnet"


