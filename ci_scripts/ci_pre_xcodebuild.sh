#!/bin/sh

# ci_pre_xcodebuild.sh
# This script runs before xcodebuild in Xcode Cloud
# It installs Tuist and generates the Xcode project

set -e  # Exit on any error

echo "🚀 Starting Tuist setup for Xcode Cloud..."

# Add common Tuist paths to PATH
export PATH="$PATH:$HOME/.tuist/bin:/opt/homebrew/bin:/usr/local/bin"

# Check if Tuist is already installed
if command -v tuist >/dev/null 2>&1; then
    echo "✅ Tuist already installed:"
    tuist version
else
    # Install Tuist using the official installer
    echo "📦 Installing Tuist..."
    curl -Ls https://install.tuist.io | bash
    
    # Add Tuist to PATH for this session
    export PATH="$PATH:$HOME/.tuist/bin"
    
    # Verify Tuist installation, use fallback if needed
    if ! command -v tuist >/dev/null 2>&1; then
        echo "⚠️ Official installer failed, trying fallback method..."
        ./ci_scripts/install_tuist_fallback.sh
    else
        echo "✅ Tuist version:"
        tuist version
    fi
fi

# Navigate to the iOS project directory
cd ios

# Clean any existing generated files
echo "🧹 Cleaning existing generated files..."
tuist clean || echo "⚠️ Clean failed, but continuing..."

# Generate the Xcode project
echo "⚡ Generating Xcode project with Tuist..."
tuist generate

# Verify generation was successful
if [ ! -f "Add2Wallet.xcworkspace/contents.xcworkspacedata" ]; then
    echo "❌ Workspace generation failed!"
    exit 1
fi

if [ ! -f "Add2Wallet.xcodeproj/project.pbxproj" ]; then
    echo "❌ Project generation failed!"
    exit 1
fi

echo "✅ Tuist project generation completed successfully!"

# List the generated files for debugging
echo "📂 Generated workspace contents:"
ls -la *.xcworkspace/ || true
ls -la *.xcodeproj/ || true

echo "🎉 Pre-build setup completed!"