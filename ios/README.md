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
- ✅ Unit tests for core functionality
- ⏳ Document picker (coming next)
- ⏳ Share extension (coming next)

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

## Next Steps
1. Add Share Extension target for PDF import from other apps
2. Implement document picker for in-app PDF selection
3. Add PassKit integration for Apple Wallet
4. Implement proper authentication flow