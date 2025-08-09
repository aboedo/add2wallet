#!/bin/sh

# Fallback Tuist installation script
# This script tries multiple methods to install Tuist

set -e

echo "🔄 Attempting fallback Tuist installation..."

# Method 1: Try official installer
install_official() {
    echo "📦 Trying official Tuist installer..."
    curl -Ls https://install.tuist.io | bash
    export PATH="$PATH:$HOME/.tuist/bin"
    if command -v tuist >/dev/null 2>&1; then
        echo "✅ Official installer succeeded"
        return 0
    fi
    return 1
}

# Method 2: Try Homebrew (if available)
install_homebrew() {
    echo "🍺 Trying Homebrew installation..."
    if command -v brew >/dev/null 2>&1; then
        brew install tuist
        if command -v tuist >/dev/null 2>&1; then
            echo "✅ Homebrew installation succeeded"
            return 0
        fi
    fi
    return 1
}

# Method 3: Try direct binary download
install_binary() {
    echo "📥 Trying direct binary download..."
    mkdir -p "$HOME/.tuist/bin"
    
    # Get the latest release info from GitHub API
    LATEST_RELEASE=$(curl -s https://api.github.com/repos/tuist/tuist/releases/latest | grep '"tag_name":' | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')
    
    if [ -n "$LATEST_RELEASE" ]; then
        echo "📋 Latest version: $LATEST_RELEASE"
        DOWNLOAD_URL="https://github.com/tuist/tuist/releases/download/$LATEST_RELEASE/tuist.zip"
        
        # Download and extract
        curl -L "$DOWNLOAD_URL" -o /tmp/tuist.zip
        unzip -o /tmp/tuist.zip -d /tmp/tuist
        cp /tmp/tuist/tuist "$HOME/.tuist/bin/"
        chmod +x "$HOME/.tuist/bin/tuist"
        
        export PATH="$PATH:$HOME/.tuist/bin"
        
        if command -v tuist >/dev/null 2>&1; then
            echo "✅ Binary download succeeded"
            return 0
        fi
    fi
    return 1
}

# Try each method in order
install_official || install_homebrew || install_binary || {
    echo "❌ All installation methods failed"
    exit 1
}

echo "🎉 Tuist installation completed!"
tuist --version