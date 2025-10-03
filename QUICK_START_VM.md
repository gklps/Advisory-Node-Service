# Quick Start: VM Deployment

## TL;DR - One Command Setup

```bash
# Run this from your Advisory-Node-Service/scripts directory
cd /home/rubix/Advisory-Node-Service/scripts
./setup-vm.sh
```

## What You Get

✅ **Testnet Environment**: `http://your-vm-ip:8080`  
✅ **Mainnet Environment**: `http://your-vm-ip:8081`  
✅ **PostgreSQL databases**: `advisory_testnet` & `advisory_mainnet`  
✅ **Auto-restart services**: Supervisor process management  
✅ **Backup tools**: Automated database backup/restore  

## Prerequisites

- Ubuntu 20.04+ VM with sudo access
- 2GB+ RAM, 20GB+ storage
- Internet connection

## Step-by-Step Setup

### 1. Prepare Your VM

```bash
# Update system (if needed)
sudo apt update && sudo apt upgrade -y

# Navigate to your project directory
cd /home/rubix/Advisory-Node-Service/scripts
```

### 2. Run Setup Script

```bash
# Make script executable
chmod +x setup-vm.sh

# Run setup (will prompt for database password)
./setup-vm.sh
```

The script will:
- Install PostgreSQL, Go, Supervisor, Nginx
- Create testnet and mainnet databases **with proper permissions**
- Build and configure the Advisory Node service
- Set up process management with auto-restart
- Configure firewall and auto-start on reboot
- **Test all services with health checks**
- Provide comprehensive troubleshooting info

### 3. Verify Installation

```bash
# Check service status
~/advisory-node-deploy/manage.sh status

# Test endpoints
curl http://localhost:8080/api/quorum/health  # Testnet
curl http://localhost:8081/api/quorum/health  # Mainnet
```

## Management Commands

```bash
cd ~/advisory-node-deploy

# Service management
./manage.sh status    # Check status
./manage.sh restart   # Restart both services
./manage.sh logs testnet    # View testnet logs
./manage.sh logs mainnet    # View mainnet logs

# Database backups
./scripts/backup-db.sh

# Database restore
./scripts/restore-db.sh testnet    # Restore latest testnet backup
./scripts/restore-db.sh mainnet backup_20231201_120000  # Restore specific backup
```

## Configuration Files

- **Testnet**: `~/advisory-node-deploy/testnet.env`
- **Mainnet**: `~/advisory-node-deploy/mainnet.env`
- **Supervisor**: `/etc/supervisor/conf.d/advisory-*.conf`

## Directory Structure

```
~/advisory-node-deploy/          # Deployment directory
├── advisory-node               # Binary
├── testnet.env                # Testnet config
├── mainnet.env                # Mainnet config
├── start-testnet.sh           # Testnet startup script
├── start-mainnet.sh           # Mainnet startup script
├── manage.sh                  # Management script
├── backups/                   # Database backups
├── logs/                      # Service logs
└── scripts/                   # Utility scripts

/home/rubix/Advisory-Node-Service/  # Source code directory
├── main.go                    # Application source
├── scripts/                   # Setup scripts
│   ├── setup-vm.sh           # Main setup script
│   ├── backup-db.sh          # Backup script
│   └── restore-db.sh         # Restore script
└── ...                       # Other source files
```

## Service URLs

| Environment | URL | Database |
|-------------|-----|----------|
| Testnet | `http://your-vm-ip:8080` | `advisory_testnet` |
| Mainnet | `http://your-vm-ip:8081` | `advisory_mainnet` |

## Testing Your Setup

### Register a Test Quorum

```bash
# Testnet
curl -X POST http://your-vm-ip:8080/api/quorum/register \
  -H "Content-Type: application/json" \
  -d '{
    "did": "bafybmi123test456789012345678901234567890123456789012345",
    "peer_id": "12D3KooWTestPeer",
    "balance": 100.0,
    "did_type": 4
  }'

# Get available quorums for 50 RBT transaction
curl "http://your-vm-ip:8080/api/quorum/available?count=5&transaction_amount=50"
```

### Check Transaction History

```bash
curl "http://your-vm-ip:8080/api/quorum/transactions?limit=10"
```

## Troubleshooting

### Services Not Starting

```bash
# The updated script includes automatic diagnostics!
# Check comprehensive status
~/advisory-node-deploy/manage.sh status

# View detailed logs
sudo supervisorctl tail advisory-testnet
sudo supervisorctl tail advisory-mainnet

# Check database connection
PGPASSWORD="your_password" psql -h localhost -U advisory_user advisory_testnet -c "SELECT current_database();"
```

### Database Permission Issues (Now Fixed Automatically)

The updated setup script automatically handles database permissions, but if you encounter issues:

```bash
# Run the permission fix script
cd ~/Advisory-Node-Service/scripts
./fix-database-permissions.sh

# Or manually fix permissions
sudo -u postgres psql -c "ALTER DATABASE advisory_testnet OWNER TO advisory_user;"
sudo -u postgres psql -c "ALTER DATABASE advisory_mainnet OWNER TO advisory_user;"
```

### Port Already in Use

```bash
# Check what's using the ports
lsof -i:8080
lsof -i:8081

# Kill conflicting processes if needed
sudo kill -9 $(lsof -ti:8080)
sudo kill -9 $(lsof -ti:8081)
```

### Complete Service Restart

```bash
# Full service restart
sudo systemctl restart postgresql supervisor
sleep 10
sudo supervisorctl restart advisory-testnet advisory-mainnet
```

## Production Considerations

### SSL/HTTPS Setup

```bash
# Install Certbot for Let's Encrypt
sudo apt install certbot python3-certbot-nginx

# Get SSL certificate (replace with your domain)
sudo certbot --nginx -d testnet-advisory.yourdomain.com
sudo certbot --nginx -d mainnet-advisory.yourdomain.com
```

### Monitoring Setup

```bash
# Install monitoring tools
sudo apt install prometheus node-exporter grafana

# Add to crontab for automated backups
echo "0 2 * * * /opt/advisory-node/scripts/backup-db.sh" | crontab -
```

### Security Hardening

```bash
# Configure fail2ban
sudo apt install fail2ban

# Update PostgreSQL configuration for production
sudo nano /etc/postgresql/*/main/postgresql.conf
# Set: listen_addresses = 'localhost'

# Configure log rotation
sudo nano /etc/logrotate.d/advisory-node
```

## Environment Variables Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `DB_TYPE` | Database type | `postgres` |
| `DB_HOST` | Database host | `localhost` |
| `DB_PORT` | Database port | `5432` |
| `DB_NAME` | Database name | `advisory_testnet/mainnet` |
| `DB_USER` | Database user | `advisory_user` |
| `DB_PASSWORD` | Database password | (prompted) |
| `PORT` | Service port | `8080/8081` |
| `GIN_MODE` | Gin framework mode | `release` |
| `CORS_ORIGINS` | CORS allowed origins | `*` |

## Need Help?

1. **Check logs**: `./manage.sh logs [testnet|mainnet]`
2. **Service status**: `./manage.sh status`
3. **Database connection**: Test with `psql` commands
4. **Firewall**: Ensure ports 8080, 8081 are open
5. **Resources**: Check with `htop`, `df -h`, `free -m`

Your Advisory Node Service is now ready for testnet and mainnet environments! 🚀
