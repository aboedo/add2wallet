import SwiftUI

struct PassDetailsView: View {
    let metadata: EnhancedPassMetadata
    let ticketCount: Int?
    private let keyWidth: CGFloat = 120
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Show async map if we have location data
            AsyncMapView(metadata: metadata)
            
            // Other information below the map
            Group {
                keyValueRow("Seat", metadata.seatInfo)
                keyValueRow("Barcode", metadata.barcodeData)
                keyValueRow("Price", metadata.price)
                keyValueRow("Confirmation", metadata.confirmationNumber)
                keyValueRow("Gate", metadata.gateInfo)
                if let ticketCount, ticketCount > 1 {
                    keyValueRow("Number of passes", String(ticketCount))
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground).opacity(0.8))
    }
    
    @ViewBuilder
    private func keyValueRow(_ key: String, _ value: String?) -> some View {
        if let value = value, !value.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Text("\(key):")
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .frame(width: keyWidth, alignment: .leading)
                Text(value)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
    
    PassDetailsView(metadata: sampleMetadata, ticketCount: 2)
        .padding()
}