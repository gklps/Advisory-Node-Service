#!/bin/bash

# Debug script to help troubleshoot setup issues

echo "========================================="
echo "Advisory Node Setup Debug Information"
echo "========================================="
echo ""

# Current location info
echo "🔍 Current Directory Info:"
echo "   Current working directory: $(pwd)"
echo "   Script location: $(dirname "${BASH_SOURCE[0]}")"
echo "   Script absolute path: $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo ""

# Look for main.go files
echo "🔍 Looking for main.go files:"
find ~ -name "main.go" -path "*/Advisory-Node-Service/*" 2>/dev/null | head -5
find ~ -name "main_db.go" -path "*/Advisory-Node-Service/*" 2>/dev/null | head -5
echo ""

# Check current directory structure
echo "🔍 Current Directory Structure:"
ls -la "$(pwd)"
echo ""

# Check if we're in the right place
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🔍 Calculated Paths:"
echo "   Script directory: $SCRIPT_DIR"
echo "   Project directory: $PROJECT_DIR"
echo ""

echo "🔍 Project Directory Contents:"
if [ -d "$PROJECT_DIR" ]; then
    ls -la "$PROJECT_DIR"
else
    echo "   ❌ Project directory does not exist: $PROJECT_DIR"
fi
echo ""

# Check for Go files specifically
echo "🔍 Go Files in Project Directory:"
if [ -d "$PROJECT_DIR" ]; then
    find "$PROJECT_DIR" -name "*.go" | head -10
else
    echo "   ❌ Cannot check - project directory not found"
fi
echo ""

# Check for go.mod
echo "🔍 Go Module File:"
if [ -f "$PROJECT_DIR/go.mod" ]; then
    echo "   ✅ go.mod found: $PROJECT_DIR/go.mod"
    echo "   Content preview:"
    head -5 "$PROJECT_DIR/go.mod" | sed 's/^/      /'
else
    echo "   ❌ go.mod not found in: $PROJECT_DIR"
    echo "   Looking for go.mod files nearby:"
    find "$(dirname "$PROJECT_DIR")" -name "go.mod" 2>/dev/null | head -3
fi
echo ""

# System info
echo "🔍 System Information:"
echo "   User: $(whoami)"
echo "   Home: $HOME"
echo "   Go version: $(go version 2>/dev/null || echo 'Go not found')"
echo "   PostgreSQL status: $(systemctl is-active postgresql 2>/dev/null || echo 'Not available')"
echo ""

# Recommendations
echo "🔧 Recommendations:"
echo ""

if [ ! -f "$PROJECT_DIR/main.go" ] && [ ! -f "$PROJECT_DIR/main_db.go" ]; then
    echo "❌ Issue: No main Go file found"
    echo "   Solutions:"
    echo "   1. Ensure you're running from: /home/rubix/Advisory-Node-Service/scripts/"
    echo "   2. Check if your project structure is:"
    echo "      /home/rubix/Advisory-Node-Service/"
    echo "      ├── main.go (or main_db.go)"
    echo "      ├── go.mod"
    echo "      └── scripts/"
    echo "          └── setup-vm.sh"
    echo ""
fi

if [ ! -f "$PROJECT_DIR/go.mod" ]; then
    echo "❌ Issue: No go.mod file found"
    echo "   Solutions:"
    echo "   1. Initialize Go module: cd $PROJECT_DIR && go mod init advisory-node"
    echo "   2. Or copy from correct location if it exists elsewhere"
    echo ""
fi

echo "✅ Next steps:"
echo "   1. Fix any issues above"
echo "   2. Run: cd ~/Advisory-Node-Service/scripts"
echo "   3. Run: ./setup-vm.sh"
echo ""
echo "========================================="
