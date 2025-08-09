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
python -m venv venv
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
**Commands**:

```bash
# Setup (requires Tuist)
cd ios
tuist generate

# Run tests from Xcode
# Product > Test (⌘+U)

# Or via command line
xcodebuild test -scheme Add2Wallet
```

**Key Test Files**:
- `NetworkServiceTests.swift` - API communication tests
- `ContentViewModelTests.swift` - View model logic tests
- `ShareExtensionTests.swift` - Share extension tests

## Development Setup

### Backend Development

```bash
cd backend
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt

# Set environment variables
export OPENAI_API_KEY="your-key-here"
export API_KEY="development-api-key"

# Run development server
python run.py
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

1. Start backend server: `cd backend && python run.py`
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