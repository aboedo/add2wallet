#!/bin/bash

# Apple Wallet Pass Certificate Setup Script
# This script helps convert Apple certificates to the format needed for pass signing

set -e

CERT_DIR="certificates"
cd "$(dirname "$0")"

echo "🔐 Apple Wallet Pass Certificate Setup"
echo "======================================"
echo

# Check if certificates directory exists
if [ ! -d "$CERT_DIR" ]; then
    echo "❌ Certificates directory not found. Creating..."
    mkdir -p "$CERT_DIR"
fi

cd "$CERT_DIR"

echo "📋 Required files checklist:"
echo "   1. pass.cer      (Pass Type ID Certificate from Apple)"
echo "   2. pass.p12      (Private key exported from Keychain)"
echo "   3. wwdr.cer      (Apple WWDR Certificate)"
echo

# Check for required input files
MISSING_FILES=()

if [ ! -f "pass.cer" ]; then
    MISSING_FILES+=("pass.cer")
fi

if [ ! -f "pass.p12" ]; then
    MISSING_FILES+=("pass.p12")
fi

if [ ! -f "wwdr.cer" ]; then
    MISSING_FILES+=("wwdr.cer")
fi

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    echo "❌ Missing required files:"
    for file in "${MISSING_FILES[@]}"; do
        echo "   - $file"
    done
    echo
    echo "📥 Please follow these steps to get the required files:"
    echo
    echo "1. Download Pass Type ID Certificate:"
    echo "   - Go to https://developer.apple.com/account/resources/identifiers/list/passTypeId"
    echo "   - Find your Pass Type ID (pass.com.andresboedo.add2wallet.generic)"
    echo "   - Click 'Download' and save as 'pass.cer'"
    echo
    echo "2. Export Private Key:"
    echo "   - Open Keychain Access"
    echo "   - Find your Pass Type ID certificate"
    echo "   - Right-click → Export"
    echo "   - Save as 'pass.p12' (choose a password)"
    echo
    echo "3. Download WWDR Certificate:"
    echo "   - Go to https://developer.apple.com/certificationauthority/AppleWWDRCA.cer"
    echo "   - Save as 'wwdr.cer'"
    echo
    echo "Once you have all files, run this script again."
    exit 1
fi

echo "✅ All required files found!"
echo

# Convert certificates to PEM format
echo "🔄 Converting certificates to PEM format..."

# Convert pass certificate
if [ ! -f "pass.pem" ] || [ "pass.cer" -nt "pass.pem" ]; then
    echo "   Converting pass.cer → pass.pem"
    openssl x509 -inform DER -outform PEM -in pass.cer -out pass.pem
    echo "   ✅ pass.pem created"
fi

# Convert private key (will prompt for password)
if [ ! -f "key.pem" ] || [ "pass.p12" -nt "key.pem" ]; then
    echo "   Converting pass.p12 → key.pem"
    echo "   (You will be prompted for your .p12 password)"
    openssl pkcs12 -in pass.p12 -out key.pem -nodes -clcerts
    echo "   ✅ key.pem created"
fi

# Convert WWDR certificate
if [ ! -f "wwdr.pem" ] || [ "wwdr.cer" -nt "wwdr.pem" ]; then
    echo "   Converting wwdr.cer → wwdr.pem"
    openssl x509 -inform DER -outform PEM -in wwdr.cer -out wwdr.pem
    echo "   ✅ wwdr.pem created"
fi

echo
echo "🎉 Certificate setup complete!"
echo
echo "📁 Generated files:"
echo "   - pass.pem    (Pass certificate)"
echo "   - key.pem     (Private key)"
echo "   - wwdr.pem    (Apple WWDR certificate)"
echo
echo "🔒 Security reminder:"
echo "   These files contain sensitive keys. Keep them secure!"
echo "   They are already excluded from version control."
echo
echo "✅ Your server is now ready to sign Apple Wallet passes!"

# Test certificate files
echo
echo "🧪 Testing certificate files..."

# Check if certificates are valid
openssl x509 -in pass.pem -text -noout > /dev/null 2>&1 && echo "   ✅ pass.pem is valid" || echo "   ❌ pass.pem is invalid"
openssl rsa -in key.pem -check -noout > /dev/null 2>&1 && echo "   ✅ key.pem is valid" || echo "   ❌ key.pem is invalid"  
openssl x509 -in wwdr.pem -text -noout > /dev/null 2>&1 && echo "   ✅ wwdr.pem is valid" || echo "   ❌ wwdr.pem is invalid"

echo
echo "🚀 Ready to generate signed Apple Wallet passes!"