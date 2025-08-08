import SwiftUI
import UniformTypeIdentifiers
import PassKit

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @State private var passViewController: PKAddPassesViewController?
    @State private var showingAddPassVC = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("Add2Wallet")
                            .font(.largeTitle).fontWeight(.bold)
                        Text("Convert PDFs to Apple Wallet passes")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    
                    if let url = viewModel.selectedFileURL, !viewModel.isProcessing {
                        VStack(alignment: .leading, spacing: 12) {
                            PDFPreviewView(url: url)
                                .frame(height: 320)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))

                            if let details = viewModel.passMetadata {
                                PassDetailsView(metadata: details, ticketCount: viewModel.ticketCount)
                                    .transition(.opacity)
                            }
                        }
                        .padding(.top, 8)
                    } else if viewModel.isProcessing {
                        ProcessingView(phrase: viewModel.funnyPhrase)
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
                    
                    if let message = viewModel.statusMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(viewModel.hasError ? .red : .green)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 80)
                    }
                    .padding()
                }

                // Fixed bottom action bar
                VStack(spacing: 8) {
                    if let url = viewModel.selectedFileURL, !viewModel.isProcessing {
                        HStack(spacing: 12) {
                            Button(role: .cancel) {
                                viewModel.clearSelection()
                            } label: {
                                Label("Cancel", systemImage: "xmark")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                viewModel.uploadSelected()
                            } label: {
                                Label("Create Pass", systemImage: "wallet.pass")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    if passViewController != nil {
                        Button(action: { showingAddPassVC = true }) {
                            Label("Add to Wallet", systemImage: "plus.rectangle.on.folder")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .background(.thinMaterial)
            }
            .navigationBarHidden(true)
            .onAppear {
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
            }
            .sheet(isPresented: $showingAddPassVC) {
                if let passVC = passViewController {
                    PassKitView(passViewController: passVC)
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

// Inline ProcessingView to avoid scope issues during build
struct ProcessingView: View {
    let phrase: String

    @State private var rotateRing = false
    @State private var pulseCenter = false
    @State private var phraseOpacity: Double = 0.0

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(AngularGradient(
                        gradient: Gradient(colors: [
                            Color.blue, Color.purple, Color.pink, Color.orange, Color.blue
                        ]),
                        center: .center
                    ), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(rotateRing ? 360 : 0))
                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: rotateRing)

                Image(systemName: "wand.and.stars")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                    .scaleEffect(pulseCenter ? 1.06 : 0.94)
                    .shadow(color: .yellow.opacity(0.4), radius: pulseCenter ? 16 : 6)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseCenter)
            }

            Text(phrase)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .opacity(phraseOpacity)
                .onChange(of: phrase) { _ in
                    withAnimation(.easeInOut(duration: 0.25)) { phraseOpacity = 0.0 }
                    withAnimation(.easeInOut(duration: 0.25).delay(0.25)) { phraseOpacity = 1.0 }
                }
        }
        .onAppear {
            rotateRing = true
            pulseCenter = true
            phraseOpacity = 1.0
        }
    }
}

import MapKit

struct PassDetailsView: View {
    let metadata: EnhancedPassMetadata
    let ticketCount: Int?
    private let keyWidth: CGFloat = 120
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pass Details")
                .font(.headline)
            Group {
                keyValueRow("Type", metadata.eventType)
                keyValueRow("Title", metadata.title ?? metadata.eventName)
                keyValueRow("Description", metadata.description ?? metadata.eventDescription)
                keyValueRow("Date", metadata.date)
                keyValueRow("Time", metadata.time)
                keyValueRow("Venue", metadata.venueName)
                keyValueRow("Address", metadata.venueAddress)
                keyValueRow("City", metadata.city)
                keyValueRow("Region", metadata.stateCountry)
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

            if let lat = metadata.latitude, let lon = metadata.longitude {
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                Map {
                    Marker(metadata.venueName ?? "Venue", coordinate: coord)
                }
                .mapStyle(.standard)
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.3))
                )

                HStack(spacing: 8) {
                    Button {
                        openInAppleMaps(coordinate: coord, name: metadata.venueName ?? "Location")
                    } label: {
                        Label("Open in Apple Maps", systemImage: "map")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        openInGoogleMaps(coordinate: coord, name: metadata.venueName ?? "Location")
                    } label: {
                        Label("Open in Google Maps", systemImage: "map.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .font(.footnote)
                .padding(.top, 6)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

#Preview {
    ContentView()
}