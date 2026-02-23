import SwiftUI

struct PassDetailPresentation: View {
    let metadata: EnhancedPassMetadata
    let ticketCount: Int?
    let isEmbedded: Bool
    
    private var passColor: Color {
        PassColorUtils.getPassColor(metadata: metadata)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Accent strip — pass brand color
            passColor
                .frame(height: 6)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: ThemeManager.CornerRadius.large, topTrailingRadius: ThemeManager.CornerRadius.large))
            
            // Unified card
            VStack(alignment: .leading, spacing: ThemeManager.Spacing.lg) {
                // Header: title + key info
                VStack(alignment: .leading, spacing: ThemeManager.Spacing.sm) {
                    Text(metadata.title ?? metadata.eventName ?? "Untitled Pass")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(ThemeManager.Colors.textPrimary)
                    
                    PassMetadataView(
                        metadata: metadata,
                        style: .detailView,
                        ticketCount: ticketCount
                    )
                }
                
                Divider()
                
                // Map
                AsyncMapView(metadata: metadata)
                
                // Detail fields in a 2-column grid
                detailFields
                
                // Ticket count if multiple
                if let count = ticketCount, count > 1 {
                    HStack(spacing: ThemeManager.Spacing.xs) {
                        Image(systemName: "ticket")
                            .foregroundColor(passColor)
                        Text("\(count) passes included")
                            .font(ThemeManager.Typography.footnote)
                            .foregroundColor(ThemeManager.Colors.textSecondary)
                    }
                }
            }
            .padding(ThemeManager.Spacing.lg)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: ThemeManager.CornerRadius.large, bottomTrailingRadius: ThemeManager.CornerRadius.large))
        }
    }
    
    @ViewBuilder
    private var detailFields: some View {
        let fields = buildFields()
        
        if !fields.isEmpty {
            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ], alignment: .leading, spacing: ThemeManager.Spacing.md) {
                ForEach(fields, id: \.label) { field in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(field.label.uppercased())
                            .font(ThemeManager.Typography.caption)
                            .foregroundColor(ThemeManager.Colors.textTertiary)
                        Text(field.value)
                            .font(ThemeManager.Typography.body)
                            .foregroundColor(ThemeManager.Colors.textPrimary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
    
    private struct FieldItem: Hashable {
        let label: String
        let value: String
    }
    
    private func buildFields() -> [FieldItem] {
        var fields: [FieldItem] = []
        
        if let passenger = metadata.seatInfo, !passenger.isEmpty {
            fields.append(FieldItem(label: "Seat", value: passenger))
        }
        if let price = metadata.price, !price.isEmpty {
            fields.append(FieldItem(label: "Price", value: price))
        }
        if let conf = metadata.confirmationNumber, !conf.isEmpty {
            fields.append(FieldItem(label: "Confirmation", value: conf))
        }
        if let gate = metadata.gateInfo, !gate.isEmpty {
            fields.append(FieldItem(label: "Gate", value: gate))
        }
        if let performers = metadata.performerNames, !performers.isEmpty {
            fields.append(FieldItem(label: "Artists", value: performers.joined(separator: ", ")))
        }
        if let exhibit = metadata.exhibitName, !exhibit.isEmpty {
            fields.append(FieldItem(label: "Exhibit", value: exhibit))
        }
        
        return fields
    }
}

#Preview {
    let sampleMetadata = EnhancedPassMetadata(
        eventType: "Ferry",
        eventName: "Buquebus Ferry",
        title: "Buquebus: MVD to BUE",
        description: "Ferry travel from Montevideo to Buenos Aires",
        date: "2026-03-30",
        time: "11:00",
        duration: "2.5 hours",
        venueName: "Buquebus Ferry",
        venueAddress: nil,
        city: "Montevideo",
        stateCountry: "Uruguay",
        latitude: -34.9011,
        longitude: -56.1645,
        organizer: "Buquebus",
        performerArtist: nil,
        seatInfo: nil,
        barcodeData: nil,
        price: "$5,423.98",
        confirmationNumber: "B2600378709",
        gateInfo: nil,
        eventDescription: "Ferry travel from Montevideo to Buenos Aires",
        venueType: "Port",
        capacity: nil,
        website: nil,
        phone: nil,
        nearbyLandmarks: nil,
        publicTransport: nil,
        parkingInfo: nil,
        ageRestriction: nil,
        dressCode: nil,
        weatherConsiderations: nil,
        amenities: nil,
        accessibility: nil,
        aiProcessed: true,
        confidenceScore: 90,
        processingTimestamp: nil,
        modelUsed: nil,
        enrichmentCompleted: true,
        backgroundColor: "rgb(0, 51, 161)",
        foregroundColor: "rgb(255, 255, 255)",
        labelColor: "rgb(200, 200, 200)",
        multipleEvents: nil,
        upcomingEvents: nil,
        venuePlaceId: nil,
        performerNames: nil,
        exhibitName: nil,
        hasAssignedSeating: nil,
        eventUrls: nil
    )
    
    ScrollView {
        PassDetailPresentation(
            metadata: sampleMetadata,
            ticketCount: 2,
            isEmbedded: false
        )
    }
    .background(Color(.systemGroupedBackground))
}
