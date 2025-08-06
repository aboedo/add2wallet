# Add2Wallet

Convert PDF tickets and passes into Apple Wallet passes using AI-powered document processing.

## Project Structure

```
add2wallet/
├── PLAN.md               # Detailed project plan and architecture
├── ios/                  # iOS native app
│   ├── Add2Wallet/      # Main app source
│   └── Add2WalletTests/ # iOS tests
└── backend/             # Python backend service
    ├── app/             # FastAPI application
    └── tests/           # Backend tests
```

## Quick Start

### Prerequisites
- **iOS Development**: Xcode 15.0+, iOS 17.0+ SDK
- **Backend**: Python 3.11+
- **Optional**: Apple Developer Account (for device testing)

### Backend Setup

```bash
# Navigate to backend directory
cd backend

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Run tests
pytest

# Start development server
python run.py
```

The backend will be available at `http://localhost:8000`
API documentation at `http://localhost:8000/docs`

### iOS Setup

1. **Create Xcode Project**:
   - Open Xcode
   - Create new project > iOS > App
   - Product Name: `Add2Wallet`
   - Interface: SwiftUI
   - Language: Swift
   - Replace generated files with ones in `ios/Add2Wallet/`

2. **Run the App**:
   - Select target device/simulator
   - Press Cmd+R to run
   - Press Cmd+U to run tests

## Testing the Integration

1. Start the backend server:
   ```bash
   cd backend && source venv/bin/activate && python run.py
   ```

2. Run the iOS app in simulator
3. The app will connect to `http://localhost:8000`

## Development Workflow

1. **Check Project Status**: Review `PLAN.md` for current phase
2. **Pick a Task**: Find next unchecked item in current phase
3. **Run Tests**: Ensure existing tests pass before changes
4. **Make Changes**: Implement the feature
5. **Test Again**: Verify your changes work
6. **Update Plan**: Check off completed tasks

## Current Status

**Phase 1: Foundation Setup** ✅
- [x] iOS app skeleton created
- [x] Basic Python server with upload endpoint
- [x] Test structure for both components
- [ ] Share extension (next step)

## Next Steps

1. Add iOS Share Extension for PDF import
2. Implement document picker in main app
3. Add OpenAI integration for PDF processing
4. Generate Apple Wallet passes

## Documentation

- [Project Plan](PLAN.md) - Detailed architecture and roadmap
- [iOS README](ios/README.md) - iOS-specific documentation
- [Backend README](backend/README.md) - Backend-specific documentation

## License

This project is private and proprietary.