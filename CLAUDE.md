# Add2Wallet - Project Documentation for Claude

This document provides comprehensive information about the Add2Wallet project for AI assistants to understand the codebase, testing procedures, and development workflows.

## Project Overview

Add2Wallet is a two-component system that converts PDF tickets and passes into Apple Wallet passes using AI-powered document processing. The system consists of:

1. **iOS Native App** - SwiftUI app with share extension for PDF import
2. **Python Backend Service** - FastAPI server with PDF processing and pass generation

## Architecture

```
iOS App (SwiftUI) ←→ Python Backend (FastAPI)
     ↓                        ↓
Share Extension         OpenAI + PassKit
     ↓                        ↓
Apple Wallet           Certificate Signing
```

## Backend Application (`/backend/`)

### Core Functionality

The backend is a **FastAPI** application that processes PDFs and generates Apple Wallet passes.

**Main Components:**

- **FastAPI App** (`app/main.py`) - Main server with REST endpoints
- **Barcode Extractor** (`app/services/barcode_extractor.py`) - Extracts barcodes/QR codes from PDFs using computer vision
- **AI Service** (`app/services/ai_service.py`) - OpenAI integration for PDF content analysis  
- **Pass Generator** (`app/services/pass_generator.py`) - Creates signed Apple Wallet passes
- **PDF Validator** (`app/services/pdf_validator.py`) - Validates uploaded PDF files

### Key Endpoints

- `POST /upload` - Upload PDF for processing (returns job_id)
- `GET /status/{job_id}` - Check processing status
- `GET /pass/{job_id}` - Download generated .pkpass file
- `GET /tickets/{job_id}` - List all tickets for multi-ticket PDFs
- `GET /health` - Health check for all services

### Processing Pipeline

1. **PDF Upload & Validation** - File size limits, PDF structure validation
2. **Barcode Detection** - Multi-method approach using PyMuPDF, pdf2image, OpenCV, pyzbar
3. **AI Analysis** - OpenAI GPT extracts event metadata (title, date, venue, etc.)
4. **Pass Generation** - Creates Apple Wallet passes with extracted data and barcodes
5. **Certificate Signing** - Signs passes with Apple Developer certificates

### Key Features

- **Multi-format Barcode Support**: Aztec, QR Code, Data Matrix, Code128, PDF417
- **Smart Format Detection**: Prioritizes Aztec codes for tickets, QR for general use
- **Enhanced Image Processing**: Multiple DPI levels, contrast enhancement, deskewing
- **AI-Powered Enrichment**: Extracts venue info, dates, seat details using OpenAI
- **Multi-ticket Support**: Handles PDFs with multiple barcodes/tickets

## iOS Application (`/ios/`)

### Architecture

The iOS app uses **SwiftUI** with **SwiftData** for persistence and is built using **Tuist** for project generation.

**Main Components:**

- **Add2WalletApp.swift** - Main app entry point, URL handling, file processing
- **ContentView.swift** - Main UI with PDF selection, processing status, pass details
- **NetworkService.swift** - HTTP client for backend communication
- **SavedPassesView.swift** - History of generated passes
- **Share Extension** - Processes PDFs shared from other apps

### Key Features

- **Document Picker**: Select PDFs from Files app
- **Share Extension**: Process PDFs shared from Safari, Mail, etc.
- **Universal Links**: Handle links.add2wallet.app URLs  
- **PassKit Integration**: Add passes directly to Apple Wallet
- **Pass History**: SwiftData persistence of generated passes
- **Map Integration**: Show venue locations with Apple/Google Maps links

### URL Handling

The app handles multiple URL schemes:
- `add2wallet://share/token` - Custom URL scheme
- `links.add2wallet.app/share/token` - Universal Links
- File URLs from "Open in Add2Wallet"

## Testing

### Backend Testing

**Framework**: pytest  
**Test Files**: `backend/tests/`  
**Commands**:

```bash
# Setup
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Run all tests
pytest

# Run specific test file
pytest tests/test_main.py

# Run with verbose output
pytest -v

# Run tests with API key set
API_KEY=development-api-key pytest tests/test_main.py::test_upload_data_matrix_pdf_integration -v
```

**Key Test Files**:
- `test_main.py` - API endpoint tests
- `test_barcode_extractor.py` - Barcode detection tests  
- `test_aztec_integration.py` - Aztec code processing tests
- `test_pdf_validator.py` - PDF validation tests

### iOS Testing

**Framework**: XCTest  
**Test Files**: `ios/Add2WalletTests/`  

#### Quick Setup & Run Commands

```bash
# Setup (requires Tuist)
cd ios
tuist generate

# Run all tests from command line
xcodebuild test -scheme Add2Wallet -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2'

# Run tests from Xcode
# Product > Test (⌘+U)

# Build only (faster for compilation checks)
xcodebuild build -scheme Add2Wallet -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2'

# Run specific test class
xcodebuild test -scheme Add2Wallet -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2' -only-testing:Add2WalletTests.NetworkServiceTests

# Run specific test method
xcodebuild test -scheme Add2Wallet -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.2' -only-testing:Add2WalletTests.NetworkServiceTests/testMockUploadPDFSuccess
```

#### Test Architecture

**Unit Tests**:
- `NetworkServiceTests.swift` - Comprehensive API communication tests with mock service
- `PassUsageManagerTests.swift` - RevenueCat integration and pass balance management
- `ContentViewModelTests.swift` - Core app state management and PDF processing logic
- `DateTimeFormatterTests.swift` - Date/time parsing and formatting utilities
- `PassColorUtilsTests.swift` - Color extraction, parsing, and pass theming
- `SavedPassTests.swift` - SwiftData model validation and persistence
- `ShareExtensionTests.swift` - Share extension integration and notification handling

**Integration Tests**:
- `PDFProcessingIntegrationTests.swift` - End-to-end PDF → pass generation workflow
- `SwiftDataIntegrationTests.swift` - Database operations and iCloud sync scenarios
- `RevenueCatIntegrationTests.swift` - Purchase flows and customer management

**Mock Services**:
- `MockNetworkService.swift` - Configurable network responses with delay simulation
- `MockRevenueCat.swift` - RevenueCat purchase and balance management mocking
- `TestHelpers.swift` - Test utilities, SwiftData containers, and data factories

**Test Resources**:
- `Add2WalletTests/Resources/` - Demo PDF files and mock JSON responses
- Automatic bundle inclusion in test target for realistic file processing tests

#### Testing Best Practices

**For Unit Tests**:
```swift
@MainActor  // Required for UI-related tests due to SwiftUI actor isolation
class YourTests: XCTestCase {
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables = nil
        super.tearDown()
    }
}
```

**For Async Tests**:
```swift
func testAsyncOperation() async {
    let expectation = XCTestExpectation(description: "Async operation")
    
    // Perform async work...
    
    await fulfillment(of: [expectation], timeout: 5.0)
}
```

**Using Mock Services**:
```swift
let mockService = MockNetworkService()
mockService.setSuccessResponse(expectedResponse)
// or
mockService.setErrorResponse(NetworkError.serverError("Test error", statusCode: 500))
```

**Using Test Helpers**:
```swift
let testPDF = TestHelpers.loadTestPDF(named: "torre_ifel")
let testMetadata = TestHelpers.createTestEnhancedPassMetadata()
let testContext = createTestModelContext()
```

#### Debugging Test Failures

**Common Issues**:
1. **MainActor Isolation**: Add `@MainActor` to test classes that interact with UI components
2. **Async Timing**: Use `await fulfillment(of:timeout:)` for proper async test handling
3. **Mock Configuration**: Ensure mock services are configured before test execution
4. **Resource Loading**: Verify test resources are included in the test bundle

**Test Output Interpretation**:
- Tests may fail initially when testing against real network endpoints
- Mock tests should pass consistently and quickly
- Integration tests validate end-to-end workflows
- Focus on achieving >80% code coverage on business logic classes

### Manual Testing Guidelines

**Note**: Claude Code doesn't need to run the iOS app directly for testing. Manual testing will be done by the user after code changes are complete. Claude should focus on:
- Ensuring compilation works correctly after each change
- Verifying code syntax and structure  
- Running automated tests to validate logic
- Following established patterns in the codebase
- Using mock services for predictable test scenarios

### Continuous Integration

The test suite is designed to:
- ✅ Compile cleanly on each change
- ✅ Run quickly with mock services (< 30 seconds)
- ✅ Provide comprehensive coverage of business logic
- ✅ Validate integration points without external dependencies
- ✅ Support both Xcode and command-line execution

### Code Organization Benefits

With the new testing infrastructure:
- **URLHandler**: Centralized URL processing with testable methods
- **NotificationManager**: Type-safe notification handling with helper methods
- **Mock Services**: Predictable testing environment with configurable responses
- **Test Helpers**: Reusable utilities for common test scenarios
- **Resource Management**: Proper test bundle configuration for realistic testing

## Development Setup

### Backend Development

```bash
cd backend
python3 -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt

# Set environment variables
export OPENAI_API_KEY="your-key-here"
export API_KEY="development-api-key"

# Run development server
python3 run.py
# Server available at: http://localhost:8000
# API docs at: http://localhost:8000/docs
```

### iOS Development

```bash
# Prerequisites: Xcode 15+, Tuist
brew install tuist

cd ios
tuist generate
open Add2Wallet.xcworkspace

# Run app: ⌘+R
# Run tests: ⌘+U
```

### Full Integration Testing

1. Start backend server: `cd backend && python3 run.py`
2. Run iOS app in simulator
3. Test PDF processing end-to-end

## Common Development Tasks

### Adding New Barcode Format Support

1. Update `supported_formats` in `barcode_extractor.py:41`
2. Add format mapping in `_normalize_barcode_format()` method
3. Update format groups for detection priority
4. Test with sample PDFs containing the new format

### Modifying AI Prompts

1. Edit prompts in `ai_service.py`
2. Update response parsing logic
3. Test with various PDF types
4. Update tests to verify new extraction fields

### Adding New Pass Fields

1. Update `EnhancedPassMetadata` in iOS `NetworkService.swift:4`
2. Modify pass templates in `pass_generator.py`
3. Update UI to display new fields
4. Add backend response fields

### Configuring App Store Backlinks

Add2Wallet passes can include backlinks to the iOS app using Apple's `associatedStoreIdentifiers` field:

1. **Set APP_STORE_ID environment variable** with your iTunes Store item identifier
2. **Get the ID from App Store Connect** after app publication
3. **Passes will show "Related Apps" section** in Apple Wallet
4. **Users can tap to download/open** the Add2Wallet app

**Example:**
```bash
export APP_STORE_ID=1234567890
```

The feature is implemented in `pass_generator.py:866` and automatically adds the identifier to all generated passes when configured.

## Key Files Reference

### Backend
- `app/main.py:141` - Main upload endpoint
- `app/services/barcode_extractor.py:55` - Barcode extraction entry point
- `app/services/ai_service.py:22` - AI analysis service
- `app/services/pass_generator.py:25` - Apple Wallet pass generation
- `requirements.txt:1` - Python dependencies

### iOS
- `Add2WalletApp.swift:32` - URL handling logic
- `Views/ContentView.swift:25` - Main UI
- `Services/NetworkService.swift:139` - Backend communication
- `Models/SavedPass.swift` - SwiftData persistence model

## Environment Variables

### Backend
- `OPENAI_API_KEY` - OpenAI API access (required for AI features)
- `API_KEY` - Backend API authentication (default: "development-api-key")
- `APP_STORE_ID` - iTunes Store item identifier for pass backlinks (optional)

### Production URLs
- Backend: `https://add2wallet-backend-production.up.railway.app`
- Universal Links: `https://links.add2wallet.app`

## Common Issues & Solutions

### Certificate Issues
- Ensure Apple Developer certificates are in `backend/certificates/`
- Run `backend/setup_certificates.sh` if needed
- Check certificate expiration dates

### Barcode Detection Issues
- Try different DPI settings in `_extract_from_images()`
- Add new image preprocessing techniques
- Verify pyzbar/OpenCV dependencies are installed correctly

### iOS Build Issues
- Regenerate project: `tuist clean && tuist generate`
- Update provisioning profiles
- Check bundle identifiers match certificates

## Project Status

Currently in **Phase 4** of development plan (see `PLAN.md`). Core functionality is complete with:
- ✅ PDF upload and processing
- ✅ Multi-format barcode detection  
- ✅ AI-powered metadata extraction
- ✅ Apple Wallet pass generation
- ✅ iOS app with share extension
- ✅ SwiftData persistence
- 🔄 Production deployment and testing

Next priorities: Enhanced error handling, UI polish, App Store preparation.

## Model Guidance for Agents

**Default: Sonnet** for implementation work — new endpoints, UI views, bug fixes, tests, refactors.

**Escalate to Opus when:**
- Changing the PDF processing pipeline architecture (orchestrator, barcode pipeline)
- AI prompt engineering (ai_service.py, ai_extractor.py) — subtle wording matters
- Certificate/signing logic changes — security-critical
- Data model changes that affect both iOS and backend
- Cross-component design decisions (API contract changes)
- Stuck after 2 attempts on a tricky bug

**MiniMax OK for:**
- Simple config changes, env vars, dependency updates
- File renaming, import cleanup
- README/doc updates