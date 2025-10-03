#!/bin/bash

# VM Setup Script for Advisory Node Service
# This script automates the initial setup of testnet and mainnet environments

set -e

echo "========================================="
echo "Advisory Node VM Setup Script"
echo "========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    print_error "Please do not run this script as root. Use a regular user with sudo privileges."
    exit 1
fi

# Prompt for configuration
echo "This script will set up Advisory Node Service with:"
echo "- PostgreSQL database"
echo "- Testnet environment (port 8080)"
echo "- Mainnet environment (port 8081)"
echo "- Supervisor process management"
echo ""

read -p "Continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 1
fi

# Configuration options (you can modify these)
DEFAULT_DB_USER="advisory_user"
DEFAULT_TESTNET_PORT="8080"
DEFAULT_MAINNET_PORT="8081"
DEFAULT_TESTNET_DB="advisory_testnet"
DEFAULT_MAINNET_DB="advisory_mainnet"

echo ""
echo "🔧 Configuration Options:"
echo "   Database User: $DEFAULT_DB_USER"
echo "   Testnet Port: $DEFAULT_TESTNET_PORT"
echo "   Mainnet Port: $DEFAULT_MAINNET_PORT"
echo "   Testnet DB: $DEFAULT_TESTNET_DB"
echo "   Mainnet DB: $DEFAULT_MAINNET_DB"
echo ""

read -p "Enter database password for $DEFAULT_DB_USER: " -s DB_PASSWORD
echo ""
read -p "Enter your VM's domain name (optional, press enter to skip): " DOMAIN_NAME

# Allow customization
echo ""
read -p "Use custom configuration? (y/n, default: n): " -n 1 -r CUSTOM_CONFIG
echo ""
if [[ $CUSTOM_CONFIG =~ ^[Yy]$ ]]; then
    read -p "Database username (default: $DEFAULT_DB_USER): " CUSTOM_DB_USER
    read -p "Testnet port (default: $DEFAULT_TESTNET_PORT): " CUSTOM_TESTNET_PORT
    read -p "Mainnet port (default: $DEFAULT_MAINNET_PORT): " CUSTOM_MAINNET_PORT
    read -p "Testnet database name (default: $DEFAULT_TESTNET_DB): " CUSTOM_TESTNET_DB
    read -p "Mainnet database name (default: $DEFAULT_MAINNET_DB): " CUSTOM_MAINNET_DB
    
    # Use custom values if provided
    DB_USER=${CUSTOM_DB_USER:-$DEFAULT_DB_USER}
    TESTNET_PORT=${CUSTOM_TESTNET_PORT:-$DEFAULT_TESTNET_PORT}
    MAINNET_PORT=${CUSTOM_MAINNET_PORT:-$DEFAULT_MAINNET_PORT}
    TESTNET_DB=${CUSTOM_TESTNET_DB:-$DEFAULT_TESTNET_DB}
    MAINNET_DB=${CUSTOM_MAINNET_DB:-$DEFAULT_MAINNET_DB}
else
    # Use defaults
    DB_USER=$DEFAULT_DB_USER
    TESTNET_PORT=$DEFAULT_TESTNET_PORT
    MAINNET_PORT=$DEFAULT_MAINNET_PORT
    TESTNET_DB=$DEFAULT_TESTNET_DB
    MAINNET_DB=$DEFAULT_MAINNET_DB
fi

print_status "Using configuration:"
print_status "  Database User: $DB_USER"
print_status "  Testnet: Port $TESTNET_PORT, Database $TESTNET_DB"
print_status "  Mainnet: Port $MAINNET_PORT, Database $MAINNET_DB"

print_status "Starting VM setup..."

# Update system
print_status "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install dependencies
print_status "Installing dependencies..."
sudo apt install -y postgresql postgresql-contrib git supervisor nginx htop curl jq

# Install Go if not present
if ! command -v go &> /dev/null; then
    print_status "Installing Go..."
    wget https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
    sudo tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    export PATH=$PATH:/usr/local/go/bin
    rm go1.21.0.linux-amd64.tar.gz
    print_status "Go installed successfully"
else
    print_status "Go is already installed"
fi

# Setup PostgreSQL
print_status "Configuring PostgreSQL..."
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Create databases and user with proper permissions
print_status "Creating databases and configuring permissions..."
sudo -u postgres psql << EOF
-- Create databases
CREATE DATABASE $TESTNET_DB;
CREATE DATABASE $MAINNET_DB;

-- Create user
CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';

-- Grant database-level privileges
GRANT ALL PRIVILEGES ON DATABASE $TESTNET_DB TO $DB_USER;
GRANT ALL PRIVILEGES ON DATABASE $MAINNET_DB TO $DB_USER;

-- Make user owner of databases (ensures all permissions)
ALTER DATABASE $TESTNET_DB OWNER TO $DB_USER;
ALTER DATABASE $MAINNET_DB OWNER TO $DB_USER;

-- Connect to testnet database and set schema permissions
\c $TESTNET_DB
GRANT ALL PRIVILEGES ON SCHEMA public TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;

-- Connect to mainnet database and set schema permissions
\c $MAINNET_DB
GRANT ALL PRIVILEGES ON SCHEMA public TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;

\q
EOF

print_status "✅ Databases created with proper permissions"

# Configure PostgreSQL authentication
print_status "Configuring PostgreSQL authentication..."
PG_VERSION=$(sudo -u postgres psql -c "SHOW server_version;" | grep -oP '\d+\.\d+' | head -1)
PG_MAJOR_VERSION=$(echo $PG_VERSION | cut -d. -f1)

PG_HBA_PATH="/etc/postgresql/$PG_MAJOR_VERSION/main/pg_hba.conf"

# Backup original pg_hba.conf
sudo cp $PG_HBA_PATH $PG_HBA_PATH.backup

# Add advisory database entries
sudo tee -a $PG_HBA_PATH > /dev/null << EOF

# Advisory Node Service connections
local   $TESTNET_DB    $DB_USER                     md5
local   $MAINNET_DB    $DB_USER                     md5
host    $TESTNET_DB    $DB_USER    127.0.0.1/32     md5
host    $MAINNET_DB    $DB_USER    127.0.0.1/32     md5
EOF

sudo systemctl restart postgresql

# Determine script and project directories using relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# For deployment, we'll use a local directory instead of /opt
DEPLOY_BASE_DIR="$HOME/advisory-node-deploy"
APP_DIR="$DEPLOY_BASE_DIR"

print_status "Script directory: $SCRIPT_DIR"
print_status "Project directory: $PROJECT_DIR"
print_status "Deployment directory: $APP_DIR"

# Check for main.go in multiple possible locations
MAIN_GO_LOCATIONS=(
    "$PROJECT_DIR/main.go"
    "$PROJECT_DIR/main_db.go"  
    "$SCRIPT_DIR/../main.go"
    "$SCRIPT_DIR/../main_db.go"
    "$(pwd)/main.go"
    "$(pwd)/main_db.go"
)

MAIN_GO_FOUND=""
for location in "${MAIN_GO_LOCATIONS[@]}"; do
    if [ -f "$location" ]; then
        MAIN_GO_FOUND="$location"
        PROJECT_DIR="$(dirname "$location")"
        print_status "Found main.go at: $MAIN_GO_FOUND"
        print_status "Using project directory: $PROJECT_DIR"
        break
    fi
done

if [ -z "$MAIN_GO_FOUND" ]; then
    print_error "main.go not found in any expected location:"
    for location in "${MAIN_GO_LOCATIONS[@]}"; do
        print_error "  - $location"
    done
    print_error ""
    print_error "Please ensure you're running this script from the correct location."
    print_error "Current directory: $(pwd)"
    print_error "Script directory: $SCRIPT_DIR"
    exit 1
fi

# Create deployment directory structure
print_status "Setting up deployment directory..."
mkdir -p $APP_DIR/data
mkdir -p $APP_DIR/scripts
mkdir -p $APP_DIR/backups
mkdir -p $APP_DIR/logs

# Copy application files
print_status "Copying application files..."
print_status "Copying from: $PROJECT_DIR"
print_status "Copying to: $APP_DIR"

# List what we're copying for debugging
print_status "Files to copy:"
ls -la "$PROJECT_DIR" | head -10

cp -r $PROJECT_DIR/* $APP_DIR/

# Verify critical files were copied
print_status "Verifying copied files..."
if [ ! -f "$APP_DIR/go.mod" ]; then
    print_error "go.mod not found in deployment directory"
    exit 1
fi

if [ ! -f "$APP_DIR/main.go" ] && [ ! -f "$APP_DIR/main_db.go" ]; then
    print_error "No main Go file found in deployment directory"
    ls -la "$APP_DIR/"
    exit 1
fi

# Build application
print_status "Building Advisory Node application..."
cd $APP_DIR

# Check if we have go.mod
if [ ! -f "go.mod" ]; then
    print_error "go.mod not found in $APP_DIR"
    print_error "Directory contents:"
    ls -la
    exit 1
fi

print_status "Downloading Go modules..."
go mod download

print_status "Building binary..."
# Try to build with the main file we found
if [ -f "main.go" ]; then
    go build -o advisory-node main.go
elif [ -f "main_db.go" ]; then
    go build -o advisory-node main_db.go
else
    print_error "No suitable main Go file found for building"
    exit 1
fi

# Verify the binary was created
if [ ! -f "advisory-node" ]; then
    print_error "Failed to build advisory-node binary"
    exit 1
fi

print_status "✅ Binary built successfully: $(ls -lh advisory-node)"

# Create environment files
print_status "Creating environment configuration files..."

# Testnet environment
cat > $APP_DIR/testnet.env << EOF
# Database Configuration
DB_TYPE=postgres
DB_HOST=localhost
DB_PORT=5432
DB_NAME=$TESTNET_DB
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_SSL_MODE=disable

# Server Configuration
PORT=$TESTNET_PORT
GIN_MODE=release
CORS_ORIGINS=*

# Environment Identifier
ENVIRONMENT=testnet
EOF

# Mainnet environment
cat > $APP_DIR/mainnet.env << EOF
# Database Configuration
DB_TYPE=postgres
DB_HOST=localhost
DB_PORT=5432
DB_NAME=$MAINNET_DB
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_SSL_MODE=disable

# Server Configuration
PORT=$MAINNET_PORT
GIN_MODE=release
CORS_ORIGINS=*

# Environment Identifier
ENVIRONMENT=mainnet
EOF

# Create startup scripts
print_status "Creating startup scripts..."

# Testnet startup script
cat > $APP_DIR/start-testnet.sh << EOF
#!/bin/bash
source $APP_DIR/testnet.env
export DB_TYPE DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD DB_SSL_MODE
export PORT GIN_MODE CORS_ORIGINS ENVIRONMENT

echo "Starting Advisory Node - TESTNET"
echo "Port: \$PORT"
echo "Database: \$DB_NAME"
echo "Environment: \$ENVIRONMENT"

cd $APP_DIR
./advisory-node
EOF

# Mainnet startup script
cat > $APP_DIR/start-mainnet.sh << EOF
#!/bin/bash
source $APP_DIR/mainnet.env
export DB_TYPE DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD DB_SSL_MODE
export PORT GIN_MODE CORS_ORIGINS ENVIRONMENT

echo "Starting Advisory Node - MAINNET"
echo "Port: \$PORT"
echo "Database: \$DB_NAME"
echo "Environment: \$ENVIRONMENT"

cd $APP_DIR
./advisory-node
EOF

chmod +x $APP_DIR/start-testnet.sh
chmod +x $APP_DIR/start-mainnet.sh

# Create supervisor configurations
print_status "Setting up Supervisor process management..."

sudo tee /etc/supervisor/conf.d/advisory-testnet.conf > /dev/null << EOF
[program:advisory-testnet]
command=$APP_DIR/start-testnet.sh
directory=$APP_DIR
autostart=true
autorestart=true
stderr_logfile=$APP_DIR/logs/advisory-testnet.err.log
stdout_logfile=$APP_DIR/logs/advisory-testnet.out.log
user=$USER
environment=HOME="$APP_DIR",USER="$USER"
EOF

sudo tee /etc/supervisor/conf.d/advisory-mainnet.conf > /dev/null << EOF
[program:advisory-mainnet]
command=$APP_DIR/start-mainnet.sh
directory=$APP_DIR
autostart=true
autorestart=true
stderr_logfile=$APP_DIR/logs/advisory-mainnet.err.log
stdout_logfile=$APP_DIR/logs/advisory-mainnet.out.log
user=$USER
environment=HOME="$APP_DIR",USER="$USER"
EOF

# Setup Nginx (if domain provided)
if [ ! -z "$DOMAIN_NAME" ]; then
    print_status "Configuring Nginx reverse proxy..."
    
    sudo tee /etc/nginx/sites-available/advisory-testnet > /dev/null << EOF
server {
    listen 80;
    server_name testnet-advisory.$DOMAIN_NAME;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    sudo tee /etc/nginx/sites-available/advisory-mainnet > /dev/null << EOF
server {
    listen 80;
    server_name mainnet-advisory.$DOMAIN_NAME;

    location / {
        proxy_pass http://localhost:8081;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    sudo ln -sf /etc/nginx/sites-available/advisory-testnet /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/advisory-mainnet /etc/nginx/sites-enabled/
    
    sudo nginx -t && sudo systemctl restart nginx
fi

# Configure firewall
print_status "Configuring firewall..."
sudo ufw allow ssh
sudo ufw allow 80
sudo ufw allow 443
sudo ufw allow 8080
sudo ufw allow 8081
echo "y" | sudo ufw enable

# Start services
print_status "Starting Advisory Node services..."
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start advisory-testnet advisory-mainnet

# Wait a moment for services to start
sleep 5

# Enhanced service testing with retries
print_status "Testing service endpoints..."

# Wait for services to fully initialize
print_status "Waiting for services to initialize (30 seconds)..."
sleep 30

# Test testnet service with retries
echo ""
print_status "Testing testnet service (port $TESTNET_PORT)..."
TESTNET_SUCCESS=false
for i in {1..10}; do
    if curl -s --connect-timeout 5 http://localhost:$TESTNET_PORT/api/quorum/health >/dev/null 2>&1; then
        print_status "✅ Testnet service is running successfully!"
        curl -s http://localhost:$TESTNET_PORT/api/quorum/health | head -3
        TESTNET_SUCCESS=true
        break
    else
        print_warning "Attempt $i: Testnet not responding, waiting 5 seconds..."
        sleep 5
    fi
done

if [ "$TESTNET_SUCCESS" = false ]; then
    print_error "❌ Testnet service failed to start properly"
    print_status "Checking testnet logs:"
    sudo supervisorctl tail advisory-testnet | tail -10
fi

# Test mainnet service with retries
echo ""
print_status "Testing mainnet service (port $MAINNET_PORT)..."
MAINNET_SUCCESS=false
for i in {1..10}; do
    if curl -s --connect-timeout 5 http://localhost:$MAINNET_PORT/api/quorum/health >/dev/null 2>&1; then
        print_status "✅ Mainnet service is running successfully!"
        curl -s http://localhost:$MAINNET_PORT/api/quorum/health | head -3
        MAINNET_SUCCESS=true
        break
    else
        print_warning "Attempt $i: Mainnet not responding, waiting 5 seconds..."
        sleep 5
    fi
done

if [ "$MAINNET_SUCCESS" = false ]; then
    print_error "❌ Mainnet service failed to start properly"
    print_status "Checking mainnet logs:"
    sudo supervisorctl tail advisory-mainnet | tail -10
fi

# Database connectivity test
print_status "Testing database connectivity..."
if PGPASSWORD="$DB_PASSWORD" psql -h localhost -U "$DB_USER" -d "$TESTNET_DB" -c "SELECT current_database(), current_user;" >/dev/null 2>&1; then
    print_status "✅ Testnet database connection successful"
else
    print_error "❌ Testnet database connection failed"
fi

if PGPASSWORD="$DB_PASSWORD" psql -h localhost -U "$DB_USER" -d "$MAINNET_DB" -c "SELECT current_database(), current_user;" >/dev/null 2>&1; then
    print_status "✅ Mainnet database connection successful"
else
    print_error "❌ Mainnet database connection failed"
fi

# Create management script
print_status "Creating management script..."
cat > $APP_DIR/manage.sh << EOF
#!/bin/bash

case "$1" in
    status)
        echo "Service Status:"
        sudo supervisorctl status advisory-testnet advisory-mainnet
        echo ""
        echo "Health Checks:"
        echo "Testnet: $(curl -s http://localhost:8080/api/quorum/health | jq -r '.status // "Error"')"
        echo "Mainnet: $(curl -s http://localhost:8081/api/quorum/health | jq -r '.status // "Error"')"
        ;;
    restart)
        echo "Restarting services..."
        sudo supervisorctl restart advisory-testnet advisory-mainnet
        ;;
    stop)
        echo "Stopping services..."
        sudo supervisorctl stop advisory-testnet advisory-mainnet
        ;;
    start)
        echo "Starting services..."
        sudo supervisorctl start advisory-testnet advisory-mainnet
        ;;
    logs)
        if [ "$2" = "testnet" ]; then
            sudo supervisorctl tail -f advisory-testnet
        elif [ "$2" = "mainnet" ]; then
            sudo supervisorctl tail -f advisory-mainnet
        else
            echo "Usage: $0 logs [testnet|mainnet]"
        fi
        ;;
    update)
        echo "Updating application..."
        cd $PROJECT_DIR
        git pull
        cp -r * $APP_DIR/
        cd $APP_DIR
        go build -o advisory-node
        sudo supervisorctl restart advisory-testnet advisory-mainnet
        echo "Update complete!"
        ;;
    *)
        echo "Usage: \$0 {status|start|stop|restart|logs|update}"
        echo ""
        echo "Commands:"
        echo "  status  - Show service status and health"
        echo "  start   - Start both services"
        echo "  stop    - Stop both services"
        echo "  restart - Restart both services"
        echo "  logs    - Show logs (specify testnet or mainnet)"
        echo "  update  - Update and restart services"
        ;;
esac
EOF

chmod +x $APP_DIR/manage.sh

# Setup auto-start on reboot
print_status "Setting up auto-start on reboot..."
chmod +x $APP_DIR/scripts/auto-start-service.sh

# Add to crontab for auto-start on reboot
(crontab -l 2>/dev/null | grep -v "auto-start-service.sh"; echo "@reboot $APP_DIR/scripts/auto-start-service.sh") | crontab -

# Also ensure supervisor starts on boot
sudo systemctl enable supervisor

print_status "✅ Auto-start on reboot configured"
print_status "Setup completed successfully!"
echo ""
echo ""
echo "========================================="
echo "🎉 SETUP COMPLETED SUCCESSFULLY!"
echo "========================================="

# Show final status
SETUP_SUCCESS=true
if [ "$TESTNET_SUCCESS" = false ] || [ "$MAINNET_SUCCESS" = false ]; then
    SETUP_SUCCESS=false
fi

if [ "$SETUP_SUCCESS" = true ]; then
    echo "✅ All services are running properly!"
else
    echo "⚠️  Some services may need attention - check logs"
fi

echo ""
echo "📊 Deployment Summary:"
echo "   🗄️  Database: PostgreSQL with proper permissions"
echo "   🌐 Testnet:  http://$(hostname -I | awk '{print $1}'):$TESTNET_PORT ($TESTNET_DB)"
echo "   🌐 Mainnet:  http://$(hostname -I | awk '{print $1}'):$MAINNET_PORT ($MAINNET_DB)"
echo "   👤 DB User:  $DB_USER"
echo "   🔧 Management: $APP_DIR/manage.sh"

if [ ! -z "$DOMAIN_NAME" ]; then
echo ""
echo "🌍 Domain Access (if DNS configured):"
echo "   🧪 Testnet: http://testnet-advisory.$DOMAIN_NAME"
echo "   🚀 Mainnet: http://mainnet-advisory.$DOMAIN_NAME"
fi

echo ""
echo "🔧 Management Commands:"
echo "   $APP_DIR/manage.sh status     # Check service status"
echo "   $APP_DIR/manage.sh restart    # Restart services"
echo "   $APP_DIR/manage.sh logs testnet    # View testnet logs"
echo "   $APP_DIR/manage.sh logs mainnet    # View mainnet logs"
echo "   $APP_DIR/manage.sh update     # Update from source"

echo ""
echo "🧪 Test Commands:"
echo "   curl http://localhost:$TESTNET_PORT/api/quorum/health"
echo "   curl http://localhost:$MAINNET_PORT/api/quorum/health"
echo "   curl \"http://localhost:$TESTNET_PORT/api/quorum/available?count=5&transaction_amount=100\""

echo ""
echo "🔄 Auto-start Configuration:"
echo "   ✅ Services auto-restart on crash (Supervisor)"
echo "   ✅ Services auto-start on reboot (Cron job)"
echo "   ✅ System services enabled (PostgreSQL, Supervisor)"

echo ""
echo "📂 Important Locations:"
echo "   📁 Deployment: $APP_DIR"
echo "   📝 Logs: $APP_DIR/logs/"
echo "   ⚙️  Config: $APP_DIR/*.env"
echo "   💾 Backups: $APP_DIR/backups/"

echo ""
echo "🚨 Troubleshooting (if needed):"
echo "   📊 sudo supervisorctl status"
echo "   📋 $APP_DIR/manage.sh status"
echo "   🔍 sudo supervisorctl tail advisory-testnet"
echo "   🔍 sudo supervisorctl tail advisory-mainnet"

if [ "$SETUP_SUCCESS" = true ]; then
    echo ""
    echo "🎯 Your Advisory Node Service is ready for production!"
    echo "🚀 Both testnet and mainnet environments are operational."
else
    echo ""
    echo "⚠️  Setup completed but some services need attention."
    echo "📋 Check the service logs and run the troubleshooting commands above."
fi

echo ""
echo "========================================="
