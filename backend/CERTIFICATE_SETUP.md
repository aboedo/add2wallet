# 🔐 Apple Wallet Pass Certificate Setup

## Quick Setup Guide

Since you mentioned you already have the App Store Connect part done, follow these steps:

### 1. Get Your Certificate Files

You need these files from Apple Developer Portal:

1. **Pass Type ID Certificate** (`pass.cer`)
   - Go to [Apple Developer Portal - Pass Type IDs](https://developer.apple.com/account/resources/identifiers/list/passTypeId)
   - Find your Pass Type ID: `pass.com.andresboedo.add2wallet.generic`
   - Click **Download** → save as `pass.cer`

2. **Private Key** (`pass.p12`)
   - Open **Keychain Access** on your Mac
   - Find your Pass Type ID certificate (should be named something like "Pass Type ID: pass.com.andresboedo.add2wallet.generic")
   - Right-click → **Export "Pass Type ID: ..."**
   - Choose **Personal Information Exchange (.p12)**
   - Save as `pass.p12` and set a password (remember it!)

3. **Apple WWDR Certificate** (`wwdr.cer`)
   - Download from: https://developer.apple.com/certificationauthority/AppleWWDRCA.cer
   - Save as `wwdr.cer`

### 2. Run the Setup Script

```bash
# Make sure you're in the backend directory
cd backend

# Place your certificate files in the certificates/ directory:
# - certificates/pass.cer
# - certificates/pass.p12  
# - certificates/wwdr.cer

# Run the setup script
./setup_certificates.sh
```

The script will:
- ✅ Check for required files
- 🔄 Convert certificates to PEM format
- 🧪 Test certificate validity
- ✅ Enable pass signing

### 3. Test Certificate Setup

```bash
# Start the server
source venv/bin/activate
python run.py
```

Look for this message when the server starts:
```
✅ All certificate files found - signing enabled
```

### 4. Test End-to-End

1. **Upload a PDF** from your iOS app
2. **Check the logs** - you should see signing activity
3. **Download the pass** - it will now be properly signed
4. **Install on iPhone** - iOS should accept the signed pass

## Troubleshooting

### "Certificate file not found"
- Make sure files are in `backend/certificates/` directory
- Check file names match exactly: `pass.cer`, `pass.p12`, `wwdr.cer`

### "Error signing manifest"
- Check that your .p12 password is correct (script will prompt)
- Ensure certificates are not expired
- Verify Pass Type ID matches: `pass.com.andresboedo.add2wallet.generic`

### "Pass won't install on iPhone"
- Check that Pass Type ID is registered in App Store Connect
- Verify WWDR certificate is current (Apple updates it periodically)
- Make sure your Apple Developer account is active

## Security Notes

🔒 **Certificate files contain sensitive private keys**
- Never commit `.pem`, `.p12`, or `.cer` files to version control
- Keep certificate files secure and backed up
- Rotate certificates before expiration

## What's Next?

Once certificates are configured:
- ✅ Passes will be properly signed
- ✅ iOS will install them without warnings  
- ✅ Ready for production use

The server automatically detects when certificates are available and enables signing!