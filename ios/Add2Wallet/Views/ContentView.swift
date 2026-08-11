import SwiftUI
import UniformTypeIdentifiers
import PassKit
import PhotosUI
import RevenueCatUI
import MessageUI

struct ContentView: View {
    // Owned by the app, not by this view: see `Add2WalletApp`. The sheet is a
    // window onto an import that outlives it.
    @EnvironmentObject var viewModel: ContentViewModel
    @EnvironmentObject var passUsageManager: PassUsageManager
    // Read from the model, not held here: a reopened sheet is a new view and
    // would have missed the notification that announced the finished pass.
    private var passViewController: PKAddPassesViewController? {
        viewModel.pendingAddPassesController
    }
    @State private var showingAddPassVC = false
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
    @State private var showingPhotoPicker = false
    @State private var showingScanner = false
    @State private var selectedPhoto: PhotosPickerItem?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    #if DEBUG
    @StateObject private var debugDetector = DebugShakeDetector.shared
    #endif
    
    /// The import flow. It used to be a tab that ended by ejecting you into
    /// the other tab; it is a modal transaction, so it is presented as one.
    var body: some View {
        generatePassView
        #if DEBUG
            .debugRevenueCatOverlay(isPresented: $debugDetector.isDebugOverlayPresented)
        #endif
    }
    
    /// The balance, as a control that does what it looks like it does.
    ///
    /// It used to be a bare `Text`. The bar wraps any toolbar item in a capsule,
    /// so it arrived looking exactly like a button and did nothing when tapped —
    /// an affordance the platform handed us by accident rather than one we
    /// chose. There are only two honest ways out of that, and taking the chrome
    /// away is the worse one: "how do I get more credits?" is a real question
    /// with a real answer, and the paywall was previously reachable only by
    /// failing — by picking a file you had no credit to convert.
    private var creditBalanceButton: some View {
        Button {
            ThemeManager.Haptics.light()
            viewModel.showingPurchaseAlert = true
        } label: {
            Text("\(passUsageManager.remainingPasses) left")
                .font(ThemeManager.Typography.footnoteMonospaced)
                .foregroundColor(ThemeManager.Colors.textPrimary)
                // The capsule is sized to its content, and bare text gets
                // generous room above and below and almost none at the sides.
                .padding(.horizontal, ThemeManager.Spacing.sm)
        }
        .accessibilityLabel("\(passUsageManager.remainingPasses) credits left. Get more.")
        .accessibilityIdentifier("creditBalanceButton")
    }

    /// At zero the three source buttons are a trap: you pick a file, wait, and
    /// only then find out you cannot convert it. A count in the corner is
    /// reassurance when it reads nine and a blocker when it reads zero, so at
    /// zero it stops being a corner and says so.
    private var outOfCreditsBanner: some View {
        HStack(spacing: ThemeManager.Spacing.md) {
            // No explanatory second line: the empty state below already says a
            // ticket costs one credit, and saying it twice on one screen reads
            // as nagging rather than as helping.
            Text("You're out of credits")
                .font(ThemeManager.Typography.bodySemibold)
                .foregroundColor(ThemeManager.Colors.textPrimary)

            Spacer(minLength: ThemeManager.Spacing.sm)

            // Deliberately *not* `.borderedProminent`: that style draws a white
            // label whatever the tint, and this button sits on a card, so the
            // only tints that keep the label legible are the ones that vanish
            // against the card. Ink with an inverting foreground is the app's
            // own answer and it holds in both appearances.
            Button {
                ThemeManager.Haptics.light()
                viewModel.showingPurchaseAlert = true
            } label: {
                Text("Get credits")
                    .font(ThemeManager.Typography.footnote.weight(.semibold))
                    .foregroundColor(ThemeManager.Colors.onBrandPrimary)
                    .padding(.horizontal, ThemeManager.Spacing.md)
                    .padding(.vertical, ThemeManager.Spacing.sm)
                    .background(ThemeManager.Colors.brandPrimary, in: Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
        .padding(ThemeManager.Spacing.cardPadding)
        .background(
            ThemeManager.Colors.surfaceCardGrouped,
            in: RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.card)
        )
    }

    private var generatePassView: some View {
        ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ScrollView {
                    VStack(spacing: ThemeManager.Spacing.md) {
                    // Three ways in, given equal weight. No hero card: the
                    // sheet already said what this is.
                    if viewModel.selectedFileURL == nil && !viewModel.isProcessing {
                        if passUsageManager.remainingPasses == 0 && !passUsageManager.isLoadingBalance {
                            outOfCreditsBanner
                        }

                        ImportSourcePicker(
                            onFiles: { viewModel.selectFile() },
                            onPhotos: { showingPhotoPicker = true },
                            onScan: { showingScanner = true },
                            onPaste: { viewModel.handlePastedProviders($0) }
                        )
                    }
                    
                    if let url = viewModel.selectedFileURL, !viewModel.isProcessing {
                        VStack(alignment: .leading, spacing: ThemeManager.Spacing.md) {
                            if let details = viewModel.passMetadata {
                                // Unified pass detail presentation matching SavedPassDetailView
                                PassDetailPresentation(
                                    metadata: details,
                                    ticketCount: viewModel.ticketCount,
                                    isEmbedded: true,
                                    groupTitle: (viewModel.ticketCount ?? 1) > 1 ? details.groupName : nil
                                )
                                .transition(.opacity)
                            }
                            
                            if !viewModel.warnings.isEmpty {
                                WarningsView(warnings: viewModel.warnings)
                                    .transition(.opacity)
                            }
                            
                            // Collapsed source-file preview at the bottom
                            CollapsibleFilePreview(url: url)
                                .transition(.opacity)
                        }
                        .padding(.top, ThemeManager.Spacing.sm)
                    } else if viewModel.isProcessing {
                        ProgressView(contentViewModel: viewModel)
                    } else {
                        // Empty state
                        VStack(spacing: ThemeManager.Spacing.md) {
                            Image(systemName: "wallet.pass")
                                .font(.system(size: ThemeManager.IconSize.hero, weight: .thin))
                                .foregroundColor(ThemeManager.Colors.textTertiary)
                                .padding(.top, ThemeManager.Spacing.xl)
                            
                            Text("A ticket becomes an Apple Wallet pass. One credit each.")
                                .font(ThemeManager.Typography.footnote)
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
            .safeAreaInset(edge: .bottom) {
                // Sticky bottom CTA using ThemeManager design system
                if (viewModel.selectedFileURL != nil && !viewModel.isProcessing) || (viewModel.errorMessage != nil && !viewModel.errorMessage!.isEmpty) {
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
                                if passAddedSuccessfully {
                                    // Post-add state: pass was added to wallet
                                    Button {
                                        ThemeManager.Haptics.light()
                                        dismiss()
                                    } label: {
                                        Label("Done", systemImage: "checkmark")
                                    }
                                    .themedPrimaryButton()

                                    Button {
                                        ThemeManager.Haptics.selection()
                                        viewModel.clearSelection()
                                        passAddedSuccessfully = false
                                        viewModel.pendingAddPassesController = nil
                                    } label: {
                                        Label("New Pass", systemImage: "doc.badge.plus")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .themedSecondaryButton()
                                } else if passViewController != nil {
                                    // Primary CTA - full width, prominent
                                    Button {
                                        ThemeManager.Haptics.light()
                                        addToWalletBounce += 1
                                        showingAddPassVC = true
                                    } label: {
                                        Label("Add to Wallet", systemImage: "plus.rectangle.on.folder")
                                            .symbolEffect(.bounce, value: addToWalletBounce)
                                    }
                                    .themedPrimaryButton()

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
                                    }
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
                                    }
                                } else {
                                    // Error state: show cancel + retry + contact support
                                    HStack(spacing: ThemeManager.Spacing.sm) {
                                        Button(role: .cancel) {
                                            ThemeManager.Haptics.selection()
                                            viewModel.clearSelection()
                                        } label: {
                                            Label("Cancel", systemImage: "xmark")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .themedSecondaryButton()

                                        Button {
                                            ThemeManager.Haptics.light()
                                            viewModel.retryUpload()
                                        } label: {
                                            Label("Retry", systemImage: "arrow.clockwise")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .themedSecondaryButton()

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
                    .padding(.horizontal, ThemeManager.Spacing.lg)
                    .padding(.top, ThemeManager.Spacing.sm)
                    .padding(.bottom, ThemeManager.Spacing.md)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.medium))
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: -4)
                    .padding(.horizontal, ThemeManager.Spacing.xs)
                    .animation(ThemeManager.Animations.standard, value: viewModel.selectedFileURL)
                }
            }
            .task {
                await passUsageManager.forceRefreshBalance()
            }
            .onAppear {
                // Refresh balance every time tab appears
                Task {
                    await passUsageManager.forceRefreshBalance()
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
                        // Nil out old VC first so SwiftUI tears it down cleanly,
                        // then assign new one on next runloop tick
                        // The model already holds it; this only has to reset the
                        // presentation so SwiftUI tears the old one down.
                        _ = passVC
                        self.showingAddPassVC = false
                    }
                }
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("ResetPassUIState"),
                    object: nil,
                    queue: .main
                ) { _ in
                    self.showingAddPassVC = false
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
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("PassAlreadyInWallet"),
                    object: nil,
                    queue: .main
                ) { _ in
                    self.successToastMessage = "Already in your Wallet ✓"
                    self.showingSuccessToast = true
                }
            }
            .sheet(isPresented: Binding(
                get: { showingAddPassVC && passViewController != nil },
                set: { showingAddPassVC = $0 }
            ), onDismiss: {
                showingAddPassVC = false
                // If pass was added successfully, keep the flag true so the UI shows post-add buttons
                if !passAddedSuccessfully {
                    viewModel.pendingAddPassesController = nil
                }
                // Refresh balance when returning from Apple Wallet (sheet dismissal)
                Task {
                    await passUsageManager.forceRefreshBalance()
                }
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
                        // `clearSelection` already drops the held controller.
                        viewModel.clearSelection()
                    }
                )
            }
            .fullScreenCover(isPresented: $showingFullScreenPDF) {
                if let url = viewModel.selectedFileURL {
                    FullScreenFileView(url: url)
                }
            }
            .fileImporter(
                isPresented: $viewModel.showingDocumentPicker,
                allowedContentTypes: SupportedFile.contentTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        viewModel.handleSelectedDocument(url: url)
                    }
                case .failure(let error):
                    viewModel.errorMessage = "Error selecting file: \(error.localizedDescription)"
                    viewModel.hasError = true
                }
            }
            .photosPicker(
                isPresented: $showingPhotoPicker,
                selection: $selectedPhoto,
                matching: .images,
                photoLibrary: .shared()
            )
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                selectedPhoto = nil
                Task { await importPhoto(item) }
            }
            .fullScreenCover(isPresented: $showingScanner) {
                DocumentScanner { data in
                    showingScanner = false
                    guard let data, !data.isEmpty else { return }
                    viewModel.importFile(
                        data: data,
                        filename: SupportedFile.filename("scan", fallbackURL: nil, type: .pdf)
                    )
                }
                .ignoresSafeArea()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    creditBalanceButton
                }
            }
            .sheet(isPresented: $viewModel.showingPurchaseAlert) {
                PaywallView(displayCloseButton: true)
                    .onPurchaseCompleted { customerInfo in
                        print("✅ Purchase completed, refreshing VC balance...")
                        viewModel.purchaseCompletedPendingUpload = true
                        // RC already processed the purchase — just refresh VC balance once
                        Task {
                            await passUsageManager.forceRefreshBalance()
                        }
                    }
                    .onRestoreCompleted { customerInfo in
                        print("✅ Restore completed, refreshing balance...")
                        Task {
                            await passUsageManager.forceRefreshBalance()
                        }
                    }
                    .onDisappear {
                        Task { @MainActor in
                            if viewModel.purchaseCompletedPendingUpload {
                                viewModel.purchaseCompletedPendingUpload = false
                                // Balance should already be updated from onPurchaseCompleted
                                // but force one more refresh just in case
                                await passUsageManager.forceRefreshBalance()
                                // Bypass balance check — user just purchased
                                viewModel.isRetry = true
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
                        attachmentData: data["attachmentData"] as? Data ?? data["pdfData"] as? Data ?? Data(),
                        attachmentMIMEType: data["attachmentMIMEType"] as? String ?? "application/octet-stream",
                        fileName: data["fileName"] as? String ?? "document"
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
        } // End of ZStack
    }

    @MainActor
    private func importPhoto(_ item: PhotosPickerItem) async {
        // Keep the original bytes rather than re-encoding: HEIC/PNG/JPEG all go
        // to the backend as-is, and the extension has to match what we send.
        let type = item.supportedContentTypes.first { SupportedFile.isSupported($0) }
            ?? .jpeg
        do {
            guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
                viewModel.errorMessage = "Couldn't read that photo. Try a different one."
                viewModel.hasError = true
                return
            }
            viewModel.importFile(
                data: data,
                filename: SupportedFile.filename("photo", fallbackURL: nil, type: type)
            )
        } catch {
            viewModel.errorMessage = "Error loading photo: \(error.localizedDescription)"
            viewModel.hasError = true
        }
    }
}





#Preview("Pass Ready to Add") {
    // Create a ContentView with mock data showing a pass ready to be added
    ContentView()
        .environmentObject(PassUsageManager.shared)
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
        .environmentObject(PassUsageManager.shared)
}

#Preview("Processing State") {
    ContentView()
        .environmentObject(PassUsageManager.shared)
        .onAppear {
            // Simulate processing state
            NotificationCenter.default.post(
                name: NSNotification.Name("PreviewProcessingState"),
                object: nil,
                userInfo: nil
            )
        }
}
