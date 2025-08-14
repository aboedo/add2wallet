# Add2Wallet Monetization Implementation Plan

## Overview
Adding monetization to Add2Wallet using RevenueCat SDK with Virtual Currencies for pass management and in-app purchases.

## Implementation Checklist

### Step 1: Fix Railway Deployment Issue ⚠️
- [ ] Investigate dependency issues in Railway deployment
- [ ] Ensure numpy version compatibility (currently using numpy<2.0)
- [ ] Test deployment without degrading functionality
- [ ] Verify all backend services work properly in production

### Step 2: Integrate RevenueCat SDK
- [ ] Add RevenueCat SDK via Swift Package Manager (latest version up to next major)
- [ ] Configure with public API key: `appl_fYlYmWylgRwabkYEZoocYZaCOGU`
- [ ] Initialize SDK in App startup
- [ ] Test SDK integration

### Step 3: Implement PASS Virtual Currency
- [ ] Replace local PassUsageManager with RevenueCat Virtual Currencies
- [ ] Fetch PASS balance from CustomerInfo
- [ ] Update UI to display RevenueCat-based pass count
- [ ] Remove local storage implementation

### Step 4: Server-Side Pass Deduction
- [ ] Add RevenueCat secret key as environment variable: `sk_xYDUixBpiCkUQiwlmeMlCvvFrGjNv`
- [ ] Implement API call to deduct 1 PASS when generating a pass
- [ ] Ensure deduction happens after successful pass generation
- [ ] Add error handling for failed deductions

### Step 5: Skip Deduction for Retries
- [ ] Track retry status in ContentViewModel
- [ ] Skip PASS deduction when isRetry flag is true
- [ ] Test retry logic

### Step 6: Replace Alert with PaywallView
- [ ] Replace showingPurchaseAlert with RevenueCat PaywallView
- [ ] Handle purchase completion and refresh CustomerInfo
- [ ] Update pass balance after successful purchase
- [ ] Test purchase flow

### Step 7: Add Settings Button
- [ ] Add settings button to SavedPassesView navigation bar
- [ ] Present RevenueCat Customer Center when tapped
- [ ] Test Customer Center presentation

### Step 8: Configure Customer Center Actions
- [ ] Implement "rate_app" custom action for app rating
- [ ] Implement "provide_feedback" custom action with email template
- [ ] Include appUserID in feedback email
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