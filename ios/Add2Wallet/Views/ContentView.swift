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
    
    private var titleHeaderColor: Color {
        return PassColorUtils.getPassColor(metadata: viewModel.passMetadata)
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
        #if DEBUG
        .debugRevenueCatOverlay(isPresented: $debugDetector.isDebugOverlayPresented)
        #endif
    }
    
    private var generatePassView: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: ThemeManager.Spacing.md) {
                    // Hero card stack for home screen - matches pass color when available
                    HeroCardStack(
                        remainingPasses: usageManager.remainingPasses,
                        isLoadingBalance: usageManager.isLoadingBalance,
                        passColor: viewModel.passMetadata != nil ? PassColorUtils.getPassColor(metadata: viewModel.passMetadata) : nil,
                        onSelectPDF: { viewModel.selectPDF() },
                        onSamplePDF: { viewModel.loadDemoFile() }
                    )
                    
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
                        ProgressView(viewModel: viewModel)
                            .padding(.top, 40)
                    } else {
                        // Empty state instructions
                        VStack(spacing: ThemeManager.Spacing.sm) {
                            Text("Or use the Share Extension from any app")
                                .font(ThemeManager.Typography.caption)
                                .foregroundColor(ThemeManager.Colors.textSecondary)
                            
                            Text("Open a PDF in Files, Safari, or any app and tap Share → Add to Wallet")
                                .font(ThemeManager.Typography.caption)
                                .foregroundColor(ThemeManager.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, ThemeManager.Spacing.md)
                        }
                        .padding(.top, ThemeManager.Spacing.sm)
                    }
                    
                    Spacer(minLength: 80)
                    }
                    .padding()
                }

            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .bottom) {
                // Sticky bottom CTA using ThemeManager design system
                if viewModel.selectedFileURL != nil || viewModel.isProcessing || (viewModel.statusMessage != nil && !viewModel.statusMessage!.isEmpty) {
                    VStack(spacing: ThemeManager.Spacing.sm) {
                        // Status message
                        if let message = viewModel.statusMessage, !message.isEmpty {
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
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.medium))
                    .animation(ThemeManager.Animations.standard, value: viewModel.selectedFileURL)
                }
            }
            .task {
                // Refresh balance when view appears
                await usageManager.refreshBalance()
            }
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
                    viewModel.statusMessage = "Error selecting PDF: \(error.localizedDescription)"
                    viewModel.hasError = true
                }
            }
            .sheet(isPresented: $viewModel.showingPurchaseAlert) {
                PaywallView { customerInfo in
                    // Purchase successful, refresh balance
                    print("Purchase completed, refreshing balance...")
                    Task {
                        await usageManager.refreshBalance()
                        // Retry the upload after successful purchase
                        await viewModel.uploadSelected()
                    }
                    return (userCancelled: false, error: nil)
                }
                .onDisappear {
                    // Always refresh balance when paywall closes
                    Task {
                        await usageManager.refreshBalance()
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
        }
    }
    
}

struct PassKitView: UIViewControllerRepresentable {
    let passViewController: PKAddPassesViewController
    @Binding var passAdded: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> PKAddPassesViewController {
        passViewController.delegate = context.coordinator
        return passViewController
    }
    
    func updateUIViewController(_ uiViewController: PKAddPassesViewController, context: Context) {
        // No updates needed
    }
    
    class Coordinator: NSObject, PKAddPassesViewControllerDelegate {
        let parent: PassKitView
        
        init(_ parent: PassKitView) {
            self.parent = parent
        }
        
        func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
            // PKAddPassesViewController doesn't provide reliable way to detect if pass was added
            // We'll use a simple heuristic: assume success since user went through the flow
            // The proper way would be to monitor PKPassLibrary notifications, but this is complex
            parent.passAdded = true
            controller.dismiss(animated: true)
        }
    }
}

struct MailComposeView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let pdfData: Data
    let fileName: String
    
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mailComposer = MFMailComposeViewController()
        mailComposer.mailComposeDelegate = context.coordinator
        mailComposer.setToRecipients(["andresboedo@gmail.com"])
        mailComposer.setSubject(subject)
        mailComposer.setMessageBody(body, isHTML: false)
        
        // Attach the PDF file
        mailComposer.addAttachmentData(pdfData, mimeType: "application/pdf", fileName: fileName)
        
        return mailComposer
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposeView
        
        init(_ parent: MailComposeView) {
            self.parent = parent
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            // Handle the result if needed
            switch result {
            case .sent:
                print("Email sent successfully")
            case .cancelled:
                print("Email cancelled")
            case .saved:
                print("Email saved as draft")
            case .failed:
                print("Email failed to send: \(error?.localizedDescription ?? "Unknown error")")
            @unknown default:
                print("Unknown email result")
            }
            
            parent.presentationMode.wrappedValue.dismiss()
        }
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
                                    gradient: Gradient(colors: [ThemeManager.Colors.brandPrimary, ThemeManager.Colors.brandSecondary]),
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

#Preview {
    ContentView()
}
