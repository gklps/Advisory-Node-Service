# VM Deployment Guide: Advisory Node Service

## Overview

This guide will help you deploy the Advisory Node Service on your VM with separate **testnet** and **mainnet** environments using local PostgreSQL or SQLite databases.

## Architecture

```
VM Server
├── PostgreSQL Database (Local)
│   ├── advisory_testnet (Database)
│   └── advisory_mainnet (Database)
├── Advisory Node Services
│   ├── Testnet Instance (Port 8080)
│   └── Mainnet Instance (Port 8081)
└── Reverse Proxy (Nginx - Optional)
    ├── testnet.yourdomain.com → :8080
    └── mainnet.yourdomain.com → :8081
```

## Prerequisites

### System Requirements
- Ubuntu 20.04+ or CentOS 8+ VM
- At least 2GB RAM, 20GB storage
- Go 1.19+ installed
- PostgreSQL 12+ (recommended) or SQLite support

### Install Dependencies

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install PostgreSQL
sudo apt install postgresql postgresql-contrib -y

# Install Go (if not installed)
wget https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc

# Install Git
sudo apt install git -y

# Install process manager (optional)
sudo apt install supervisor -y
```

## Database Setup

### 1. Configure PostgreSQL

```bash
# Start PostgreSQL service
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Switch to postgres user
sudo -u postgres psql

# Create databases and users
CREATE DATABASE advisory_testnet;
CREATE DATABASE advisory_mainnet;
CREATE USER advisory_user WITH PASSWORD 'your_secure_password';
GRANT ALL PRIVILEGES ON DATABASE advisory_testnet TO advisory_user;
GRANT ALL PRIVILEGES ON DATABASE advisory_mainnet TO advisory_user;

# Exit psql
\q
```

### 2. Configure PostgreSQL Authentication

```bash
# Edit pg_hba.conf to allow local connections
sudo nano /etc/postgresql/12/main/pg_hba.conf

# Add these lines (replace existing local entries):
local   advisory_testnet    advisory_user                     md5
local   advisory_mainnet    advisory_user                     md5
host    advisory_testnet    advisory_user    127.0.0.1/32     md5
host    advisory_mainnet    advisory_user    127.0.0.1/32     md5

# Restart PostgreSQL
sudo systemctl restart postgresql
```

## Application Deployment

### 1. Clone and Build

```bash
# Create application directory
sudo mkdir -p /opt/advisory-node
cd /opt/advisory-node

# Clone repository
git clone <your-repository-url> .

# Build the application
go mod download
go build -o advisory-node

# Make executable
chmod +x advisory-node
```

### 2. Create Environment Files

#### Testnet Environment (`/opt/advisory-node/testnet.env`)

```bash
# Database Configuration
DB_TYPE=postgres
DB_HOST=localhost
DB_PORT=5432
DB_NAME=advisory_testnet
DB_USER=advisory_user
DB_PASSWORD=your_secure_password
DB_SSL_MODE=disable

# Server Configuration
PORT=8080
GIN_MODE=release
CORS_ORIGINS=*

# Environment Identifier
ENVIRONMENT=testnet
```

#### Mainnet Environment (`/opt/advisory-node/mainnet.env`)

```bash
# Database Configuration
DB_TYPE=postgres
DB_HOST=localhost
DB_PORT=5432
DB_NAME=advisory_mainnet
DB_USER=advisory_user
DB_PASSWORD=your_secure_password
DB_SSL_MODE=disable

# Server Configuration
PORT=8081
GIN_MODE=release
CORS_ORIGINS=*

# Environment Identifier
ENVIRONMENT=mainnet
```

### 3. Create Startup Scripts

#### Testnet Startup Script (`/opt/advisory-node/start-testnet.sh`)

```bash
#!/bin/bash

# Load testnet environment
source /opt/advisory-node/testnet.env

# Export variables
export DB_TYPE DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD DB_SSL_MODE
export PORT GIN_MODE CORS_ORIGINS ENVIRONMENT

echo "Starting Advisory Node - TESTNET"
echo "Port: $PORT"
echo "Database: $DB_NAME"
echo "Environment: $ENVIRONMENT"

cd /opt/advisory-node
./advisory-node -port=$PORT -mode=$GIN_MODE
```

#### Mainnet Startup Script (`/opt/advisory-node/start-mainnet.sh`)

```bash
#!/bin/bash

# Load mainnet environment
source /opt/advisory-node/mainnet.env

# Export variables
export DB_TYPE DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD DB_SSL_MODE
export PORT GIN_MODE CORS_ORIGINS ENVIRONMENT

echo "Starting Advisory Node - MAINNET"
echo "Port: $PORT"
echo "Database: $DB_NAME"
echo "Environment: $ENVIRONMENT"

cd /opt/advisory-node
./advisory-node -port=$PORT -mode=$GIN_MODE
```

```bash
# Make scripts executable
chmod +x /opt/advisory-node/start-testnet.sh
chmod +x /opt/advisory-node/start-mainnet.sh
```

## Process Management with Supervisor

### 1. Create Supervisor Configuration

#### Testnet Service (`/etc/supervisor/conf.d/advisory-testnet.conf`)

```ini
[program:advisory-testnet]
command=/opt/advisory-node/start-testnet.sh
directory=/opt/advisory-node
autostart=true
autorestart=true
stderr_logfile=/var/log/advisory-testnet.err.log
stdout_logfile=/var/log/advisory-testnet.out.log
user=www-data
environment=HOME="/opt/advisory-node",USER="www-data"
```

#### Mainnet Service (`/etc/supervisor/conf.d/advisory-mainnet.conf`)

```ini
[program:advisory-mainnet]
command=/opt/advisory-node/start-mainnet.sh
directory=/opt/advisory-node
autostart=true
autorestart=true
stderr_logfile=/var/log/advisory-mainnet.err.log
stdout_logfile=/var/log/advisory-mainnet.out.log
user=www-data
environment=HOME="/opt/advisory-node",USER="www-data"
```

### 2. Start Services

```bash
# Reload supervisor configuration
sudo supervisorctl reread
sudo supervisorctl update

# Start services
sudo supervisorctl start advisory-testnet
sudo supervisorctl start advisory-mainnet

# Check status
sudo supervisorctl status
```

## Nginx Reverse Proxy (Optional)

### 1. Install Nginx

```bash
sudo apt install nginx -y
```

### 2. Configure Virtual Hosts

#### Testnet Configuration (`/etc/nginx/sites-available/advisory-testnet`)

```nginx
server {
    listen 80;
    server_name testnet-advisory.yourdomain.com;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

#### Mainnet Configuration (`/etc/nginx/sites-available/advisory-mainnet`)

```nginx
server {
    listen 80;
    server_name mainnet-advisory.yourdomain.com;

    location / {
        proxy_pass http://localhost:8081;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 3. Enable Sites

```bash
# Enable sites
sudo ln -s /etc/nginx/sites-available/advisory-testnet /etc/nginx/sites-enabled/
sudo ln -s /etc/nginx/sites-available/advisory-mainnet /etc/nginx/sites-enabled/

# Test configuration
sudo nginx -t

# Restart Nginx
sudo systemctl restart nginx
```

## Firewall Configuration

```bash
# Allow SSH, HTTP, and custom ports
sudo ufw allow ssh
sudo ufw allow 80
sudo ufw allow 443
sudo ufw allow 8080
sudo ufw allow 8081

# Enable firewall
sudo ufw enable
```

## Testing Deployment

### 1. Health Checks

```bash
# Test testnet
curl http://localhost:8080/api/quorum/health
curl http://your-vm-ip:8080/api/quorum/health

# Test mainnet
curl http://localhost:8081/api/quorum/health
curl http://your-vm-ip:8081/api/quorum/health
```

### 2. Database Connectivity

```bash
# Check PostgreSQL connections
sudo -u postgres psql -d advisory_testnet -c "SELECT current_database();"
sudo -u postgres psql -d advisory_mainnet -c "SELECT current_database();"
```

### 3. Service Status

```bash
# Check supervisor services
sudo supervisorctl status

# Check logs
sudo tail -f /var/log/advisory-testnet.out.log
sudo tail -f /var/log/advisory-mainnet.out.log
```

## Alternative: SQLite Setup

If you prefer SQLite over PostgreSQL:

### 1. Create SQLite Environment Files

#### Testnet SQLite (`testnet-sqlite.env`)

```bash
# Database Configuration
DB_TYPE=sqlite
DB_FILE=/opt/advisory-node/data/testnet.db

# Server Configuration
PORT=8080
GIN_MODE=release
CORS_ORIGINS=*
ENVIRONMENT=testnet
```

#### Mainnet SQLite (`mainnet-sqlite.env`)

```bash
# Database Configuration
DB_TYPE=sqlite
DB_FILE=/opt/advisory-node/data/mainnet.db

# Server Configuration
PORT=8081
GIN_MODE=release
CORS_ORIGINS=*
ENVIRONMENT=mainnet
```

### 2. Create Data Directory

```bash
sudo mkdir -p /opt/advisory-node/data
sudo chown www-data:www-data /opt/advisory-node/data
```

## Maintenance Commands

### Service Management

```bash
# Restart services
sudo supervisorctl restart advisory-testnet
sudo supervisorctl restart advisory-mainnet

# Stop services
sudo supervisorctl stop advisory-testnet advisory-mainnet

# View logs
sudo supervisorctl tail -f advisory-testnet
sudo supervisorctl tail -f advisory-mainnet
```

### Database Maintenance

```bash
# Backup databases
pg_dump -h localhost -U advisory_user advisory_testnet > testnet_backup.sql
pg_dump -h localhost -U advisory_user advisory_mainnet > mainnet_backup.sql

# Monitor database size
sudo -u postgres psql -c "SELECT pg_size_pretty(pg_database_size('advisory_testnet'));"
sudo -u postgres psql -c "SELECT pg_size_pretty(pg_database_size('advisory_mainnet'));"
```

### Application Updates

```bash
cd /opt/advisory-node

# Pull latest changes
git pull

# Rebuild
go build -o advisory-node

# Restart services
sudo supervisorctl restart advisory-testnet advisory-mainnet
```

## Security Considerations

1. **Database Security**:
   - Use strong passwords
   - Restrict database access to localhost only
   - Regular security updates

2. **Application Security**:
   - Run services as non-root user (www-data)
   - Configure proper CORS origins for production
   - Use HTTPS in production (SSL certificates)

3. **Network Security**:
   - Configure firewall properly
   - Use VPN for administrative access
   - Monitor access logs

4. **Backup Strategy**:
   - Regular database backups
   - Application configuration backups
   - Disaster recovery plan

## Monitoring

### System Monitoring

```bash
# Check resource usage
htop
df -h
free -m

# Check network connections
netstat -tulpn | grep -E ':(8080|8081|5432)'

# Check service logs
journalctl -u supervisor -f
```

### Application Monitoring

```bash
# Check API health
watch -n 30 'curl -s http://localhost:8080/api/quorum/health | jq'
watch -n 30 'curl -s http://localhost:8081/api/quorum/health | jq'

# Monitor database connections
sudo -u postgres psql -c "SELECT pid, usename, application_name, client_addr FROM pg_stat_activity WHERE datname IN ('advisory_testnet', 'advisory_mainnet');"
```

This comprehensive guide should help you set up a robust testnet and mainnet environment for your Advisory Node Service on your VM with local database management.
