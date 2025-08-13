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
    @State private var showingSuccessView = false
    @State private var passAddedSuccessfully = false
    
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Header section with pass color theming
                    VStack(spacing: 8) {
                        if let metadata = savedPass.metadata {
                            // Custom header for detail view
                            VStack(spacing: 8) {
                                Text(savedPass.displayTitle)
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.white)
                            }
                            
                            // Use shared PassMetadataView for subtitle info
                            PassMetadataView(
                                metadata: metadata,
                                style: .detailView,
                                ticketCount: savedPass.passCount > 1 ? savedPass.passCount : nil
                            )
                        } else {
                            Text(savedPass.displayTitle)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.white)
                            
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
        .sheet(isPresented: $showingAddPassVC, onDismiss: {
            // Check if pass was added successfully
            if passAddedSuccessfully {
                showingSuccessView = true
                passAddedSuccessfully = false
            }
        }) {
            if let passVC = passViewController {
                PassKitView(passViewController: passVC, passAdded: $passAddedSuccessfully)
            }
        }
        .fullScreenCover(isPresented: $showingSuccessView) {
            PassAddedSuccessView(
                isPresented: $showingSuccessView,
                passCount: savedPass.passCount,
                onDismiss: {
                    // Dismiss the detail view and return to the main list
                    dismiss()
                }
            )
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
        return PassColorUtils.getPassColor(metadata: savedPass.metadata, passType: savedPass.passType)
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
