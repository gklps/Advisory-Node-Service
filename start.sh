#!/bin/bash

# Start Advisory Node Service on port 8082
# Default configuration for RubixGo integration

echo "========================================="
echo "Starting Advisory Node Service"
echo "========================================="
echo ""

# Check if already running on 8080
if lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null ; then
    echo "⚠️  Port 8080 is already in use!"
    echo "Run 'lsof -i:8080' to check what's using it"
    echo ""
    read -p "Kill existing process and start fresh? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
        lsof -ti:8080 | xargs kill -9 2>/dev/null
        echo "✅ Killed existing process on port 8080"
    else
        echo "Exiting..."
        exit 1
    fi
fi

# Start the advisory node
echo "Starting Advisory Node on port 8080..."
echo "Database: PostgreSQL"
echo ""

# Load environment variables if file exists
if [ -f "Advisory-Node-Service.env" ]; then
    echo "Loading environment from Advisory-Node-Service.env..."
    export $(cat Advisory-Node-Service.env | xargs)
fi

./advisory-node

# Note: Remove the & at the end if you want to run in foreground
# ./advisory-node-db &  # Add & to run in background