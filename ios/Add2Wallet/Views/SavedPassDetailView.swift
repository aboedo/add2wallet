import SwiftUI
import PassKit

struct SavedPassDetailView: View {
    let savedPass: SavedPass
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddPassVC = false
    @State private var passViewController: PKAddPassesViewController?
    @State private var statusMessage: String?
    @State private var hasError = false
    @State private var showingFullScreenPDF = false
    
    private func combineDateTime(date: String?, time: String?) -> String? {
        let cleanDate = date?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTime = time?.trimmingCharacters(in: .whitespacesAndNewlines)
        if (cleanDate?.isEmpty ?? true) && (cleanTime?.isEmpty ?? true) { return nil }
        
        let cal = Calendar.autoupdatingCurrent
        
        // Parse fixed-format date
        var dateObj: Date?
        if let ds = cleanDate, !ds.isEmpty {
            let iso = DateFormatter()
            iso.calendar = cal
            iso.locale = Locale(identifier: "en_US_POSIX")
            iso.dateFormat = "yyyy-MM-dd"
            dateObj = iso.date(from: ds)
        }
        
        // Parse fixed-format time
        var timeComponents: DateComponents?
        if let ts = cleanTime, !ts.isEmpty {
            let tf = DateFormatter()
            tf.calendar = cal
            tf.locale = Locale(identifier: "en_US_POSIX")
            tf.dateFormat = "HH:mm"
            if let tDate = tf.date(from: ts) {
                timeComponents = cal.dateComponents([.hour, .minute, .second], from: tDate)
            }
        }
        
        // Format combined output in user locale
        let output = DateFormatter()
        output.calendar = cal
        output.locale = .autoupdatingCurrent
        output.dateStyle = (dateObj != nil) ? .medium : .none
        output.timeStyle = (timeComponents != nil) ? .short : .none
        output.doesRelativeDateFormatting = true
        
        if let d = dateObj, let t = timeComponents,
           let combined = cal.date(bySettingHour: t.hour ?? 0,
                                   minute: t.minute ?? 0,
                                   second: t.second ?? 0,
                                   of: d) {
            return output.string(from: combined)
        }
        
        if let d = dateObj {
            return output.string(from: d)
        }
        
        if let t = timeComponents {
            let today = cal.startOfDay(for: Date())
            if let dt = cal.date(bySettingHour: t.hour ?? 0,
                                 minute: t.minute ?? 0,
                                 second: t.second ?? 0,
                                 of: today) {
                output.dateStyle = .none
                output.timeStyle = .short
                return output.string(from: dt)
            }
        }
        
        return nil
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Header section with pass color theming
                    VStack(spacing: 8) {
                        // Date and time field with calendar icon
                        if let metadata = savedPass.metadata, let dateTimeString = combineDateTime(date: metadata.date, time: metadata.time) {
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
                        
                        Text(savedPass.displayTitle)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                        
                        if let metadata = savedPass.metadata {
                            SavedPassThreeFieldSubtitleView(savedPass: savedPass)
                        } else {
                            Text(savedPass.displaySubtitle)
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                        }
                        
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    
                    // Pass details section
                    if let metadata = savedPass.metadata {
                        PassDetailsView(metadata: metadata, ticketCount: nil)
                            .transition(.opacity)
                    } else {
                        // Fallback if detailed metadata is not available
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Pass Information")
                                .font(.headline)
                            
                            Group {
                                keyValueRow("Type", savedPass.passType.capitalized)
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }
                    
                }
                
                // PDF Preview section if available
                if let pdfData = savedPass.pdfData {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Original PDF")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        // Create a temporary URL for the PDF preview
                        if let tempPDFURL = createTempPDFURL(from: pdfData) {
                            PDFPreviewView(url: tempPDFURL)
                                .frame(height: 250)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.secondary.opacity(0.2))
                                )
                                .padding(.horizontal)
                                .onTapGesture {
                                    showingFullScreenPDF = true
                                }
                                .overlay(
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Spacer()
                                            Label("Tap to view full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                                                .font(.caption)
                                                .padding(8)
                                                .background(.ultraThinMaterial)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                .padding(8)
                                        }
                                    }
                                )
                        }
                    }
                    .padding(.bottom)
                    Spacer(minLength: 80)

                }
                
                
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                if !savedPass.passDatas.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(savedPass.passCount > 1 ? "Add \(savedPass.passCount) to Wallet" : "Add to Wallet") {
                            addPassToWallet()
                        }
                        .fontWeight(.medium)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Status message at bottom
                if let message = statusMessage, !message.isEmpty {
                    VStack(spacing: 8) {
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(hasError ? .red : .green)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .background(.thinMaterial)
                }
            }
            .background(
                LinearGradient(
                    colors: [passHeaderColor.opacity(0.6), passHeaderColor],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            
        }
        .sheet(isPresented: $showingAddPassVC) {
            if let passVC = passViewController {
                PassKitView(passViewController: passVC)
            }
        }
        .fullScreenCover(isPresented: $showingFullScreenPDF) {
            if let pdfData = savedPass.pdfData,
               let tempPDFURL = createTempPDFURL(from: pdfData) {
                FullScreenPDFView(url: tempPDFURL)
            }
        }
    }
    
    private func createTempPDFURL(from data: Data) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent("\(savedPass.id).pdf")
        
        do {
            try data.write(to: tempURL)
            return tempURL
        } catch {
            print("Error creating temporary PDF file: \(error)")
            return nil
        }
    }
    
    @ViewBuilder
    private func keyValueRow(_ key: String, _ value: String?) -> some View {
        if let value = value, !value.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Text("\(key):")
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .frame(width: 120, alignment: .leading)
                Text(value)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func addPassToWallet() {
        guard !savedPass.passDatas.isEmpty else {
            statusMessage = "Pass data not available"
            hasError = true
            return
        }
        
        do {
            if savedPass.passDatas.count == 1 {
                // Single pass
                let pass = try PKPass(data: savedPass.passDatas[0])
                
                guard PKPassLibrary.isPassLibraryAvailable() else {
                    statusMessage = "Apple Wallet is not available on this device"
                    hasError = true
                    return
                }
                
                passViewController = PKAddPassesViewController(pass: pass)
            } else {
                // Multiple passes
                let passes = try savedPass.passDatas.map { try PKPass(data: $0) }
                
                guard PKPassLibrary.isPassLibraryAvailable() else {
                    statusMessage = "Apple Wallet is not available on this device"
                    hasError = true
                    return
                }
                
                passViewController = PKAddPassesViewController(passes: passes)
            }
            
            showingAddPassVC = true
            hasError = false
            
        } catch {
            statusMessage = "Error loading pass: \(error.localizedDescription)"
            hasError = true
        }
    }
    
    private var passHeaderColor: Color {
        // First try to use actual pass colors from metadata
        if let metadata = savedPass.metadata {
            // Check if we have the actual pass colors
            if let backgroundColor = metadata.backgroundColor {
                return parseRGBColor(backgroundColor) ?? fallbackColorFromEventType(metadata)
            }
            return fallbackColorFromEventType(metadata)
        }
        
        // Final fallback to basic pass type
        return fallbackColorFromPassType(savedPass.passType)
    }
    
    private func parseRGBColor(_ rgbString: String) -> Color? {
        // Parse rgb(r,g,b) format
        let pattern = #"rgb\((\d+),\s*(\d+),\s*(\d+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: rgbString, range: NSRange(rgbString.startIndex..., in: rgbString)) else {
            return nil
        }
        
        let rRange = Range(match.range(at: 1), in: rgbString)!
        let gRange = Range(match.range(at: 2), in: rgbString)!
        let bRange = Range(match.range(at: 3), in: rgbString)!
        
        guard let r = Double(String(rgbString[rRange])),
              let g = Double(String(rgbString[gRange])),
              let b = Double(String(rgbString[bRange])) else {
            return nil
        }
        
        return Color(red: r/255.0, green: g/255.0, blue: b/255.0)
    }
    
    private func fallbackColorFromEventType(_ metadata: EnhancedPassMetadata) -> Color {
        let eventType = (metadata.eventType ?? savedPass.passType).lowercased()
        
        switch eventType {
        case let type where type.contains("museum"):
            return .brown
        case let type where type.contains("concert") || type.contains("music"):
            return .purple
        case let type where type.contains("event") || type.contains("festival"):
            return .orange
        case let type where type.contains("flight") || type.contains("airline"):
            return .blue
        case let type where type.contains("movie") || type.contains("cinema"):
            return .red
        case let type where type.contains("sport") || type.contains("game"):
            return .green
        case let type where type.contains("transit") || type.contains("train") || type.contains("bus"):
            return .cyan
        case let type where type.contains("theatre") || type.contains("theater"):
            return .indigo
        default:
            return .gray
        }
    }
    
    private func fallbackColorFromPassType(_ passType: String) -> Color {
        switch passType.lowercased() {
        case let type where type.contains("evt"):
            return .orange
        case let type where type.contains("concert"):
            return .purple
        case let type where type.contains("flight"):
            return .blue
        case let type where type.contains("movie"):
            return .red
        case let type where type.contains("sport"):
            return .green
        case let type where type.contains("transit"):
            return .cyan
        default:
            return .gray
        }
    }
}

struct FullScreenPDFView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            PDFPreviewView(url: url)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                        .fontWeight(.medium)
                    }
                }
                .edgesIgnoringSafeArea(.bottom)
        }
    }
}

// MARK: - SavedPassThreeFieldSubtitleView
struct SavedPassThreeFieldSubtitleView: View {
    let savedPass: SavedPass
    
    var body: some View {
        VStack(spacing: 8) {
            
            if let metadata = savedPass.metadata {
                
                
                // Event description field with caption font
                if let description = metadata.eventDescription ?? metadata.description {
                    HStack(spacing: 8) {
                        Image(systemName: "text.alignleft")
                            .foregroundColor(.white.opacity(0.7))
                            .font(.caption)
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(.bottom)
                }
                
                // Venue field with map pin icon
                if let venue = metadata.venueName {
                    VStack(alignment: .leading) {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin")
                                .foregroundColor(.white.opacity(0.9))
                                .font(.subheadline)
                            Text(venue)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                        }
                        if let address = metadata.venueAddress, let city = metadata.city, let country = metadata.stateCountry {
                            Text("\(address), \(city), \(country)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                        }
                    }
                }
                if savedPass.passCount > 1 {
                    HStack {
                        Text("\(savedPass.passCount) tickets")
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
    
    let samplePass = SavedPass(
        passType: "Concert",
        title: "Taylor Swift Eras Tour",
        eventDate: "December 15, 2024",
        venue: "Madison Square Garden",
        city: "New York, NY",
        metadata: sampleMetadata
    )
    
    SavedPassDetailView(savedPass: samplePass)
}
