import SwiftUI
import UniformTypeIdentifiers
import PassKit
import RevenueCatUI

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
                    VStack(spacing: 16) {
                    PassHeaderView(
                        title: "Add2Wallet",
                        subtitle: "Convert PDFs to Apple Wallet passes",
                        metadata: viewModel.passMetadata
                    )
                    
                    // Simple usage counter display (ugly for debugging)
                    HStack {
                        if usageManager.isLoadingBalance {
                            SwiftUI.ProgressView()
                                .scaleEffect(0.8)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                        } else {
                            Text("Passes Remaining: \(usageManager.remainingPasses)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.top, -8)
                    
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
                                    PassMetadataView(metadata: details, style: .contentView)
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
                                
                                // Show retry button if there was an error
                                if viewModel.hasError {
                                    Button {
                                        viewModel.retryUpload()
                                    } label: {
                                        Label("Retry", systemImage: "arrow.clockwise")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)
                                } else if passViewController != nil {
                                    Button {
                                        showingAddPassVC = true
                                    } label: {
                                        Label("Add to Wallet", systemImage: "plus.rectangle.on.folder")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                                } else {
                                    Button {
                                        viewModel.uploadSelected()
                                    } label: {
                                        Label("Create Pass", systemImage: "wallet.pass")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.blue)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationBarHidden(true)
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
            }
            .sheet(isPresented: $showingAddPassVC, onDismiss: {
                // Reset state after dismissal
                // Note: We can't reliably detect if the pass was actually added vs cancelled
                // Apple's PassKit doesn't provide this information
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
            // Don't automatically assume success - the user might have cancelled
            // We'll keep the success flow disabled by default
            parent.passAdded = false
            controller.dismiss(animated: true)
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
