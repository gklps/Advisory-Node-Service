#!/bin/bash

# Database Restore Script for Advisory Node Service
# Restores databases from backup files

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_DIR="$APP_DIR/backups"
DB_USER="advisory_user"

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

# Function to show usage
show_usage() {
    echo "Usage: $0 [testnet|mainnet] [backup_file]"
    echo ""
    echo "Examples:"
    echo "  $0 testnet                          # Restore latest testnet backup"
    echo "  $0 mainnet backup_20231201_120000   # Restore specific mainnet backup"
    echo ""
    echo "Available backups:"
    ls -la $BACKUP_DIR/*.gz 2>/dev/null || echo "No backups found in $BACKUP_DIR"
}

# Check arguments
if [ $# -eq 0 ]; then
    show_usage
    exit 1
fi

ENVIRONMENT=$1
BACKUP_FILE=$2

# Validate environment
if [[ "$ENVIRONMENT" != "testnet" && "$ENVIRONMENT" != "mainnet" ]]; then
    print_error "Environment must be 'testnet' or 'mainnet'"
    show_usage
    exit 1
fi

DB_NAME="advisory_$ENVIRONMENT"

# Find backup file
if [ -z "$BACKUP_FILE" ]; then
    # Use latest backup
    BACKUP_FILE=$(ls -t $BACKUP_DIR/${DB_NAME}_backup_*.sql.gz 2>/dev/null | head -1)
    if [ -z "$BACKUP_FILE" ]; then
        print_error "No backup files found for $ENVIRONMENT"
        exit 1
    fi
    print_status "Using latest backup: $(basename $BACKUP_FILE)"
else
    # Use specified backup file
    if [[ "$BACKUP_FILE" != *.gz ]]; then
        BACKUP_FILE="$BACKUP_DIR/${BACKUP_FILE}.sql.gz"
    elif [[ "$BACKUP_FILE" != "$BACKUP_DIR"* ]]; then
        BACKUP_FILE="$BACKUP_DIR/$BACKUP_FILE"
    fi
    
    if [ ! -f "$BACKUP_FILE" ]; then
        print_error "Backup file not found: $BACKUP_FILE"
        show_usage
        exit 1
    fi
fi

print_warning "⚠️  WARNING: This will completely replace the $ENVIRONMENT database!"
print_warning "⚠️  Current database: $DB_NAME"
print_warning "⚠️  Backup file: $(basename $BACKUP_FILE)"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    print_status "Restore cancelled."
    exit 0
fi

# Stop services before restore
print_status "Stopping Advisory Node services..."
sudo supervisorctl stop advisory-testnet advisory-mainnet || true

# Function to restore database
restore_database() {
    local db_name=$1
    local backup_file=$2
    
    print_status "Restoring $db_name from $(basename $backup_file)..."
    
    # Verify backup file integrity
    if ! zcat $backup_file | head -10 | grep -q "PostgreSQL database dump"; then
        print_error "❌ Backup file appears to be corrupted"
        return 1
    fi
    
    # Drop existing database and recreate
    print_status "Dropping existing database: $db_name"
    sudo -u postgres psql << EOF
SELECT pg_terminate_backend(pg_stat_activity.pid)
FROM pg_stat_activity
WHERE pg_stat_activity.datname = '$db_name'
  AND pid <> pg_backend_pid();

DROP DATABASE IF EXISTS $db_name;
CREATE DATABASE $db_name;
GRANT ALL PRIVILEGES ON DATABASE $db_name TO $DB_USER;
\q
EOF

    # Restore from backup
    print_status "Restoring data from backup..."
    if zcat $backup_file | psql -h localhost -U $DB_USER $db_name; then
        print_status "✅ Database restore completed successfully!"
        
        # Verify restoration by checking table count
        table_count=$(psql -h localhost -U $DB_USER $db_name -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" | xargs)
        print_status "✅ Restored $table_count tables in $db_name"
        
        return 0
    else
        print_error "❌ Failed to restore database"
        return 1
    fi
}

# Perform restoration
if restore_database "$DB_NAME" "$BACKUP_FILE"; then
    print_status "✅ Database restoration completed successfully!"
    
    # Restart services
    print_status "Restarting Advisory Node services..."
    sleep 2
    sudo supervisorctl start advisory-testnet advisory-mainnet
    
    # Wait for services to start
    print_status "Waiting for services to start..."
    sleep 5
    
    # Test the restored environment
    PORT=""
    if [ "$ENVIRONMENT" = "testnet" ]; then
        PORT="8080"
    else
        PORT="8081"
    fi
    
    print_status "Testing restored $ENVIRONMENT environment..."
    if curl -s http://localhost:$PORT/api/quorum/health > /dev/null; then
        print_status "✅ $ENVIRONMENT service is running successfully!"
    else
        print_warning "⚠️  $ENVIRONMENT service may not be ready yet. Check logs with: sudo supervisorctl tail advisory-$ENVIRONMENT"
    fi
    
    echo ""
    echo "========================================="
    echo "RESTORATION SUMMARY"
    echo "========================================="
    echo "✅ Database: $DB_NAME"
    echo "✅ Backup file: $(basename $BACKUP_FILE)"
    echo "✅ Restoration completed at: $(date)"
    echo ""
    echo "🔧 Next steps:"
    echo "   1. Verify data integrity"
    echo "   2. Test API endpoints"
    echo "   3. Monitor service logs"
    echo ""
    print_status "Database restoration completed successfully!"
else
    print_error "❌ Database restoration failed!"
    
    # Try to restart services anyway
    print_status "Attempting to restart services..."
    sudo supervisorctl restart advisory-testnet advisory-mainnet
    
    exit 1
fi
