import SwiftUI
import PassKit
import RevenueCat
import MessageUI

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
    @State private var showingSuccessToast = false
    @State private var successToastMessage = ""
    @State private var addToWalletBounce = 0
    
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Use unified pass detail presentation
                    if let metadata = savedPass.metadata {
                        PassDetailPresentation(
                            metadata: metadata,
                            ticketCount: savedPass.passCount > 1 ? savedPass.passCount : nil,
                            isEmbedded: false
                        )
                    } else {
                        // Fallback for passes without metadata
                        VStack(spacing: 16) {
                            // Header without metadata
                            VStack(spacing: 8) {
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
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(
                                LinearGradient(
                                    colors: [passHeaderColor, passHeaderColor.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.large))
                            
                            // Basic pass info
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
                        }
                    }
                    
                }
                
                // PDF Preview section if available (collapsed by default)
                if let pdfData = savedPass.pdfData,
                   let tempPDFURL = createTempPDFURL(from: pdfData) {
                    CollapsiblePDFPreview(url: tempPDFURL)
                        .padding(.bottom, ThemeManager.Spacing.md)
                    
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
            }
            .safeAreaInset(edge: .bottom) {
                // Sticky bottom CTA using ThemeManager design system
                VStack(spacing: ThemeManager.Spacing.sm) {
                    // Status message
                    if let message = statusMessage, !message.isEmpty {
                        Text(message)
                            .font(ThemeManager.Typography.footnote)
                            .foregroundColor(hasError ? ThemeManager.Colors.error : ThemeManager.Colors.success)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    
                    // Primary CTA and secondary actions
                    if !savedPass.passDatas.isEmpty {
                        VStack(spacing: ThemeManager.Spacing.sm) {
                            // Primary CTA - Add to Wallet
                            Button {
                                ThemeManager.Haptics.light()
                                addToWalletBounce += 1
                                addPassToWallet()
                            } label: {
                                Label(savedPass.passCount > 1 ? "Add \(savedPass.passCount) to Wallet" : "Add to Wallet", 
                                      systemImage: "plus.rectangle.on.folder")
                                    .symbolEffect(.bounce, value: addToWalletBounce)
                            }
                            .themedPrimaryButton()
                            
                            // Secondary actions row
                            HStack(spacing: ThemeManager.Spacing.sm) {
                                // Report issue button
                                Button {
                                    ThemeManager.Haptics.selection()
                                    reportIssue()
                                } label: {
                                    Label("Report Issue", systemImage: "exclamationmark.bubble")
                                        .frame(maxWidth: .infinity)
                                }
                                .themedSecondaryButton()
                            }
                        }
                    }
                }
                .padding(.horizontal, ThemeManager.Spacing.md)
                .padding(.top, ThemeManager.Spacing.md)
                .padding(.bottom, ThemeManager.Spacing.md)
                .frame(maxWidth: .infinity)
                .background(.thinMaterial)
            }
            .background(
                LinearGradient(
                    colors: [passHeaderColor, passHeaderColor.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            
        }
        .sheet(isPresented: $showingAddPassVC, onDismiss: {
            // Reset state after dismissal
            passAddedSuccessfully = false
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
        .successToast(
            isPresented: $showingSuccessToast,
            message: successToastMessage
        )
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
        return PassColorUtils.getDarkenedPassColor(metadata: savedPass.metadata, passType: savedPass.passType)
    }
    
    private func reportIssue() {
        guard let pdfData = savedPass.pdfData else {
            print("No PDF data available for issue report")
            return
        }
        
        // Get the user's app user ID from RevenueCat
        let appUserID = Purchases.shared.appUserID
        
        // Create email subject and body
        let subject = "Add2Wallet Issue Report - Pass: \(savedPass.displayTitle)"
        let body = """
        I'm having an issue with a pass in Add2Wallet.
        
        Pass Details:
        - Title: \(savedPass.displayTitle)
        - Type: \(savedPass.passType)
        - Venue: \(savedPass.displayVenue)
        - Created: \(savedPass.createdAt)
        
        Issue Description:
        [Please describe the issue you're experiencing]
        
        ---
        Diagnostic Information:
        App User ID: \(appUserID)
        App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
        iOS Version: \(UIDevice.current.systemVersion)
        Device: \(UIDevice.current.model)
        Pass Count: \(savedPass.passCount)
        """
        
        // Generate a filename for the PDF attachment
        let fileName = "\(savedPass.displayTitle.replacingOccurrences(of: " ", with: "_"))_report.pdf"
        
        // Send notification to show support email
        let userInfo: [String: Any] = [
            "subject": subject,
            "body": body,
            "pdfData": pdfData,
            "fileName": fileName
        ]
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowSupportEmail"),
            object: nil,
            userInfo: userInfo
        )
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
