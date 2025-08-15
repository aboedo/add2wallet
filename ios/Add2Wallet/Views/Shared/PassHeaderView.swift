import SwiftUI

struct PassHeaderView: View {
    let title: String
    let subtitle: String?
    let metadata: EnhancedPassMetadata?
    let passType: String?
    let showDateTime: Bool
    
    init(title: String, subtitle: String? = nil, metadata: EnhancedPassMetadata? = nil, passType: String? = nil, showDateTime: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.metadata = metadata
        self.passType = passType
        self.showDateTime = showDateTime
    }
    
    private var headerColor: Color {
        if let metadata = metadata {
            return PassColorUtils.getPassColor(metadata: metadata)
        } else if let passType = passType {
            return PassColorUtils.fallbackColorFromPassType(passType)
        }
        return .blue
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Date and time field with calendar icon (if enabled and available)
            if showDateTime,
               let metadata = metadata,
               let dateTimeString = PassDateTimeFormatter.combineDateTime(date: metadata.date, time: metadata.time) {
                HStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "calendar")
                        .foregroundColor(.white.opacity(0.9))
                        .font(.subheadline)
                    Text(dateTimeString)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            
            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
            
            if let subtitle = subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(showDateTime ? .title3 : .subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [headerColor, headerColor.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    VStack(spacing: 16) {
        // ContentView style
        PassHeaderView(
            title: "Add2Wallet", 
            subtitle: "Convert PDFs to Apple Wallet passes",
            metadata: nil,
            passType: nil
        )
        
        // SavedPassDetailView style  
        PassHeaderView(
            title: "Taylor Swift Concert",
            subtitle: "Experience the magic of Taylor Swift's Eras Tour",
            metadata: EnhancedPassMetadata(
                eventType: "Concert",
                eventName: "Taylor Swift Concert",
                title: "Taylor Swift Eras Tour",
                description: "The most spectacular concert of the year",
                date: "2024-12-15",
                time: "20:00",
                duration: nil,
                venueName: "Madison Square Garden",
                venueAddress: nil,
                city: nil,
                stateCountry: nil,
                latitude: nil,
                longitude: nil,
                organizer: nil,
                performerArtist: nil,
                seatInfo: nil,
                barcodeData: nil,
                price: nil,
                confirmationNumber: nil,
                gateInfo: nil,
                eventDescription: nil,
                venueType: nil,
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
                aiProcessed: nil,
                confidenceScore: nil,
                processingTimestamp: nil,
                modelUsed: nil,
                enrichmentCompleted: nil,
                backgroundColor: "rgb(138,43,226)",
                foregroundColor: nil,
                labelColor: nil
            ),
            passType: "Concert",
            showDateTime: true
        )
    }
    .padding()
}
