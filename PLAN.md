# Add2Wallet Monetization Implementation Plan

## Overview
Adding monetization to Add2Wallet using RevenueCat SDK with Virtual Currencies for pass management and in-app purchases.

## Implementation Checklist

### Step 1: Fix Railway Deployment Issue ✅
- [x] Investigate dependency issues in Railway deployment
- [x] Ensure numpy version compatibility (currently using numpy<2.0)
- [x] Test deployment without degrading functionality
- [x] Verify all backend services work properly in production

### Step 2: Integrate RevenueCat SDK ✅
- [x] Add RevenueCat SDK via Swift Package Manager (latest version up to next major)
- [x] Configure with public API key: `appl_fYlYmWylgRwabkYEZoocYZaCOGU`
- [x] Initialize SDK in App startup
- [ ] Test SDK integration

### Step 3: Implement PASS Virtual Currency ✅
- [x] Replace local PassUsageManager with RevenueCat Virtual Currencies
- [x] Fetch PASS balance from CustomerInfo
- [x] Update UI to display RevenueCat-based pass count
- [x] Remove local storage implementation

### Step 4: Server-Side Pass Deduction ✅
- [x] Add RevenueCat secret key as environment variable: `sk_xYDUixBpiCkUQiwlmeMlCvvFrGjNv`
- [x] Implement API call to deduct 1 PASS when generating a pass
- [x] Ensure deduction happens after successful pass generation
- [x] Add error handling for failed deductions

### Step 5: Skip Deduction for Retries ✅
- [x] Track retry status in ContentViewModel
- [x] Skip PASS deduction when isRetry flag is true
- [x] Test retry logic

### Step 6: Replace Alert with PaywallView ✅
- [x] Replace showingPurchaseAlert with RevenueCat PaywallView
- [x] Handle purchase completion and refresh CustomerInfo
- [x] Update pass balance after successful purchase
- [ ] Test purchase flow

### Step 7: Add Settings Button ✅
- [x] Add settings button to SavedPassesView navigation bar
- [x] Present RevenueCat Customer Center when tapped
- [ ] Test Customer Center presentation

### Step 8: Configure Customer Center Actions ⚠️ 
- [x] Implement "rate_app" custom action for app rating
- [x] Implement "provide_feedback" custom action with email template
- [x] Include appUserID in feedback email
- [ ] Fix Customer Center custom actions API (requires RevenueCat configuration)
- [ ] Test custom actions

## Technical Details

### RevenueCat Configuration
- **Public API Key**: `appl_fYlYmWylgRwabkYEZoocYZaCOGU` (hardcoded in app)
- **Secret API Key**: `sk_xYDUixBpiCkUQiwlmeMlCvvFrGjNv` (server environment variable)
- **Virtual Currency**: PASS

### API Endpoints to Modify
- `POST /upload` - Deduct 1 PASS after successful generation
- Add user identification for pass tracking

### iOS Changes
- SwiftUI/Swift Concurrency APIs preferred
- Customer Center with custom actions
- PaywallView for purchases

## Deployment Notes
Each step will be committed separately with proper testing before proceeding to the next.