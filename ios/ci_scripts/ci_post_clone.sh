#!/bin/sh

# ci_post_clone.sh
# This script runs immediately after cloning the repository in Xcode Cloud
# It's useful for early setup tasks

set -e  # Exit on any error

echo "🔧 Running post-clone setup..."

# Set up any environment variables or early configuration here
echo "📝 Repository cloned successfully"

# Verify we're in the right directory structure
if [ -d "ios" ]; then
    echo "✅ iOS directory found"
else
    echo "❌ iOS directory not found - check repository structure"
    exit 1
fi

# Check for Tuist project files
if [ -f "ios/Project.swift" ]; then
    echo "✅ Tuist Project.swift found"
else
    echo "❌ Tuist Project.swift not found"
    exit 1
fi

echo "✅ Post-clone setup completed!"