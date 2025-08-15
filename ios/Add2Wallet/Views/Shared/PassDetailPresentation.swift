import SwiftUI

// This component replicates the SavedPassDetailView presentation style
// for use in both ContentView and SavedPassDetailView
struct PassDetailPresentation: View {
    let metadata: EnhancedPassMetadata
    let ticketCount: Int?
    let isEmbedded: Bool // true when used in ContentView, false in SavedPassDetailView
    
    private var passColor: Color {
        PassColorUtils.getPassColor(metadata: metadata)
    }
    
    private var darkenedPassColor: Color {
        PassColorUtils.getDarkenedPassColor(metadata: metadata)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header section with pass color theming - matches SavedPassDetailView
            VStack(spacing: 8) {
                // Title
                Text(metadata.title ?? metadata.eventName ?? "Untitled Pass")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                
                // Use shared PassMetadataView for subtitle info
                PassMetadataView(
                    metadata: metadata,
                    style: .detailView,
                    ticketCount: ticketCount
                )
            }
            .padding()
            .frame(maxWidth: .infinity)
            
            // Pass details section
            PassDetailsView(metadata: metadata, ticketCount: isEmbedded ? ticketCount : nil)
                .transition(.opacity)
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
        PassDetailPresentation(
            metadata: sampleMetadata,
            ticketCount: 2,
            isEmbedded: true
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
