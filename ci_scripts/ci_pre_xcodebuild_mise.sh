#!/bin/sh

# Alternative ci_pre_xcodebuild.sh using Mise for Tuist installation
# This script runs before xcodebuild in Xcode Cloud
# It installs Tuist using Mise and generates the Xcode project

set -e  # Exit on any error

echo "🚀 Starting Tuist setup for Xcode Cloud (using Mise)..."

# Install Mise
echo "📦 Installing Mise..."
curl https://mise.run | sh

# Add mise to PATH
export PATH="$HOME/.local/bin:$PATH"

# Install Tuist via Mise
echo "📦 Installing Tuist via Mise..."
mise install tuist@latest
mise global tuist@latest

# Verify Tuist installation
echo "✅ Tuist version:"
tuist --version

# Navigate to the iOS project directory
cd ios

# Clean any existing generated files
echo "🧹 Cleaning existing generated files..."
tuist clean || echo "Clean command failed, continuing..."

# Generate the Xcode project
echo "⚡ Generating Xcode project with Tuist..."
tuist generate

echo "✅ Tuist project generation completed successfully!"

# List the generated files for debugging
echo "📂 Generated workspace contents:"
ls -la *.xcworkspace/ || true
ls -la *.xcodeproj/ || true

echo "🎉 Pre-build setup completed!"