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

echo ""
read -p "Enter database password for advisory_user: " -s DB_PASSWORD
echo ""
read -p "Enter your VM's domain name (optional, press enter to skip): " DOMAIN_NAME

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

# Create databases and user
sudo -u postgres psql << EOF
CREATE DATABASE advisory_testnet;
CREATE DATABASE advisory_mainnet;
CREATE USER advisory_user WITH PASSWORD '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE advisory_testnet TO advisory_user;
GRANT ALL PRIVILEGES ON DATABASE advisory_mainnet TO advisory_user;
\q
EOF

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
local   advisory_testnet    advisory_user                     md5
local   advisory_mainnet    advisory_user                     md5
host    advisory_testnet    advisory_user    127.0.0.1/32     md5
host    advisory_mainnet    advisory_user    127.0.0.1/32     md5
EOF

sudo systemctl restart postgresql

# Create application directory
print_status "Setting up application directory..."
sudo mkdir -p /opt/advisory-node/data
sudo chown -R $USER:$USER /opt/advisory-node

# Clone and build application (assuming we're in the repo directory)
print_status "Building Advisory Node application..."
cd /opt/advisory-node

# Copy current directory contents (if running from repo)
if [ -f "main.go" ]; then
    print_status "Copying application files..."
    cp -r * /opt/advisory-node/
else
    print_error "main.go not found. Please run this script from the advisory-node repository directory."
    exit 1
fi

go mod download
go build -o advisory-node

# Create environment files
print_status "Creating environment configuration files..."

# Testnet environment
cat > /opt/advisory-node/testnet.env << EOF
# Database Configuration
DB_TYPE=postgres
DB_HOST=localhost
DB_PORT=5432
DB_NAME=advisory_testnet
DB_USER=advisory_user
DB_PASSWORD=$DB_PASSWORD
DB_SSL_MODE=disable

# Server Configuration
PORT=8080
GIN_MODE=release
CORS_ORIGINS=*

# Environment Identifier
ENVIRONMENT=testnet
EOF

# Mainnet environment
cat > /opt/advisory-node/mainnet.env << EOF
# Database Configuration
DB_TYPE=postgres
DB_HOST=localhost
DB_PORT=5432
DB_NAME=advisory_mainnet
DB_USER=advisory_user
DB_PASSWORD=$DB_PASSWORD
DB_SSL_MODE=disable

# Server Configuration
PORT=8081
GIN_MODE=release
CORS_ORIGINS=*

# Environment Identifier
ENVIRONMENT=mainnet
EOF

# Create startup scripts
print_status "Creating startup scripts..."

# Testnet startup script
cat > /opt/advisory-node/start-testnet.sh << 'EOF'
#!/bin/bash
source /opt/advisory-node/testnet.env
export DB_TYPE DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD DB_SSL_MODE
export PORT GIN_MODE CORS_ORIGINS ENVIRONMENT

echo "Starting Advisory Node - TESTNET"
echo "Port: $PORT"
echo "Database: $DB_NAME"
echo "Environment: $ENVIRONMENT"

cd /opt/advisory-node
./advisory-node
EOF

# Mainnet startup script
cat > /opt/advisory-node/start-mainnet.sh << 'EOF'
#!/bin/bash
source /opt/advisory-node/mainnet.env
export DB_TYPE DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD DB_SSL_MODE
export PORT GIN_MODE CORS_ORIGINS ENVIRONMENT

echo "Starting Advisory Node - MAINNET"
echo "Port: $PORT"
echo "Database: $DB_NAME"
echo "Environment: $ENVIRONMENT"

cd /opt/advisory-node
./advisory-node
EOF

chmod +x /opt/advisory-node/start-testnet.sh
chmod +x /opt/advisory-node/start-mainnet.sh

# Create supervisor configurations
print_status "Setting up Supervisor process management..."

sudo tee /etc/supervisor/conf.d/advisory-testnet.conf > /dev/null << EOF
[program:advisory-testnet]
command=/opt/advisory-node/start-testnet.sh
directory=/opt/advisory-node
autostart=true
autorestart=true
stderr_logfile=/var/log/advisory-testnet.err.log
stdout_logfile=/var/log/advisory-testnet.out.log
user=$USER
environment=HOME="/opt/advisory-node",USER="$USER"
EOF

sudo tee /etc/supervisor/conf.d/advisory-mainnet.conf > /dev/null << EOF
[program:advisory-mainnet]
command=/opt/advisory-node/start-mainnet.sh
directory=/opt/advisory-node
autostart=true
autorestart=true
stderr_logfile=/var/log/advisory-mainnet.err.log
stdout_logfile=/var/log/advisory-mainnet.out.log
user=$USER
environment=HOME="/opt/advisory-node",USER="$USER"
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

# Test services
print_status "Testing service endpoints..."

echo ""
echo "Testing testnet (port 8080)..."
if curl -s http://localhost:8080/api/quorum/health > /dev/null; then
    print_status "Testnet service is running successfully!"
else
    print_warning "Testnet service may not be ready yet. Check logs with: sudo supervisorctl tail advisory-testnet"
fi

echo ""
echo "Testing mainnet (port 8081)..."
if curl -s http://localhost:8081/api/quorum/health > /dev/null; then
    print_status "Mainnet service is running successfully!"
else
    print_warning "Mainnet service may not be ready yet. Check logs with: sudo supervisorctl tail advisory-mainnet"
fi

# Create management script
print_status "Creating management script..."
cat > /opt/advisory-node/manage.sh << 'EOF'
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
        cd /opt/advisory-node
        git pull
        go build -o advisory-node
        sudo supervisorctl restart advisory-testnet advisory-mainnet
        echo "Update complete!"
        ;;
    *)
        echo "Usage: $0 {status|start|stop|restart|logs|update}"
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

chmod +x /opt/advisory-node/manage.sh

print_status "Setup completed successfully!"
echo ""
echo "========================================="
echo "SETUP SUMMARY"
echo "========================================="
echo "✅ PostgreSQL databases created:"
echo "   - advisory_testnet (port 8080)"
echo "   - advisory_mainnet (port 8081)"
echo ""
echo "✅ Services configured with Supervisor"
echo "✅ Firewall configured"
if [ ! -z "$DOMAIN_NAME" ]; then
echo "✅ Nginx reverse proxy configured"
echo "   - http://testnet-advisory.$DOMAIN_NAME"
echo "   - http://mainnet-advisory.$DOMAIN_NAME"
fi
echo ""
echo "🔧 Management commands:"
echo "   /opt/advisory-node/manage.sh status"
echo "   /opt/advisory-node/manage.sh restart"
echo "   /opt/advisory-node/manage.sh logs testnet"
echo "   /opt/advisory-node/manage.sh logs mainnet"
echo ""
echo "🌐 Service URLs:"
echo "   Testnet:  http://$(hostname -I | awk '{print $1}'):8080"
echo "   Mainnet:  http://$(hostname -I | awk '{print $1}'):8081"
echo ""
echo "📋 Next steps:"
echo "   1. Test the endpoints with curl or your browser"
echo "   2. Configure DNS if using domain names"
echo "   3. Set up SSL certificates for production"
echo "   4. Configure monitoring and backups"
echo ""
print_status "Advisory Node Service is ready to use!"
