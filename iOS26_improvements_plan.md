# iOS 26 Wallet Improvements Implementation Plan

Based on WWDC 2025 "What's new in Wallet" session, this document outlines the new features Add2Wallet should implement to enhance event tickets (museum tickets, concert tickets, etc.) for iOS 26.

## 📋 Implementation Checklist

### Phase 1: Upcoming Events Support ✨ NEW
- [ ] Implement `upcomingPassInformation` array in pass.json generation
- [ ] Add support for multiple events on a single ticket
- [ ] Create event detail screens with custom artwork
- [ ] Add unique identifiers for each upcoming event
- [ ] Implement event-specific display names and dates

### Phase 2: Enhanced Semantics for Events
- [ ] Add venue semantics to pass generation:
  - [ ] `venueName` - Name of the venue
  - [ ] `venuePlaceID` - Apple Maps place ID for venue
  - [ ] `venueLocation` - Coordinates for venue location
- [ ] Implement seat/section semantics:
  - [ ] Extract and add seat numbers from AI analysis
  - [ ] Display seats prominently on pass details
- [ ] Add performer/artist semantics for concerts
- [ ] Implement event type detection (concert, museum, theater, etc.)

### Phase 3: Dynamic Visual Assets
- [ ] Implement custom header images for events:
  - [ ] Add `headerImage` URL support in `images` object
  - [ ] Generate event-specific artwork from PDF content
  - [ ] Support multiple scales (1x, 2x, 3x) for iOS/watchOS
- [ ] Add venue map support:
  - [ ] Implement `venueMap` image URLs
  - [ ] Add `reuseExisting` flag for shared venue maps
  - [ ] Auto-generate maps using venue location data

### Phase 4: Event-Specific URLs and Actions
- [ ] Create `URLs` object for each upcoming event
- [ ] Implement event-specific action buttons:
  - [ ] Parking information links
  - [ ] Merchandise store URLs
  - [ ] Venue information pages
  - [ ] Ticket transfer/management links
- [ ] Support different URL sets per event (not reusing main pass URLs)

### Phase 5: Dynamic Event Management
- [ ] Implement `isActive` property for events:
  - [ ] Auto-update based on event start/end times
  - [ ] Mark past events as inactive
- [ ] Add pass update capability:
  - [ ] Add new upcoming events after initial pass creation
  - [ ] Remove cancelled or irrelevant events
  - [ ] Update event status dynamically

### Phase 6: iOS App Enhancements
- [ ] Implement PKPassLibrary background add capability:
  - [ ] Add `requestAuthorization(for: .backgroundAddPasses)` call
  - [ ] Check authorization status on app launch
  - [ ] Implement automatic pass addition for authorized users
- [ ] Add settings toggle for background pass addition
- [ ] Show notification when passes are added automatically
- [ ] Support batch pass addition with `addPasses` API

## 🏗️ Implementation Details

### Backend Changes (Python/FastAPI)

#### 1. Update Pass Generation (`backend/app/services/pass_generator.py`)

```python
# Add to _create_event_ticket() method

# Upcoming Events Support (iOS 26)
if metadata.event_type in ['concert', 'museum', 'theater']:
    pass_data['upcomingPassInformation'] = []
    
    # Check if this is a multi-event ticket
    if metadata.multiple_events:
        for event in metadata.upcoming_events:
            upcoming_event = {
                'type': 'event',
                'identifier': event.id,
                'displayName': event.name,
                'date': event.date.isoformat(),
                'semantics': {
                    'eventName': event.name,
                    'venueName': event.venue_name,
                    'venueLocation': {
                        'latitude': event.latitude,
                        'longitude': event.longitude
                    },
                    'venuePlaceID': event.apple_maps_id,
                },
                'URLs': {
                    'parkingInfoURL': event.parking_url,
                    'merchandiseURL': event.merch_url,
                    'venueInfoURL': event.venue_url
                },
                'images': {
                    'headerImage': {
                        '1x': f"{BASE_URL}/images/{event.id}_header_1x.png",
                        '2x': f"{BASE_URL}/images/{event.id}_header_2x.png",
                        '3x': f"{BASE_URL}/images/{event.id}_header_3x.png"
                    }
                },
                'isActive': event.date > datetime.now()
            }
            
            # Add seats if available
            if event.seat_info:
                upcoming_event['semantics']['seatNumber'] = event.seat_info
                
            pass_data['upcomingPassInformation'].append(upcoming_event)
```

#### 2. Enhanced AI Service (`backend/app/services/ai_service.py`)

Update the AI prompt to extract iOS 26 relevant information:

```python
ENHANCED_ANALYSIS_PROMPT = """
Analyze this ticket/pass and extract:
1. Event type (concert, museum, theater, sports, etc.)
2. Multiple events if this is a season pass or multi-event ticket
3. Venue information:
   - Venue name
   - Venue address/location
   - Nearby landmarks
4. For each event:
   - Event name/title
   - Date and time
   - Performers/artists (if concert)
   - Exhibit name (if museum)
   - Seat/section information
5. Available services:
   - Parking information mentioned
   - Merchandise availability
   - Food/beverage options
6. Special instructions or requirements
"""
```

#### 3. Update Models (`backend/app/models.py`)

```python
from typing import List, Optional
from datetime import datetime

class UpcomingEvent(BaseModel):
    id: str
    name: str
    date: datetime
    venue_name: str
    latitude: Optional[float]
    longitude: Optional[float]
    apple_maps_id: Optional[str]
    seat_info: Optional[str]
    parking_url: Optional[str]
    merch_url: Optional[str]
    venue_url: Optional[str]
    
class EnhancedPassMetadata(BaseModel):
    # Existing fields...
    
    # iOS 26 additions
    event_type: Optional[str]  # concert, museum, theater, etc.
    multiple_events: bool = False
    upcoming_events: List[UpcomingEvent] = []
    venue_place_id: Optional[str]
    venue_coordinates: Optional[Dict[str, float]]
    performer_names: Optional[List[str]]
    exhibit_name: Optional[str]
    has_assigned_seating: bool = False
```

### iOS App Changes (Swift)

#### 1. Update Network Service (`ios/Services/NetworkService.swift`)

```swift
// Add iOS 26 structures
struct UpcomingEvent: Codable {
    let id: String
    let name: String
    let date: Date
    let venueName: String
    let venueLocation: VenueLocation?
    let seatInfo: String?
    let urls: EventURLs?
    let isActive: Bool
}

struct EventURLs: Codable {
    let parkingInfoURL: String?
    let merchandiseURL: String?
    let venueInfoURL: String?
}

// Update EnhancedPassMetadata
struct EnhancedPassMetadata: Codable {
    // Existing fields...
    
    // iOS 26 additions
    let eventType: String?
    let multipleEvents: Bool
    let upcomingEvents: [UpcomingEvent]?
    let venuePlaceId: String?
    let performerNames: [String]?
}
```

#### 2. Implement Background Pass Addition (`ios/Add2WalletApp.swift`)

```swift
import PassKit

class PassManager: ObservableObject {
    @Published var isAuthorizedForBackgroundAdd = false
    
    func requestBackgroundAddAuthorization() async {
        guard #available(iOS 19.0, *) else { return }
        
        do {
            let status = try await PKPassLibrary().requestAuthorization(for: .backgroundAddPasses)
            await MainActor.run {
                self.isAuthorizedForBackgroundAdd = (status == .authorized)
            }
        } catch {
            print("Failed to request authorization: \(error)")
        }
    }
    
    func checkAuthorizationStatus() {
        guard #available(iOS 19.0, *) else { return }
        
        let status = PKPassLibrary().authorizationStatus(for: .backgroundAddPasses)
        isAuthorizedForBackgroundAdd = (status == .authorized)
    }
    
    func addPassesAutomatically(_ passes: [PKPass]) async throws {
        guard #available(iOS 19.0, *) else {
            // Fall back to traditional add method
            for pass in passes {
                PKPassLibrary().addPasses([pass])
            }
            return
        }
        
        if isAuthorizedForBackgroundAdd {
            // Add passes in background without prompts
            PKPassLibrary().addPasses(passes)
        } else {
            // Request authorization first
            await requestBackgroundAddAuthorization()
            if isAuthorizedForBackgroundAdd {
                PKPassLibrary().addPasses(passes)
            }
        }
    }
}
```

#### 3. Update ContentView for Multiple Events

```swift
// In ContentView.swift
if let upcomingEvents = passMetadata?.upcomingEvents, !upcomingEvents.isEmpty {
    Section("Upcoming Events") {
        ForEach(upcomingEvents, id: \.id) { event in
            VStack(alignment: .leading, spacing: 8) {
                Text(event.name)
                    .font(.headline)
                Text(event.venueName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(event.date, style: .date)
                    .font(.caption)
                if let seatInfo = event.seatInfo {
                    Label(seatInfo, systemImage: "chair")
                        .font(.caption)
                }
            }
            .padding(.vertical, 4)
            .opacity(event.isActive ? 1.0 : 0.6)
        }
    }
}
```

## 🎯 Priority Implementation Order

1. **High Priority** (Biggest user impact):
   - [ ] Upcoming events array for multi-event tickets
   - [ ] Venue semantics with Maps integration
   - [ ] Background pass addition in iOS app

2. **Medium Priority** (Enhanced experience):
   - [ ] Custom header images per event
   - [ ] Event-specific URLs and actions
   - [ ] Dynamic event management with `isActive`

3. **Nice to Have** (Polish):
   - [ ] Venue maps generation
   - [ ] Weather tile integration
   - [ ] Multi-scale image support

## 📊 Testing Requirements

### Backend Tests
- [ ] Test upcoming events array generation
- [ ] Verify semantic tags are properly formatted
- [ ] Test multi-event ticket detection
- [ ] Validate image URL generation
- [ ] Test pass updates with new events

### iOS Tests
- [ ] Test background pass authorization flow
- [ ] Verify batch pass addition
- [ ] Test upcoming events display
- [ ] Validate Maps integration with venue location
- [ ] Test pass update notifications

## 🚀 Deployment Considerations

1. **Backward Compatibility**:
   - Maintain support for iOS 18 devices
   - Gracefully degrade features for older OS versions
   - Keep existing pass structure intact

2. **Pass Validation**:
   - Test passes on iOS 26 beta
   - Verify rendering on Apple Watch
   - Ensure passes work without new features on older devices

3. **Migration Strategy**:
   - Update existing passes with new semantics via pass updates
   - Don't break existing passes in users' wallets
   - Gradual rollout with feature flags

## 📝 Notes from WWDC 2025 Transcript

Key quotes and implementation hints:

- **Line 16-17**: "Upcoming events are defined in a new 'upcomingPassInformation' array"
- **Line 20**: "The upcoming event object follows the same structure that's used for building a Poster Event Ticket"
- **Line 29-30**: "I've added the venue information using the 'venueName', 'venuePlaceID', and 'venueLocation' semantics"
- **Line 38-39**: "If I want my upcoming event guide and pass event guide to show the same URLs, I have to include the same values in my upcoming event object"
- **Line 50-51**: "The 'isActive' property in your upcoming event lets Wallet know when the event is relevant"
- **Line 137-138**: "New this year, you can request the background add passes capability, which prompts the user to allow your app to add passes to Wallet automatically"

## 🔄 Post-Implementation Tasks

- [ ] Update CLAUDE.md with iOS 26 features documentation
- [ ] Create sample passes showcasing new features
- [ ] Update App Store description with iOS 26 features
- [ ] Prepare marketing materials highlighting upcoming events support
- [ ] Submit passes for Apple review with new features

---

**Last Updated**: Based on WWDC 2025 "What's new in Wallet" session
**iOS Version Target**: iOS 26 (2025)
**Backward Compatibility**: iOS 18+