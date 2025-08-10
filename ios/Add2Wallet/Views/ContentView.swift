import SwiftUI
import UniformTypeIdentifiers
import PassKit

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @State private var passViewController: PKAddPassesViewController?
    @State private var showingAddPassVC = false
    @State private var selectedTab = 0
    @State private var showingFullScreenPDF = false
    @Environment(\.modelContext) private var modelContext
    
    private var titleHeaderColor: Color {
        // First try to use actual pass colors from metadata
        if let metadata = viewModel.passMetadata {
            // Check if we have the actual pass colors
            if let backgroundColor = metadata.backgroundColor {
                return parseRGBColor(backgroundColor) ?? fallbackColorFromEventType(metadata)
            }
            return fallbackColorFromEventType(metadata)
        }
        
        // Final fallback to a default color
        return .blue
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            generatePassView
                .tabItem {
                    Label("Generate Pass", systemImage: "plus.circle")
                }
                .tag(0)
            
            SavedPassesView()
                .tabItem {
                    Label("My Passes", systemImage: "wallet.pass")
                }
                .tag(1)
        }
    }
    
    private var generatePassView: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("Add2Wallet")
                            .font(.largeTitle).fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("Convert PDFs to Apple Wallet passes")
                            .font(.subheadline).foregroundColor(.white.opacity(0.9))
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: [titleHeaderColor, titleHeaderColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    if let url = viewModel.selectedFileURL, !viewModel.isProcessing {
                        VStack(alignment: .leading, spacing: 12) {
                            PDFPreviewView(url: url)
                                .frame(height: 320)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))
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

                            if let details = viewModel.passMetadata {
                                // Split subtitle into three components
                                VStack(spacing: 8) {
                                    ThreeFieldSubtitleView(metadata: details)
                                        .transition(.opacity)
                                    
                                    PassDetailsView(metadata: details, ticketCount: viewModel.ticketCount)
                                        .transition(.opacity)
                                }
                            }
                            
                            if !viewModel.warnings.isEmpty {
                                WarningsView(warnings: viewModel.warnings)
                                    .transition(.opacity)
                            }
                        }
                        .padding(.top, 8)
                    } else if viewModel.isProcessing {
                        ProgressView(viewModel: viewModel)
                            .padding(.top, 40)
                    } else {
                        VStack(spacing: 12) {
                            Button(action: { viewModel.selectPDF() }) {
                                Label("Select PDF", systemImage: "doc.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            Text("Or use the Share Extension from any app")
                                .font(.caption).foregroundColor(.secondary)
                            Text("Open a PDF in Files, Safari, or any app and tap Share → Add to Wallet")
                                .font(.caption2).foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top, 24)
                    }
                    
                    Spacer(minLength: 80)
                    }
                    .padding()
                }

                // Fixed bottom action bar - only show when needed
                if viewModel.selectedFileURL != nil || viewModel.isProcessing || (viewModel.statusMessage != nil && !viewModel.statusMessage!.isEmpty) {
                    VStack(spacing: 8) {
                        if let message = viewModel.statusMessage, !message.isEmpty {
                            Text(message)
                                .font(.footnote)
                                .foregroundColor(viewModel.hasError ? .red : .green)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                        if let _ = viewModel.selectedFileURL, !viewModel.isProcessing {
                            HStack(spacing: 12) {
                                Button(role: .cancel) {
                                    viewModel.clearSelection()
                                } label: {
                                    Label("Cancel", systemImage: "xmark")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    if passViewController != nil {
                                        showingAddPassVC = true
                                    } else {
                                        viewModel.uploadSelected()
                                    }
                                } label: {
                                    if passViewController != nil {
                                        Label("Add to Wallet", systemImage: "plus.rectangle.on.folder")
                                            .frame(maxWidth: .infinity)
                                    } else {
                                        Label("Create Pass", systemImage: "wallet.pass")
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(passViewController != nil ? .green : .blue)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .background(.thinMaterial)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                // Set up model context for view model
                viewModel.setModelContext(modelContext)
                
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("PassReadyToAdd"),
                    object: nil,
                    queue: .main
                ) { notification in
                    if let userInfo = notification.userInfo,
                       let passVC = userInfo["passViewController"] as? PKAddPassesViewController {
                        self.passViewController = passVC
                    }
                }
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("ResetPassUIState"),
                    object: nil,
                    queue: .main
                ) { _ in
                    self.passViewController = nil
                    self.showingAddPassVC = false
                }
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("SwitchToGeneratePassTab"),
                    object: nil,
                    queue: .main
                ) { _ in
                    self.selectedTab = 0
                }
            }
            .sheet(isPresented: $showingAddPassVC) {
                if let passVC = passViewController {
                    PassKitView(passViewController: passVC)
                }
            }
            .fullScreenCover(isPresented: $showingFullScreenPDF) {
                if let url = viewModel.selectedFileURL {
                    FullScreenPDFView(url: url)
                }
            }
            .fileImporter(
                isPresented: $viewModel.showingDocumentPicker,
                allowedContentTypes: [UTType.pdf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        viewModel.handleSelectedDocument(url: url)
                    }
                case .failure(let error):
                    viewModel.statusMessage = "Error selecting PDF: \(error.localizedDescription)"
                    viewModel.hasError = true
                }
            }
        }
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
        let eventType = (metadata.eventType ?? "").lowercased()
        
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
            return .blue
        }
    }
}

struct PassKitView: UIViewControllerRepresentable {
    let passViewController: PKAddPassesViewController
    
    func makeUIViewController(context: Context) -> PKAddPassesViewController {
        return passViewController
    }
    
    func updateUIViewController(_ uiViewController: PKAddPassesViewController, context: Context) {
        // No updates needed
    }
}

// Progress view with non-linear animation
struct ProgressView: View {
    @ObservedObject var viewModel: ContentViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            // Progress bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(viewModel.progressMessage)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("\(Int(viewModel.progress * 100))%")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)
                        
                        // Progress
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [.blue, .purple]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * viewModel.progress, height: 8)
                            .animation(.easeInOut(duration: 0.3), value: viewModel.progress)
                    }
                }
                .frame(height: 8)
            }
            .padding(.horizontal)
            
            // Funny phrase below progress
            if !viewModel.funnyPhrase.isEmpty {
                Text(viewModel.funnyPhrase)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .italic()
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: viewModel.funnyPhrase)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
        .padding(.horizontal)
    }
}

import MapKit
import CoreLocation

struct MapAnnotationItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let title: String
}

struct PassDetailsView: View {
    let metadata: EnhancedPassMetadata
    let ticketCount: Int?
    private let keyWidth: CGFloat = 120
    @Environment(\.openURL) private var openURL
    @State private var coordinateFromAddress: CLLocationCoordinate2D?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Venue information above the map
            Group {
//                keyValueRow("Created", metadata.formattedCreatedAt)
                            
            }
            .font(.subheadline)
            .foregroundColor(.secondary)

            // Show map if we have address or coordinates
            if shouldShowMap {
                Map(coordinateRegion: .constant(mapRegion), annotationItems: finalCoordinate != nil ? [MapAnnotationItem(coordinate: finalCoordinate!, title: metadata.venueName ?? "Location")] : []) { annotation in
                    MapPin(coordinate: annotation.coordinate, tint: .red)
                }
                .mapStyle(.standard)
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3))
                )
                .onAppear {
                    geocodeAddressIfNeeded()
                }

                HStack(spacing: 8) {
                    Button {
                        if let coord = finalCoordinate {
                            openInAppleMaps(coordinate: coord, name: metadata.venueName ?? "Location")
                        }
                    } label: {
                        Label("Open in Apple Maps", systemImage: "map")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        if let coord = finalCoordinate {
                            openInGoogleMaps(coordinate: coord, name: metadata.venueName ?? "Location")
                        }
                    } label: {
                        Label("Open in Google Maps", systemImage: "map.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .font(.footnote)
                .padding(.top, 6)
            }
            
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
    
    private var shouldShowMap: Bool {
        return hasAddress || hasCoordinates
    }
    
    private var hasAddress: Bool {
        return metadata.venueAddress?.isEmpty == false
    }
    
    private var hasCoordinates: Bool {
        return metadata.latitude != nil && metadata.longitude != nil
    }
    
    private var finalCoordinate: CLLocationCoordinate2D? {
        // Prefer geocoded address coordinate, fallback to GPS coordinates
        if let coord = coordinateFromAddress {
            return coord
        } else if let lat = metadata.latitude, let lon = metadata.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return nil
    }
    
    private var mapRegion: MKCoordinateRegion {
        guard let coord = finalCoordinate else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), latitudinalMeters: 10000, longitudinalMeters: 10000)
        }
        // Zoom out more for better context - increased from default ~1000m to 3000m
        return MKCoordinateRegion(center: coord, latitudinalMeters: 3000, longitudinalMeters: 3000)
    }
    
    private func geocodeAddressIfNeeded() {
        // Only geocode if we have an address and don't already have a geocoded coordinate
        guard coordinateFromAddress == nil,
              let address = metadata.venueAddress,
              !address.isEmpty else {
            return
        }
        
        let geocoder = CLGeocoder()
        
        // Build full address string
        var fullAddress = address
        if let city = metadata.city, !city.isEmpty {
            fullAddress += ", " + city
        }
        if let stateCountry = metadata.stateCountry, !stateCountry.isEmpty {
            fullAddress += ", " + stateCountry
        }
        
        geocoder.geocodeAddressString(fullAddress) { placemarks, error in
            if let error = error {
                print("Geocoding error: \(error)")
                return
            }
            
            if let placemark = placemarks?.first,
               let location = placemark.location {
                DispatchQueue.main.async {
                    coordinateFromAddress = location.coordinate
                }
            }
        }
    }

    // Helper function to combine date and time intelligently
    private func combineDateTime(date: String?, time: String?) -> String? {
        let cleanDate = date?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTime = time?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let date = cleanDate, !date.isEmpty, let time = cleanTime, !time.isEmpty {
            return "\(date) at \(time)"
        } else if let date = cleanDate, !date.isEmpty {
            return date
        } else if let time = cleanTime, !time.isEmpty {
            return time
        } else {
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
                    .frame(width: keyWidth, alignment: .leading)
                Text(value)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func openInAppleMaps(coordinate: CLLocationCoordinate2D, name: String) {
        let query = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Location"
        if let url = URL(string: "http://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)&q=\(query)") {
            openURL(url)
        }
    }

    private func openInGoogleMaps(coordinate: CLLocationCoordinate2D, name: String) {
        let query = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Location"
        let appURL = URL(string: "comgooglemaps://?q=\(query)&center=\(coordinate.latitude),\(coordinate.longitude)&zoom=16")
        let webURL = URL(string: "https://maps.google.com/?q=\(query)&ll=\(coordinate.latitude),\(coordinate.longitude)&z=16")

        if let appURL = appURL {
            openURL(appURL) { accepted in
                if !accepted, let webURL = webURL {
                    openURL(webURL)
                }
            }
        } else if let webURL = webURL {
            openURL(webURL)
        }
    }
}

// MARK: - WarningsView
struct WarningsView: View {
    let warnings: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(warnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Warning")
                            .font(.headline)
                            .foregroundColor(.orange)
                        
                        Text(warning)
                            .font(.body)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer()
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - ThreeFieldSubtitleView
struct ThreeFieldSubtitleView: View {
    let metadata: EnhancedPassMetadata
    
    var body: some View {
        VStack(spacing: 12) {
            // Date and time field with calendar icon
            if let dateTimeString = combineDateTime(date: metadata.date, time: metadata.time) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                        .font(.subheadline)
                    Text(dateTimeString)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Spacer()
                }
            }
            
            // Venue field with map pin icon
            if let venue = metadata.venueName {
                HStack(spacing: 8) {
                    Image(systemName: "mappin")
                        .foregroundColor(.red)
                        .font(.subheadline)
                    Text(venue)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Spacer()
                }
            }
            
            // Event description field with caption font
            if let description = metadata.eventDescription ?? metadata.description {
                HStack(spacing: 8) {
                    Image(systemName: "text.alignleft")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // Helper function to combine date and time intelligently
    private func combineDateTime(date: String?, time: String?) -> String? {
        let cleanDate = date?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTime = time?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let date = cleanDate, !date.isEmpty, let time = cleanTime, !time.isEmpty {
            return "\(date) at \(time)"
        } else if let date = cleanDate, !date.isEmpty {
            return date
        } else if let time = cleanTime, !time.isEmpty {
            return time
        } else {
            return nil
        }
    }
}

#Preview {
    ContentView()
}
