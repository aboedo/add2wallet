# Add2Wallet Implementation Plan

## Current Phase: App Polish & Demo Mode

### Overview
Implementing error handling improvements, retry experience enhancements, and demo mode functionality for the Add2Wallet iOS app.

## Implementation Checklist

### Phase 1: Error Handling & Retry Experience
- [ ] Fix "data isn't in the right format" error with better PKPass error handling
- [ ] Add retry count tracking to ContentViewModel
- [ ] Implement alert after 2nd retry attempt offering support contact
- [ ] Include PDF and appUserID in support email (already implemented)

### Phase 2: Demo Mode Implementation
- [ ] Copy "torre ifel.pdf" from backend test files to iOS app Resources
- [ ] Add demo mode flag to ContentViewModel
- [ ] Add "Try a Demo" button to main screen (text-only, bottom position)
- [ ] Implement demo file loading from app bundle
- [ ] Pass demo flag through upload chain to backend
- [ ] Update backend to skip RevenueCat pass deduction for demo mode
- [ ] Ensure demo mode doesn't require pass balance check

### Phase 3: Testing & Verification
- [ ] Test retry flow with problematic PDFs
- [ ] Verify support email includes correct attachments
- [ ] Test demo mode end-to-end
- [ ] Ensure demo doesn't affect pass balance
- [ ] Test error messages are user-friendly

## Technical Details

### Error Handling Improvements
- Better error catching around PKPass initialization
- Specific error messages for different failure types
- Logging for debugging intermittent issues

### Retry Experience
- Track retry attempts in ContentViewModel
- Show helpful alert after 2nd retry
- Offer to send problematic file to support
- Pre-fill email with diagnostic information

### Demo Mode
- Demo PDF: "torre ifel.pdf" (Eiffel Tower ticket)
- No pass balance required
- No pass deduction on backend
- Same UI flow as regular processing
- Clear indication this is a demo

## Previous Phases (Completed)

### Monetization Implementation ✅
- [x] Fix Railway deployment issue
- [x] Integrate RevenueCat SDK
- [x] Implement PASS Virtual Currency
- [x] Server-side pass deduction
- [x] Skip deduction for retries
- [x] Replace alert with PaywallView
- [x] Add settings button
- [x] Configure customer center actions

### Core Functionality ✅
- [x] PDF upload and processing
- [x] Multi-format barcode detection
- [x] AI-powered metadata extraction
- [x] Apple Wallet pass generation
- [x] iOS app with share extension
- [x] SwiftData persistence
- [x] Production deployment

## Notes
- Demo mode helps users try the app without commitment
- Better error handling reduces user frustration
- Support contact flow helps gather problematic PDFs for testing