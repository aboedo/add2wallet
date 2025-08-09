# Add2Wallet iOS App

## Overview
Native iOS application for converting PDF tickets and passes into Apple Wallet passes.

## Bundle Identifier
`com.andresboedo.add2wallet`

## Requirements
- Xcode 15.0+
- iOS 17.0+
- Swift 5.9+

## Opening the Project

The project is ready to open in Xcode:

```bash
cd ios
open Add2Wallet.xcodeproj
```

## Project Structure
```
Add2Wallet.xcodeproj/       # Xcode project file
Add2Wallet/
├── Add2WalletApp.swift     # App entry point
├── Views/
│   └── ContentView.swift   # Main UI
├── ViewModels/
│   └── ContentViewModel.swift # Business logic
├── Services/
│   └── NetworkService.swift   # API communication
├── Assets.xcassets/        # App icons and colors
├── Info.plist              # App configuration
└── Preview Content/        # SwiftUI previews

Add2WalletTests/
├── NetworkServiceTests.swift
└── ContentViewModelTests.swift
```

## Building and Running

1. Open `Add2Wallet.xcodeproj` in Xcode
2. Select your target device or simulator
3. Press `Cmd+R` to build and run
4. Press `Cmd+U` to run tests

## Features

- ✅ Basic UI with SwiftUI
- ✅ Network service for API communication
- ✅ Multipart form upload for PDFs
- ✅ Error handling and loading states
- ✅ Share Extension for PDF import from other apps
- ✅ App Groups for data sharing between app and extension
- ✅ URL scheme handling for extension communication
- ✅ Comprehensive unit tests for core functionality
- ⏳ Document picker (coming next)

## Configuration

The app is configured to:
- Connect to `http://localhost:8000` for development
- Use bundle ID `com.andresboedo.add2wallet`
- Allow local networking for development server

## Testing with Backend

1. Start the backend server:
   ```bash
   cd ../backend
   source venv/bin/activate
   python run.py
   ```

2. Run the iOS app in simulator
3. The app will connect to the local backend

## Using the Share Extension

The app includes a Share Extension that allows users to import PDFs from other apps:

1. Open any PDF in Safari, Files app, Mail, or another app
2. Tap the Share button (square with arrow pointing up)
3. Find and tap "Add to Wallet" in the share sheet
4. The PDF will be automatically processed and sent to the backend

### How it works:
- The Share Extension captures the PDF from the sharing app
- Saves it temporarily in a shared App Group container
- Opens the main app via URL scheme
- Main app processes the PDF and uploads it to the backend
- Shared file is cleaned up after processing

### App Group Configuration:
Both the main app and extension use App Group `group.com.andresboedo.add2wallet` for data sharing.

## Xcode Cloud CI/CD

This project is configured for Xcode Cloud with Tuist support:

- **Build Scripts**: Located in `ci_scripts/` directory
- **Automatic Project Generation**: Tuist generates the Xcode project during CI
- **Test Plan**: `Add2Wallet.xctestplan` for automated testing
- **Documentation**: See `ci_scripts/README.md` for detailed setup instructions

### Quick Xcode Cloud Setup:
1. Enable Xcode Cloud in Apple Developer account
2. Connect to your repository
3. Select `Add2Wallet` scheme and iOS platform
4. The build scripts will automatically handle Tuist installation and project generation

## Next Steps
1. Implement document picker for in-app PDF selection
2. Add PassKit integration for Apple Wallet
3. Implement proper authentication flow
4. Add progress tracking for pass generation