# Add2Wallet Implementation Plan

## Current Phase: UI Polish & Design System

### Overview
Implementing comprehensive UI polish based on design feedback to create a cohesive, polished user experience with proper design system, sticky CTAs, improved typography, and unified teal branding.

## Implementation Checklist

### Phase 1: High-Impact Changes (Do First) ✅
- [ ] Create ThemeManager with 8pt spacing grid, 3 elevations, 3 corner radii, and type scale
- [ ] Define teal color palette matching app icon (replacing current blue/inconsistent colors)
- [ ] Implement dynamic pass accent color extraction with fallback to brand teal
- [ ] Make "Add to Wallet" bottom-anchored, full-width, safe-area aware in ContentView
- [ ] Make "Add to Wallet" sticky in SavedPassDetailView 
- [ ] Move secondary actions (Maps, Share, Copy) below primary CTA
- [ ] Replace large PDF preview with compact thumbnail row ("View original PDF ⌄")
- [ ] Implement expandable full-screen PDF viewer on tap
- [ ] Update app tint to match icon's teal palette throughout
- [ ] Update PassColorUtils to use teal as fallback instead of blue

### Phase 2: Home Screen ("Generate Pass") Improvements
- [ ] Convert blue header to card stack design
- [ ] Top: App name + one-line value prop
- [ ] Middle: Large "Select PDF" button with doc.text.fill icon
- [ ] Bottom: Secondary actions (Files, Photos, Paste, Sample PDF)
- [ ] Replace "Passes Remaining: 9" with pill reading "9 passes left"
- [ ] Use monospaced digits, right-align in hero card
- [ ] Add progress stepper: Detect → Extract → Review → Add
- [ ] Implement subtle symbolEffect(.bounce) on completion
- [ ] Enhance empty state micro-copy: "Drop a PDF here or Select PDF"

### Phase 3: My Passes List Enhancements
- [ ] Add 2-4pt leading color stripe using pass accent color
- [ ] Keep row background system Gray 6 for readability
- [ ] Stack title (17 semibold) + subtitle (13/secondary)
- [ ] Right side: date/time in monospaced digits
- [ ] Use consistent icon size (28) and corner radius (8)
- [ ] Group headers ("JULIO 2025") in SmallCaps with letter spacing
- [ ] Add top padding to separate months

### Phase 4: Pass Detail Screen Redesign
- [ ] Large title with single-line subtitle (truncate tail)
- [ ] Two-column grid: venue (left) + date/time (right)
- [ ] Tap venue → map, tap date → add to Calendar
- [ ] Reduce map height to ~140-160pt inside card (16pt radius)
- [ ] Single "Directions" button with segmented control for Apple/Google
- [ ] Barcode/QR in own card with Copy and Save Image actions
- [ ] Alphanumerics in monospaced font with copy button
- [ ] Sticky bottom: Add to Wallet (primary)
- [ ] Secondary actions: Share pass, Share PDF, Report issue
- [ ] Collapsed PDF section by default

### Phase 5: Typography & Spacing System
- [ ] Large Title 34/34 (screen titles)
- [ ] Title2 22/28 (section titles) 
- [ ] Body 17/22 (rows)
- [ ] Footnote 13/18 (metadata)
- [ ] Monospaced for dates, times, barcodes, counters
- [ ] 8pt grid system implementation
- [ ] 16pt between groups
- [ ] 24pt before/after major blocks
- [ ] Right-align dates in list rows
- [ ] Left-align everything else
- [ ] Replace long subtitles with concise single lines

### Phase 6: UX Polish & Micro-interactions
- [ ] Light impact on "Add to Wallet"
- [ ] Selection haptic on row tap
- [ ] Success haptic on pass creation complete
- [ ] Checkmark toast ("Added to Wallet") with "Open" action
- [ ] Inline error blocks with retry and diagnostic link
- [ ] First-run coach mark: "Pick a PDF → Review → Add"

### Phase 7: Component-Level Implementation
- [ ] Sticky CTA: safeAreaInset(edge: .bottom) with blurred background
- [ ] Cards: .regularMaterial/.secondarySystemBackground with cornerRadius(16)
- [ ] List stripes: custom overlay with accent.frame(width: 4)
- [ ] Type tokens: enum wrapper for consistent sizes/weights
- [ ] Extract dominant color from pass images (k-means/average)
- [ ] Clamp to min contrast 4.5:1 vs white/black
- [ ] Use dynamic colors for header background, list stripes, chips only

### Phase 8: Testing & Verification
- [ ] Verify consistent spacing across all screens
- [ ] Test color contrast ratios meet accessibility standards
- [ ] Validate type scale hierarchy
- [ ] Test sticky CTAs on various device sizes
- [ ] Verify collapsed/expanded PDF functionality
- [ ] Test dynamic color system with various pass types
- [ ] Test haptic feedback on supported devices
- [ ] Verify smooth animations and transitions

## Technical Details

### Design System Foundation
- 8pt spacing grid (8, 16, 24, 32, 40pt)
- 3 elevations: flat, card (.regularMaterial), sheet (.ultraThinMaterial)
- 3 corner radii: 8pt (small), 16pt (medium), 24pt (large)
- Typography scale with SF Pro weights
- Teal brand color matching app icon
- Dynamic pass accent colors with contrast requirements

### Color System
- Primary Brand: Teal (#20B2AA or equivalent from icon)
- Surface Default: system background
- Surface Card: Gray 6 (dark), White (light)
- Accent Pass: computed from pass metadata
- Dynamic accent rules: min contrast 4.5:1, fallback to brand teal

### Implementation Notes
- Use safeAreaInset for sticky CTAs
- Implement custom View modifiers for consistent styling
- Create reusable components following design system
- Ensure accessibility compliance throughout

## Previous Phases (Completed)

### Error Handling & Demo Mode Implementation ✅
- [x] Fix "data isn't in the right format" error with better PKPass error handling
- [x] Add retry count tracking to ContentViewModel
- [x] Implement alert after 2nd retry attempt offering support contact
- [x] Copy "torre ifel.pdf" from backend test files to iOS app Resources
- [x] Add demo mode flag to ContentViewModel
- [x] Add "Try a Demo" button to main screen
- [x] Implement demo file loading from app bundle
- [x] Update backend to skip RevenueCat pass deduction for demo mode

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

## Design Principles
- Teal branding unification (app icon → app tint → accents)
- Meaningful color without sacrificing readability
- Sticky primary actions for better reachability
- Dynamic pass colors for visual interest
- 8pt spacing grid for visual rhythm
- Consistent typography hierarchy
- Reduced visual noise through card organization
- Progressive disclosure (collapsed → expanded)