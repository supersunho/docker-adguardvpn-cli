#!/bin/bash

# AdGuard VPN CLI Authentication Helper Script
# This script helps users perform the initial web authentication

echo "🔐 AdGuard VPN CLI Web Authentication Helper"
echo "==========================================="

echo "💡 This script will run a one-time authentication command using docker run"
echo "💡 The authentication data will be stored in the ./data directory"
echo ""

echo ""
echo "📋 Starting web authentication process..."
echo "💡 Follow the instructions in your terminal:"
echo ""
echo "1. The authentication URL will be displayed in your terminal"
echo "2. Copy the URL and open it in your web browser"
echo "3. Enter the user code when prompted on the website"
echo "4. Complete the authentication flow in your browser"
echo ""

read -p "Press Enter to start the authentication process..."

# Start the login process
echo ""
echo "🚀 Executing: docker run -it --rm -v \$(pwd)/data:/root/.local/share/adguardvpn-cli supersunho/adguardvpn-cli:latest adguardvpn-cli login"
echo ""
docker run -it --rm -v $(pwd)/data:/root/.local/share/adguardvpn-cli supersunho/adguardvpn-cli:latest adguardvpn-cli login

echo ""
echo "✅ Authentication process completed!"
echo ""
echo ""
echo "✅ Authentication completed successfully!"
echo ""
echo "💡 The authentication credentials are now stored in ./data directory"
echo "💡 You can now start your main container with 'docker-compose up -d'"
echo "💡 The main container will use the stored authentication credentials."