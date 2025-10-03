#!/bin/bash

# Script to create/fix the manage.sh script

DEPLOY_DIR="$HOME/advisory-node-deploy"

# Create the management script
cat > $DEPLOY_DIR/manage.sh << 'EOF'
#!/bin/bash

case "$1" in
    status)
        echo "Service Status:"
        sudo supervisorctl status advisory-testnet advisory-mainnet
        echo ""
        echo "Health Checks:"
        echo -n "Testnet (8080): "
        if curl -s --connect-timeout 3 http://localhost:8080/api/quorum/health >/dev/null 2>&1; then
            echo "✅ Running"
        else
            echo "❌ Not responding"
        fi
        
        echo -n "Mainnet (8081): "
        if curl -s --connect-timeout 3 http://localhost:8081/api/quorum/health >/dev/null 2>&1; then
            echo "✅ Running"
        else
            echo "❌ Not responding"
        fi
        
        echo ""
        echo "Network Status:"
        echo "Port 8080: $(lsof -i:8080 -t | wc -l) connections"
        echo "Port 8081: $(lsof -i:8081 -t | wc -l) connections"
        ;;
    restart)
        echo "Restarting services..."
        sudo supervisorctl restart advisory-testnet advisory-mainnet
        sleep 5
        echo "Services restarted. Checking status..."
        $0 status
        ;;
    stop)
        echo "Stopping services..."
        sudo supervisorctl stop advisory-testnet advisory-mainnet
        ;;
    start)
        echo "Starting services..."
        sudo supervisorctl start advisory-testnet advisory-mainnet
        sleep 5
        echo "Services started. Checking status..."
        $0 status
        ;;
    logs)
        if [ "$2" = "testnet" ]; then
            echo "=== Testnet Logs (last 50 lines) ==="
            sudo supervisorctl tail advisory-testnet
        elif [ "$2" = "mainnet" ]; then
            echo "=== Mainnet Logs (last 50 lines) ==="
            sudo supervisorctl tail advisory-mainnet
        else
            echo "Usage: $0 logs [testnet|mainnet]"
            echo ""
            echo "Available options:"
            echo "  $0 logs testnet  - Show testnet logs"
            echo "  $0 logs mainnet  - Show mainnet logs"
        fi
        ;;
    update)
        echo "Updating application..."
        SOURCE_DIR="$HOME/Advisory-Node-Service"
        if [ -d "$SOURCE_DIR" ]; then
            echo "Copying updated files from $SOURCE_DIR..."
            cd "$SOURCE_DIR"
            git pull 2>/dev/null || echo "Git pull failed or not a git repository"
            cp -r * $HOME/advisory-node-deploy/
            cd $HOME/advisory-node-deploy
            echo "Rebuilding application..."
            if [ -f "main.go" ]; then
                go build -o advisory-node main.go
            elif [ -f "main_db.go" ]; then
                go build -o advisory-node main_db.go
            else
                echo "Error: No main Go file found"
                exit 1
            fi
            sudo supervisorctl restart advisory-testnet advisory-mainnet
            echo "Update complete!"
            $0 status
        else
            echo "Error: Source directory not found: $SOURCE_DIR"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 {status|start|stop|restart|logs|update}"
        echo ""
        echo "Commands:"
        echo "  status           - Show service status and health"
        echo "  start            - Start both services"
        echo "  stop             - Stop both services"
        echo "  restart          - Restart both services"
        echo "  logs [env]       - Show logs (specify testnet or mainnet)"
        echo "  update           - Update and restart services"
        echo ""
        echo "Examples:"
        echo "  $0 status"
        echo "  $0 logs testnet"
        echo "  $0 restart"
        ;;
esac
EOF

chmod +x $DEPLOY_DIR/manage.sh

echo "✅ Created/updated manage.sh script at $DEPLOY_DIR/manage.sh"
echo ""
echo "Test the script with:"
echo "  $DEPLOY_DIR/manage.sh status"
