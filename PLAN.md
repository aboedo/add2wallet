# Add2Wallet iOS App Polish Plan

## Progress Tracker

### Task List

- [x] Task 1: Update empty state in "My Passes" tab
  - Change copy to "Start by generating your first Pass" 
  - Make "generating your first Pass" link to Generate Pass tab
  - Update tab title from "Your Passes" to "My Passes"

- [x] Task 2: Add PDF storage to SavedPass model
  - Add `pdfData: Data` property to SavedPass
  - Update save logic to include PDF data
  - Add PDF preview in SavedPassDetailView with full-screen tap

- [x] Task 3: Multi-pass support in SavedPass model
  - Replace single `passData` with `passDatas: [Data]` array
  - Group multiple passes in one SavedPass entry
  - Add pass count badge when > 1
  - Update detail view for multiple passes

- [x] Task 4: Implement fake progress bar
  - Add progress tracking with non-linear steps
  - Replace ProcessingView with progress bar
  - 30-second total with realistic intermediate steps

- [x] Task 5: Fix bottom view in Generate Pass tab
  - Only show when `selectedFileURL != nil || isProcessing`
  - Remove empty view when no content

- [x] Task 6: Visual style updates for My Passes view
  - Extract and use pass colors from metadata
  - Move date to right side of row
  - Group passes by month
  - Sort by date within months

- [ ] Task 7: Enhanced pass type thumbnails
  - Add museum, concert, sports icons
  - Improve icon matching for pass types
  - Update color scheme

- [ ] Task 8: Create tracking documentation
  - ✅ Created this PLAN.md file
  - Update checklist after each task

## Notes

- No data migration needed - breaking changes to SavedPass model are OK
- Build after each task to verify compilation
- Commit after each completed task

---

# Original Project Plan

## High-Level System Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                         iOS App                              │
│  ┌─────────────┐        ┌──────────────────┐               │
│  │ Main App    │        │ Share Extension  │               │
│  │ - Pass View │        │ - PDF Receiver   │               │
│  │ - Library   │        │ - Quick Upload   │               │
│  │ - Settings  │        └──────────────────┘               │
│  └─────────────┘                                            │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ HTTPS REST API
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     Python Backend                           │
│  ┌──────────────┐    ┌──────────────┐   ┌────────────────┐│
│  │ API Gateway  │───▶│ PDF Processor│───▶│ Pass Generator ││
│  │ - FastAPI    │    │ - Text Extract│   │ - PassKit      ││
│  │ - Auth       │    │ - OpenAI API │   │ - Signing      ││
│  │ - Validation │    │ - Enrichment │   │ - .pkpass      ││
│  └──────────────┘    └──────────────┘   └────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### Communication Protocol

#### REST API Endpoints

```yaml
Base URL: https://api.add2wallet.com/v1

Endpoints:
  POST /upload:
    Description: Upload PDF for processing
    Request:
      Content-Type: multipart/form-data
      Body:
        - file: PDF binary
        - user_id: string
        - session_token: string
    Response:
      200: { job_id: string, status: "processing" }
      400: { error: "Invalid PDF" }
      401: { error: "Unauthorized" }

  GET /status/{job_id}:
    Description: Check processing status
    Headers:
      Authorization: Bearer {session_token}
    Response:
      200: { 
        job_id: string,
        status: "processing|completed|failed",
        progress: 0-100,
        result_url?: string
      }

  GET /pass/{job_id}:
    Description: Download generated pass
    Headers:
      Authorization: Bearer {session_token}
    Response:
      200: Binary .pkpass file
      404: { error: "Pass not found" }

  POST /pass/{job_id}/customize:
    Description: Modify pass before download
    Request:
      Body: {
        colors: { background, foreground, label },
        fields: { modifications to extracted data }
      }
    Response:
      200: { preview_url: string }

  GET /passes:
    Description: List user's passes
    Headers:
      Authorization: Bearer {session_token}
    Response:
      200: { passes: [...] }
```

### Authentication & Security

#### Authentication Flow

```
1. Initial Setup (Phase 1 - Basic):
   - API Key authentication for development
   - Static API key in request headers
   - Rate limiting by IP address

2. Production Setup (Phase 7):
   - OAuth 2.0 with Sign in with Apple
   - JWT tokens with refresh mechanism
   - Device fingerprinting for additional security
```

#### Security Measures

```yaml
Request Security:
  - HTTPS only (TLS 1.3)
  - Certificate pinning in iOS app
  - Request signing with HMAC-SHA256
  - Nonce for replay attack prevention

Data Security:
  - PDF sanitization before processing
  - File size limits (10MB max)
  - Virus scanning for uploads
  - Temporary file deletion after processing
  - No persistent storage of user PDFs

API Security:
  - Rate limiting: 100 requests/hour per user
  - DDoS protection via CloudFlare
  - Input validation on all endpoints
  - SQL injection prevention
  - XSS protection headers
```

### Data Flow Architecture

```
1. PDF Upload Flow:
   User → Share Extension → iOS App → Backend API → Queue
   
2. Processing Pipeline:
   Queue → PDF Parser → OpenAI API → Data Enrichment → Validation
   
3. Pass Generation:
   Validated Data → Template Engine → PassKit → Certificate Signing → .pkpass
   
4. Delivery:
   .pkpass → CDN → iOS App → Apple Wallet
```

### Error Handling Strategy

```yaml
Client-Side (iOS):
  - Network retry with exponential backoff
  - Offline queue for pending uploads
  - User-friendly error messages
  - Fallback to manual entry option

Server-Side (Python):
  - Structured logging with correlation IDs
  - Dead letter queue for failed jobs
  - Graceful degradation for external services
  - Circuit breaker for OpenAI API
  - Automatic retry for transient failures
```

### Scalability Considerations

```yaml
Phase 1 (MVP):
  - Single server deployment
  - SQLite for job tracking
  - File system for temporary storage
  - Synchronous processing

Phase 7 (Production):
  - Load balancer with multiple instances
  - PostgreSQL for persistence
  - Redis for caching and queues
  - S3 for temporary file storage
  - Async processing with Celery
  - Horizontal scaling capability
```

## Architecture Components

### 1. iOS Native App
- Share extension for PDF import
- UI for pass preview/editing
- Apple Wallet integration
- Unit test coverage

### 2. Python Backend Service
- PDF processing endpoint
- OpenAI integration for metadata extraction
- Web scraping for event enrichment
- Pass generation with PassKit
- Unit test coverage

## Development Phases

### Phase 1: Foundation Setup
**Goal**: Basic iOS app with share extension + minimal Python server

#### iOS Tasks:
- [ ] Create new iOS project with SwiftUI
- [ ] Add share extension target
- [ ] Configure extension to accept PDF files
- [ ] Implement basic "Hello World" UI
- [ ] Add networking layer for server communication
- [ ] Send PDF to backend via multipart form
- [ ] Add basic unit test structure
- [ ] Configure development provisioning profiles

#### Backend Tasks:
- [ ] Set up Python project with FastAPI/Flask
- [ ] Create `/upload` endpoint for PDF reception
- [ ] Implement file validation (PDF only)
- [ ] Return basic success response
- [ ] Add pytest test structure
- [ ] Create requirements.txt
- [ ] Add local development server script

### Phase 2: Core Processing Pipeline
**Goal**: Process PDFs and extract structured data

#### Backend Tasks:
- [ ] Integrate OpenAI API client
- [ ] Create prompt engineering for ticket/pass extraction
- [ ] Define pass metadata schema (JSON)
- [ ] Implement PDF text extraction (PyPDF2/pdfplumber)
- [ ] Add image extraction for logos/barcodes
- [ ] Create data validation layer
- [ ] Add comprehensive error handling
- [ ] Write unit tests for each component

#### iOS Tasks:
- [ ] Design pass preview UI
- [ ] Implement loading states
- [ ] Add error handling UI
- [ ] Create pass data model
- [ ] Parse backend response
- [ ] Add progress indicators

### Phase 3: Event Enrichment
**Goal**: Enhance pass data with online information

#### Backend Tasks:
- [ ] Implement event search API integration (Google/Bing)
- [ ] Add venue lookup service
- [ ] Create web scraping module for event details
- [ ] Implement location geocoding
- [ ] Add date/time validation and formatting
- [ ] Create fallback strategies for missing data
- [ ] Cache external API responses

### Phase 4: Apple Wallet Integration
**Goal**: Generate and install actual Wallet passes

#### Prerequisites:
- [ ] Obtain Apple Developer Pass Type ID
- [ ] Generate Pass Type certificate
- [ ] Create WWDR certificate
- [ ] Set up certificate storage in backend

#### Backend Tasks:
- [ ] Integrate PassKit library (wallet-py3k or similar)
- [ ] Create pass template system
- [ ] Implement pass.json generation
- [ ] Add barcode/QR code generation
- [ ] Implement pass signing with certificates
- [ ] Generate .pkpass files
- [ ] Add pass customization options

#### iOS Tasks:
- [ ] Implement PKPass preview
- [ ] Add "Add to Wallet" functionality
- [ ] Handle pass installation callbacks
- [ ] Implement pass update notifications
- [ ] Add pass management UI

### Phase 5: UI Polish & UX
**Goal**: Production-ready user interface

#### iOS Tasks:
- [ ] Design app icon and branding
- [ ] Implement onboarding flow
- [ ] Add pass history/library
- [ ] Create settings screen
- [ ] Add haptic feedback
- [ ] Implement dark mode support
- [ ] Add accessibility features
- [ ] Create custom animations
- [ ] Add analytics integration

### Phase 6: Testing & Quality
**Goal**: Comprehensive test coverage

#### Testing Tasks:
- [ ] iOS: Unit tests for all ViewModels
- [ ] iOS: UI tests for critical flows
- [ ] iOS: Share extension integration tests
- [ ] Backend: Unit tests for all endpoints
- [ ] Backend: Integration tests with OpenAI
- [ ] Backend: Pass generation tests
- [ ] End-to-end testing scenarios
- [ ] Performance testing with large PDFs
- [ ] Security testing for file uploads

### Phase 7: Deployment Preparation
**Goal**: Ready for production

#### Infrastructure:
- [ ] Set up production server (AWS/GCP/Azure)
- [ ] Configure SSL certificates
- [ ] Set up monitoring (Sentry/DataDog)
- [ ] Implement rate limiting
- [ ] Add authentication (if needed)
- [ ] Set up CI/CD pipeline
- [ ] Create deployment scripts

#### iOS Release:
- [ ] Create App Store listing
- [ ] Prepare screenshots
- [ ] Write app description
- [ ] Submit for App Review
- [ ] Prepare TestFlight beta

## Technical Stack

### iOS
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Networking**: URLSession / Alamofire
- **Testing**: XCTest
- **Pass Integration**: PassKit

### Backend
- **Language**: Python 3.11+
- **Framework**: FastAPI
- **AI Service**: OpenAI API
- **PDF Processing**: PyPDF2/pdfplumber
- **Pass Generation**: wallet-py3k
- **Testing**: pytest
- **Web Scraping**: BeautifulSoup4/Scrapy

## Development Guidelines

### Code Standards
- iOS: Follow Swift style guide
- Python: PEP 8 compliance
- Git: Conventional commits
- Documentation: Inline + README

### Project Management
- **Use Tuist for iOS project generation**: All Xcode project files are generated using Tuist configuration
- **Compilation verification**: For every change in the iOS app, ensure that it continues to compile successfully
- **Test project integrity**: After each modification, verify the project opens in Xcode and builds without errors

### Testing Requirements
- Minimum 80% code coverage
- All endpoints must have tests
- Critical paths require integration tests
- UI tests for main user flows

### Security Considerations
- Validate all file uploads
- Sanitize PDF content
- Secure API key storage
- HTTPS only communication
- Rate limiting on endpoints
- Input size restrictions

## Current Status
**Phase**: Not Started
**Next Steps**: Begin Phase 1 - Foundation Setup

## Success Metrics
- [ ] PDF to pass conversion < 10 seconds
- [ ] 95% success rate for ticket PDFs
- [ ] Support for 10+ pass types
- [ ] App Store approval achieved
- [ ] 90%+ test coverage

## Risk Mitigation
- **OpenAI API limits**: Implement caching and fallback
- **Pass signing complexity**: Early certificate setup
- **App Store rejection**: Follow guidelines strictly
- **PDF parsing failures**: Multiple extraction methods
- **Event matching accuracy**: Manual override option

## Handoff Instructions

### For Continuing Development
1. Check current phase status in this document
2. Review completed checkboxes in current phase
3. Pick up next unchecked task
4. Run existing tests before making changes
5. Update checkboxes as tasks complete
6. Commit with descriptive messages

### Environment Setup

#### iOS Development
```bash
# Requirements
# - Xcode 15.0+
# - iOS 17.0+ SDK
# - Apple Developer Account
# - Tuist (brew install tuist)

# Clone and open project
git clone [repository]
cd add2wallet/ios

# Generate Xcode project using Tuist
tuist generate

# Open generated project
open Add2Wallet.xcodeproj

# Run tests
xcodebuild test -scheme Add2Wallet

# Verify compilation after changes
xcodebuild -scheme Add2Wallet build
```

#### Backend Development
```bash
# Requirements
# - Python 3.11+
# - pip/poetry
# - OpenAI API key

# Setup
cd add2wallet/backend
python -m venv venv
source venv/bin/activate  # or venv\Scripts\activate on Windows
pip install -r requirements.txt

# Environment variables
export OPENAI_API_KEY="your-key-here"

# Run server
python app.py  # or uvicorn main:app --reload for FastAPI

# Run tests
pytest
```

### Key Files and Locations
- iOS Project: `/ios/Add2Wallet/`
- Share Extension: `/ios/Add2WalletExtension/`
- Backend Server: `/backend/`
- Tests: `/ios/Add2WalletTests/` and `/backend/tests/`
- Certificates: `/backend/certificates/` (gitignored)
- Documentation: `/docs/`

This plan provides a clear roadmap with checkpoints for handoff between sessions or team members.