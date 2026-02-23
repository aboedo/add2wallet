import SwiftUI
import UniformTypeIdentifiers
import PassKit
import RevenueCatUI
import MessageUI

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @StateObject private var usageManager = PassUsageManager.shared
    @State private var passViewController: PKAddPassesViewController?
    @State private var showingAddPassVC = false
    @State private var selectedTab = 0
    @State private var showingFullScreenPDF = false
    @State private var showingSuccessView = false
    @State private var passAddedSuccessfully = false
    @State private var addedPassCount = 1
    @State private var showingMailComposer = false
    @State private var mailComposerData: [AnyHashable: Any]?
    @State private var showingRetryAlert = false
    @State private var showingSuccessToast = false
    @State private var successToastMessage = ""
    @State private var addToWalletBounce = 0
    @State private var createPassBounce = 0
    @Environment(\.modelContext) private var modelContext
    
    #if DEBUG
    @StateObject private var debugDetector = DebugShakeDetector.shared
    #endif
    
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
        #if DEBUG
        .debugRevenueCatOverlay(isPresented: $debugDetector.isDebugOverlayPresented)
        #endif
    }
    
    private var generatePassView: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ScrollView {
                    VStack(spacing: ThemeManager.Spacing.md) {
                    // Hero card — hide while processing
                    if !viewModel.isProcessing {
                        HeroCardStack(
                            remainingPasses: usageManager.remainingPasses,
                            isLoadingBalance: usageManager.isLoadingBalance,
                            passColor: nil,
                            onSelectPDF: { viewModel.selectPDF() },
                            onSamplePDF: { viewModel.loadDemoFile() }
                        )
                    }
                    
                    if let url = viewModel.selectedFileURL, !viewModel.isProcessing {
                        VStack(alignment: .leading, spacing: ThemeManager.Spacing.md) {
                            if let details = viewModel.passMetadata {
                                // Unified pass detail presentation matching SavedPassDetailView
                                PassDetailPresentation(
                                    metadata: details,
                                    ticketCount: viewModel.ticketCount,
                                    isEmbedded: true
                                )
                                .transition(.opacity)
                            }
                            
                            if !viewModel.warnings.isEmpty {
                                WarningsView(warnings: viewModel.warnings)
                                    .transition(.opacity)
                            }
                            
                            // Collapsed PDF preview at the bottom
                            CollapsiblePDFPreview(url: url)
                                .transition(.opacity)
                        }
                        .padding(.top, ThemeManager.Spacing.sm)
                    } else if viewModel.isProcessing {
                        ProgressView(contentViewModel: viewModel)
                            .padding(.top, 40)
                    } else {
                        // Empty state
                        VStack(spacing: ThemeManager.Spacing.md) {
                            Image(systemName: "wallet.pass")
                                .font(.system(size: 64, weight: .thin))
                                .foregroundColor(ThemeManager.Colors.textTertiary)
                                .padding(.top, ThemeManager.Spacing.xl)
                            
                            Text("Open a PDF from Files to get started")
                                .font(ThemeManager.Typography.body)
                                .foregroundColor(ThemeManager.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                            
                            Button(action: {
                                ThemeManager.Haptics.selection()
                                viewModel.loadDemoFile()
                            }) {
                                Text("or try a demo")
                                    .font(ThemeManager.Typography.footnote)
                                    .foregroundColor(ThemeManager.Colors.brandPrimary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Spacer()
                    }
                    .padding()
                }

            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .bottom) {
                // Sticky bottom CTA using ThemeManager design system
                if viewModel.selectedFileURL != nil || viewModel.isProcessing || (viewModel.errorMessage != nil && !viewModel.errorMessage!.isEmpty) {
                    VStack(spacing: ThemeManager.Spacing.sm) {
                        // Status message
                        if let message = viewModel.errorMessage, !message.isEmpty {
                            Text(message)
                                .font(ThemeManager.Typography.footnote)
                                .foregroundColor(viewModel.hasError ? ThemeManager.Colors.error : ThemeManager.Colors.success)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                        
                        // Primary CTA and secondary actions
                        if let _ = viewModel.selectedFileURL, !viewModel.isProcessing {
                            VStack(spacing: ThemeManager.Spacing.sm) {
                                // Primary CTA - full width, prominent
                                if passViewController != nil {
                                    Button {
                                        ThemeManager.Haptics.light()
                                        addToWalletBounce += 1
                                        showingAddPassVC = true
                                    } label: {
                                        Label("Add to Wallet", systemImage: "plus.rectangle.on.folder")
                                            .symbolEffect(.bounce, value: addToWalletBounce)
                                    }
                                    .themedPrimaryButton()
                                } else if !viewModel.hasError {
                                    Button {
                                        ThemeManager.Haptics.light()
                                        createPassBounce += 1
                                        viewModel.uploadSelected()
                                    } label: {
                                        Label("Create Pass", systemImage: "wallet.pass")
                                            .symbolEffect(.bounce, value: createPassBounce)
                                    }
                                    .themedPrimaryButton()
                                }
                                
                                // Secondary actions row
                                HStack(spacing: ThemeManager.Spacing.sm) {
                                    Button(role: .cancel) {
                                        ThemeManager.Haptics.selection()
                                        viewModel.clearSelection()
                                    } label: {
                                        Label("Cancel", systemImage: "xmark")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .themedSecondaryButton()
                                    
                                    // Show retry button if there was an error
                                    if viewModel.hasError {
                                        Button {
                                            ThemeManager.Haptics.light()
                                            viewModel.retryUpload()
                                        } label: {
                                            Label("Retry", systemImage: "arrow.clockwise")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .themedSecondaryButton()
                                        
                                        // Show contact support button for 4xx errors
                                        if viewModel.showingContactSupport {
                                            Button {
                                                ThemeManager.Haptics.light()
                                                viewModel.contactSupport()
                                            } label: {
                                                Label("Contact Support", systemImage: "envelope")
                                                    .frame(maxWidth: .infinity)
                                            }
                                            .themedSecondaryButton()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, ThemeManager.Spacing.md)
                    .padding(.top, ThemeManager.Spacing.sm)
                    .padding(.bottom, ThemeManager.Spacing.md)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.medium))
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: -4)
                    .animation(ThemeManager.Animations.standard, value: viewModel.selectedFileURL)
                }
            }
            .task {
                await usageManager.forceRefreshBalance()
            }
            .onAppear {
                // Refresh balance every time tab appears
                Task {
                    await usageManager.forceRefreshBalance()
                }
                
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
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("ShowSupportEmail"),
                    object: nil,
                    queue: .main
                ) { notification in
                    if let userInfo = notification.userInfo {
                        self.mailComposerData = userInfo
                        if MFMailComposeViewController.canSendMail() {
                            self.showingMailComposer = true
                        }
                    }
                }
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("PassGenerated"),
                    object: nil,
                    queue: .main
                ) { notification in
                    if let userInfo = notification.userInfo,
                       let message = userInfo["message"] as? String {
                        self.successToastMessage = message
                        self.showingSuccessToast = true
                    }
                }
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
                    passCount: addedPassCount,
                    onDismiss: {
                        // Clear the current pass (like cancel button does)
                        viewModel.clearSelection()
                        passViewController = nil
                    }
                )
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
                    viewModel.errorMessage = "Error selecting PDF: \(error.localizedDescription)"
                    viewModel.hasError = true
                }
            }
            .sheet(isPresented: $viewModel.showingPurchaseAlert) {
                PaywallView { customerInfo in
                    print("✅ Purchase completed with customerInfo, refreshing balance...")
                    viewModel.purchaseCompletedPendingUpload = true
                    // customerInfo stream will trigger forceRefreshBalance automatically
                    return (userCancelled: false, error: nil)
                }
                .onDisappear {
                    Task { @MainActor in
                        if viewModel.purchaseCompletedPendingUpload {
                            viewModel.purchaseCompletedPendingUpload = false
                            viewModel.uploadSelected()
                        }
                    }
                }
            }
            .sheet(isPresented: $showingMailComposer) {
                if let data = mailComposerData {
                    MailComposeView(
                        subject: data["subject"] as? String ?? "",
                        body: data["body"] as? String ?? "",
                        pdfData: data["pdfData"] as? Data ?? Data(),
                        fileName: data["fileName"] as? String ?? "document.pdf"
                    )
                }
            }
            .alert("Having trouble with this file?", isPresented: $viewModel.showingRetryAlert) {
                Button("Try Again") {
                    viewModel.retryAfterAlert()
                }
                Button("Send to Support") {
                    viewModel.contactSupport()
                }
                Button("Cancel", role: .cancel) {
                    // Just dismiss
                }
            } message: {
                Text("It seems we're having trouble with this file. We'd love to get it to work! Please send us the file so we can test it and improve the app.")
            }
            .successToast(
                isPresented: $showingSuccessToast,
                message: successToastMessage
            )
            } // End of VStack
        } // End of ZStack
    }
    
}





#Preview("Pass Ready to Add") {
    // Create a ContentView with mock data showing a pass ready to be added
    ContentView()
        .onAppear {
            // Create sample pass metadata for preview
            let mockMetadata = EnhancedPassMetadata(
                eventType: "concert",
                eventName: "The Weeknd - After Hours Til Dawn Tour",
                title: "The Weeknd Concert",
                description: "Experience an unforgettable night of music",
                date: "2024-07-15",
                time: "8:00 PM",
                duration: "3 hours",
                venueName: "Madison Square Garden",
                venueAddress: "4 Pennsylvania Plaza",
                city: "New York",
                stateCountry: "NY, USA",
                latitude: 40.7505,
                longitude: -73.9934,
                organizer: "Live Nation",
                performerArtist: "The Weeknd",
                seatInfo: "Section 102, Row J, Seats 15-16",
                barcodeData: "WKND2024NYC071520",
                price: "$350.00",
                confirmationNumber: "CONF-2024-78945",
                gateInfo: "Gate A - West Entrance",
                eventDescription: "The Weeknd brings his record-breaking After Hours Til Dawn Tour to Madison Square Garden",
                venueType: "Arena",
                capacity: "20,000",
                website: "https://www.msg.com",
                phone: "+1 (212) 465-6741",
                nearbyLandmarks: ["Penn Station", "Empire State Building"],
                publicTransport: "Penn Station - LIRR, NJ Transit, Subway Lines 1,2,3,A,C,E",
                parkingInfo: "Multiple parking garages available within 2 blocks",
                ageRestriction: "All ages",
                dressCode: "Casual",
                weatherConsiderations: "Indoor venue - weather protected",
                amenities: ["Concessions", "Merchandise", "ATMs", "Restrooms"],
                accessibility: "ADA compliant with wheelchair accessible seating",
                aiProcessed: true,
                confidenceScore: 95,
                processingTimestamp: Date().ISO8601Format(),
                modelUsed: "gpt-4",
                enrichmentCompleted: true,
                backgroundColor: "rgb(139,69,19)",  // Saddle brown for The Weeknd aesthetic
                foregroundColor: "rgb(255,255,255)",
                labelColor: "rgb(255,223,186)",
                multipleEvents: nil,
                upcomingEvents: nil,
                venuePlaceId: nil,
                performerNames: nil,
                exhibitName: nil,
                hasAssignedSeating: nil,
                eventUrls: nil
            )
            
            // Set up the preview state
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Access the ContentViewModel to set up preview state
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let rootView = window.rootViewController?.view,
                   let hostingController = window.rootViewController as? UIHostingController<ContentView> {
                    // Note: This is a simplified approach for preview
                    // In a real scenario, we'd need to properly inject the view model
                }
                
                // Post notifications to simulate the state
                NotificationCenter.default.post(
                    name: NSNotification.Name("PreviewMockData"),
                    object: nil,
                    userInfo: ["metadata": mockMetadata]
                )
            }
        }
        .preferredColorScheme(.dark) // Shows better with pass colors
}

#Preview("Empty State") {
    ContentView()
}

#Preview("Processing State") {
    ContentView()
        .onAppear {
            // Simulate processing state
            NotificationCenter.default.post(
                name: NSNotification.Name("PreviewProcessingState"),
                object: nil,
                userInfo: nil
            )
        }
}
