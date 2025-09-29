# Advisory Node Service - Restart & Recovery Guide

## 🔐 Credentials & Customization

### What the Setup Script Asks For:

1. **Database Password**: 
   - Prompted during setup for `advisory_user` (or custom username)
   - Stored in `~/advisory-node-deploy/testnet.env` and `~/advisory-node-deploy/mainnet.env`

2. **Domain Name**: 
   - Optional for Nginx reverse proxy setup
   - Can be skipped for IP-based access

3. **Custom Configuration**:
   - Database username (default: `advisory_user`)
   - Port numbers (default: 8080 testnet, 8081 mainnet)
   - Database names (default: `advisory_testnet`, `advisory_mainnet`)

### Customization Example:

```bash
# When running setup-vm.sh, you'll see:
🔧 Configuration Options:
   Database User: advisory_user
   Testnet Port: 8080
   Mainnet Port: 8081
   Testnet DB: advisory_testnet
   Mainnet DB: advisory_mainnet

Enter database password for advisory_user: [your_password]
Enter your VM's domain name (optional): [your-domain.com or skip]

Use custom configuration? (y/n, default: n): y
Database username (default: advisory_user): [custom_user or press enter]
Testnet port (default: 8080): [custom_port or press enter]
Mainnet port (default: 8081): [custom_port or press enter]
```

## 🔄 After VM Reboot - Automatic Restart

### What Happens Automatically:

1. **Supervisor Service**: Starts automatically (enabled during setup)
2. **PostgreSQL**: Starts automatically (system service)
3. **Advisory Node Services**: Auto-started via cron job

### Auto-Start Process:

```bash
# The setup script configures:
1. Supervisor to start on boot: sudo systemctl enable supervisor
2. Cron job for auto-start: @reboot ~/advisory-node-deploy/scripts/auto-start-service.sh
3. Services monitored by supervisor with autorestart=true
```

## 🛠️ Manual Restart Commands

### Check Current Status:

```bash
# Quick status check
~/advisory-node-deploy/manage.sh status

# Detailed supervisor status
sudo supervisorctl status

# Check individual services
curl http://localhost:8080/api/quorum/health  # Testnet
curl http://localhost:8081/api/quorum/health  # Mainnet
```

### Restart Services:

```bash
# Restart both services
~/advisory-node-deploy/manage.sh restart

# Restart individual services
sudo supervisorctl restart advisory-testnet
sudo supervisorctl restart advisory-mainnet

# Start services if stopped
sudo supervisorctl start advisory-testnet advisory-mainnet
```

### Restart System Services:

```bash
# Restart PostgreSQL
sudo systemctl restart postgresql

# Restart Supervisor
sudo systemctl restart supervisor

# Check system service status
sudo systemctl status postgresql
sudo systemctl status supervisor
```

## 🚨 Troubleshooting After Reboot

### Services Not Starting:

```bash
# 1. Check auto-start log
tail -f ~/advisory-node-deploy/logs/auto-start.log

# 2. Check supervisor logs
sudo supervisorctl tail advisory-testnet
sudo supervisorctl tail advisory-mainnet

# 3. Check system logs
journalctl -u supervisor -f
journalctl -u postgresql -f
```

### Database Connection Issues:

```bash
# Test database connectivity
psql -h localhost -U advisory_user advisory_testnet -c "SELECT current_database();"
psql -h localhost -U advisory_user advisory_mainnet -c "SELECT current_database();"

# Check PostgreSQL status
sudo systemctl status postgresql

# Restart PostgreSQL if needed
sudo systemctl restart postgresql
```

### Port Conflicts:

```bash
# Check what's using the ports
lsof -i:8080
lsof -i:8081

# Kill conflicting processes if needed
sudo kill -9 $(lsof -ti:8080)
sudo kill -9 $(lsof -ti:8081)

# Restart services
~/advisory-node-deploy/manage.sh restart
```

### Permission Issues:

```bash
# Fix ownership if needed
sudo chown -R $USER:$USER ~/advisory-node-deploy/

# Fix script permissions
chmod +x ~/advisory-node-deploy/manage.sh
chmod +x ~/advisory-node-deploy/start-*.sh
chmod +x ~/advisory-node-deploy/scripts/*.sh
```

## 🔧 Manual Recovery Steps

### Complete Service Recovery:

```bash
# 1. Stop all services
sudo supervisorctl stop advisory-testnet advisory-mainnet

# 2. Restart system services
sudo systemctl restart postgresql supervisor

# 3. Wait for services to initialize
sleep 10

# 4. Start advisory services
sudo supervisorctl start advisory-testnet advisory-mainnet

# 5. Check status
~/advisory-node-deploy/manage.sh status
```

### Database Recovery:

```bash
# If database issues persist:
# 1. Check PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-*.log

# 2. Restart PostgreSQL
sudo systemctl restart postgresql

# 3. Test database connection
psql -h localhost -U advisory_user advisory_testnet

# 4. If needed, restore from backup
~/advisory-node-deploy/scripts/restore-db.sh testnet
~/advisory-node-deploy/scripts/restore-db.sh mainnet
```

## 📋 Post-Reboot Checklist

### 1. Verify System Services:
```bash
sudo systemctl status postgresql  # Should be active
sudo systemctl status supervisor  # Should be active
sudo systemctl status nginx       # Should be active (if configured)
```

### 2. Verify Advisory Services:
```bash
sudo supervisorctl status          # Both should show RUNNING
~/advisory-node-deploy/manage.sh status
```

### 3. Test API Endpoints:
```bash
curl http://localhost:8080/api/quorum/health
curl http://localhost:8081/api/quorum/health
curl http://your-vm-ip:8080/api/quorum/health
curl http://your-vm-ip:8081/api/quorum/health
```

### 4. Check Logs:
```bash
# Auto-start log
tail ~/advisory-node-deploy/logs/auto-start.log

# Service logs
~/advisory-node-deploy/manage.sh logs testnet
~/advisory-node-deploy/manage.sh logs mainnet
```

## ⚙️ Configuration File Locations

### Environment Files (contain passwords):
- `~/advisory-node-deploy/testnet.env`
- `~/advisory-node-deploy/mainnet.env`

### Log Files:
- `~/advisory-node-deploy/logs/advisory-testnet.out.log`
- `~/advisory-node-deploy/logs/advisory-testnet.err.log`
- `~/advisory-node-deploy/logs/advisory-mainnet.out.log`
- `~/advisory-node-deploy/logs/advisory-mainnet.err.log`
- `~/advisory-node-deploy/logs/auto-start.log`

### Supervisor Configuration:
- `/etc/supervisor/conf.d/advisory-testnet.conf`
- `/etc/supervisor/conf.d/advisory-mainnet.conf`

## 🔄 Updating Configuration

### Change Ports or Database Settings:

```bash
# 1. Edit environment files
nano ~/advisory-node-deploy/testnet.env
nano ~/advisory-node-deploy/mainnet.env

# 2. Update supervisor configs (if ports changed)
sudo nano /etc/supervisor/conf.d/advisory-testnet.conf
sudo nano /etc/supervisor/conf.d/advisory-mainnet.conf

# 3. Reload supervisor and restart services
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl restart advisory-testnet advisory-mainnet
```

### Change Database Password:

```bash
# 1. Update password in PostgreSQL
sudo -u postgres psql -c "ALTER USER advisory_user PASSWORD 'new_password';"

# 2. Update environment files
sed -i 's/DB_PASSWORD=old_password/DB_PASSWORD=new_password/g' ~/advisory-node-deploy/testnet.env
sed -i 's/DB_PASSWORD=old_password/DB_PASSWORD=new_password/g' ~/advisory-node-deploy/mainnet.env

# 3. Restart services
~/advisory-node-deploy/manage.sh restart
```

## 📞 Emergency Commands

### Force Stop Everything:
```bash
sudo supervisorctl stop all
sudo systemctl stop supervisor
sudo systemctl stop postgresql
```

### Force Start Everything:
```bash
sudo systemctl start postgresql
sudo systemctl start supervisor
sudo supervisorctl start advisory-testnet advisory-mainnet
```

### Reset to Clean State:
```bash
# Stop services
~/advisory-node-deploy/manage.sh stop

# Clear logs
rm -f ~/advisory-node-deploy/logs/*.log

# Restart everything
sudo systemctl restart postgresql supervisor
sleep 10
sudo supervisorctl start advisory-testnet advisory-mainnet
```

Your Advisory Node Service is designed to automatically restart after VM reboots, but these commands will help you troubleshoot and manually recover if needed! 🚀
