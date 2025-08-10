import SwiftUI

struct PassMetadataView: View {
    let metadata: EnhancedPassMetadata
    let style: Style
    let ticketCount: Int?
    
    enum Style {
        case contentView    // For ContentView (colored background)
        case detailView     // For SavedPassDetailView (on colored background)
    }
    
    init(metadata: EnhancedPassMetadata, style: Style = .contentView, ticketCount: Int? = nil) {
        self.metadata = metadata
        self.style = style
        self.ticketCount = ticketCount
    }
    
    private var primaryTextColor: Color {
        switch style {
        case .contentView:
            return .primary
        case .detailView:
            return .white.opacity(0.9)
        }
    }
    
    private var secondaryTextColor: Color {
        switch style {
        case .contentView:
            return .secondary
        case .detailView:
            return .white.opacity(0.7)
        }
    }
    
    private var iconColor: Color {
        switch style {
        case .contentView:
            return .blue
        case .detailView:
            return .white.opacity(0.9)
        }
    }
    
    private var backgroundColor: Color? {
        switch style {
        case .contentView:
            return Color(.secondarySystemBackground)
        case .detailView:
            return nil
        }
    }
    
    var body: some View {
        VStack(spacing: style == .contentView ? 12 : 8) {
            // Date and time field with calendar icon
            if let dateTimeString = PassDateTimeFormatter.combineDateTime(date: metadata.date, time: metadata.time) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundColor(style == .contentView ? .blue : iconColor)
                        .font(.subheadline)
                    Text(dateTimeString)
                        .font(.subheadline)
                        .foregroundColor(primaryTextColor)
                    Spacer()
                }
            }
            
            // Event description field
            if let description = metadata.eventDescription ?? metadata.description {
                HStack(spacing: 8) {
                    Image(systemName: "text.alignleft")
                        .foregroundColor(secondaryTextColor)
                        .font(.caption)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(secondaryTextColor)
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
                .if(style == .detailView) { view in
                    view.padding(.bottom)
                }
            }
            
            // Venue field with map pin icon
            if let venue = metadata.venueName {
                VStack(alignment: .leading) {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin")
                            .foregroundColor(style == .contentView ? .red : iconColor)
                            .font(.subheadline)
                        Text(venue)
                            .font(.subheadline)
                            .foregroundColor(primaryTextColor)
                        Spacer()
                    }
                    
                    // Show full address for detail view
                    if style == .detailView,
                       let address = metadata.venueAddress,
                       let city = metadata.city,
                       let country = metadata.stateCountry {
                        Text("\(address), \(city), \(country)")
                            .font(.caption)
                            .foregroundColor(primaryTextColor)
                        Spacer()
                    }
                }
            }
            
            // Ticket count for detail view
            if style == .detailView, let ticketCount, ticketCount > 1 {
                HStack {
                    Text("\(ticketCount) tickets")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.4))
                        )
                    Spacer()
                }
            }
        }
        .padding()
        .if(backgroundColor != nil) { view in
            view.background(backgroundColor!)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// Helper extension for conditional view modifiers
extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#Preview {
    let sampleMetadata = EnhancedPassMetadata(
        eventType: "Concert",
        eventName: "Taylor Swift Concert",
        title: "Taylor Swift Eras Tour",
        description: "The most spectacular concert of the year",
        date: "2024-12-15",
        time: "20:00",
        duration: "3 hours",
        venueName: "Madison Square Garden",
        venueAddress: "4 Pennsylvania Plaza",
        city: "New York",
        stateCountry: "NY, USA",
        latitude: 40.7505,
        longitude: -73.9934,
        organizer: "Live Nation",
        performerArtist: "Taylor Swift",
        seatInfo: "Section 100, Row A, Seat 15",
        barcodeData: "123456789",
        price: "$150.00",
        confirmationNumber: "ABC123XYZ",
        gateInfo: "Gate 7",
        eventDescription: "Experience the magic of Taylor Swift's Eras Tour",
        venueType: "Arena",
        capacity: "20,000",
        website: "msg.com",
        phone: "(212) 465-6741",
        nearbyLandmarks: ["Empire State Building", "Herald Square"],
        publicTransport: "Penn Station (1, 2, 3, A, C, E trains)",
        parkingInfo: "$40 event parking available",
        ageRestriction: "All ages",
        dressCode: "Casual",
        weatherConsiderations: "Indoor venue",
        amenities: ["Concessions", "Gift Shop", "Accessible Seating"],
        accessibility: "ADA compliant",
        aiProcessed: true,
        confidenceScore: 95,
        processingTimestamp: "2024-01-01T12:00:00Z",
        modelUsed: "gpt-4",
        enrichmentCompleted: true,
        backgroundColor: "rgb(138,43,226)",
        foregroundColor: "rgb(255,255,255)",
        labelColor: "rgb(255,255,255)"
    )
    
    VStack(spacing: 20) {
        // ContentView style
        PassMetadataView(metadata: sampleMetadata, style: .contentView)
        
        // DetailView style  
        PassMetadataView(metadata: sampleMetadata, style: .detailView, ticketCount: 2)
            .background(
                LinearGradient(
                    colors: [Color.purple, Color.purple.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
    .padding()
}