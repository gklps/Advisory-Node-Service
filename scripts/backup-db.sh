#!/bin/bash

# Database Backup Script for Advisory Node Service
# Creates backups of both testnet and mainnet databases

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_DIR="$APP_DIR/backups"
DATE=$(date +"%Y%m%d_%H%M%S")
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

# Create backup directory
mkdir -p $BACKUP_DIR

print_status "Starting database backup process..."

# Function to backup a database
backup_database() {
    local db_name=$1
    local backup_file="$BACKUP_DIR/${db_name}_backup_${DATE}.sql"
    
    print_status "Backing up $db_name..."
    
    if pg_dump -h localhost -U $DB_USER $db_name > $backup_file; then
        # Compress the backup
        gzip $backup_file
        backup_file="${backup_file}.gz"
        
        # Get file size
        size=$(du -h $backup_file | cut -f1)
        
        print_status "✅ $db_name backup completed: $backup_file ($size)"
        
        # Verify backup integrity
        if zcat $backup_file | head -10 | grep -q "PostgreSQL database dump"; then
            print_status "✅ Backup verification passed for $db_name"
        else
            print_error "❌ Backup verification failed for $db_name"
            return 1
        fi
    else
        print_error "❌ Failed to backup $db_name"
        return 1
    fi
}

# Backup both databases
print_status "Creating backups for testnet and mainnet databases..."

if backup_database "advisory_testnet" && backup_database "advisory_mainnet"; then
    print_status "✅ All database backups completed successfully!"
else
    print_error "❌ Some backups failed!"
    exit 1
fi

# Cleanup old backups (keep last 7 days)
print_status "Cleaning up old backups (keeping last 7 days)..."
find $BACKUP_DIR -name "*.sql.gz" -mtime +7 -delete

# Show backup summary
print_status "Backup Summary:"
echo ""
echo "📁 Backup Location: $BACKUP_DIR"
echo "📅 Backup Date: $DATE"
echo ""
echo "📊 Current Backups:"
ls -lah $BACKUP_DIR/*.gz 2>/dev/null | tail -10 || echo "No backups found"
echo ""
echo "💾 Total Backup Size: $(du -sh $BACKUP_DIR | cut -f1)"

print_status "Backup process completed!"
