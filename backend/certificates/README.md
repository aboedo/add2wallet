# Apple Wallet Pass Certificates

This directory contains the certificates needed to sign Apple Wallet passes.

## Required Files

You need these files from Apple Developer Portal:

1. **`pass.cer`** - Pass Type ID Certificate (downloaded from Apple)
2. **`pass.p12`** - Private key file (exported from Keychain)
3. **`wwdr.cer`** - Apple Worldwide Developer Relations Certificate
4. **`pass.pem`** - Pass certificate in PEM format (converted from .cer)
5. **`key.pem`** - Private key in PEM format (converted from .p12)
6. **`wwdr.pem`** - WWDR certificate in PEM format (converted from .cer)

## Setup Instructions

1. Download your Pass Type ID certificate from Apple Developer Portal
2. Export the private key from Keychain as .p12
3. Download the WWDR certificate from Apple
4. Convert certificates to PEM format using the conversion commands
5. Update the pass generator configuration

## Security Note

**NEVER commit these certificate files to version control!**
Add `certificates/*.cer`, `certificates/*.p12`, `certificates/*.pem` to your `.gitignore`.