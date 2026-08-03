import SwiftUI
import Combine
import UniformTypeIdentifiers
import PassKit
import SwiftData
import RevenueCat
import UIKit

@MainActor
class ContentViewModel: ObservableObject {
    @Published var isProcessing = false {
        didSet {
            if !isProcessing { endBackgroundTaskIfNeeded() }
        }
    }
    @Published var errorMessage: String?
    @Published var funnyPhrase: String = ""
    @Published var hasError = false
    @Published var errorCode: String?
    @Published var showingContactSupport = false
    @Published var showingDocumentPicker = false
    @Published var selectedFileURL: URL?
    @Published var passMetadata: EnhancedPassMetadata?
    @Published var ticketCount: Int? = nil
    @Published var warnings: [String] = []
    @Published var isRetry = false
    @Published var showingPurchaseAlert = false
    @Published var retryCount = 0
    @Published var showingRetryAlert = false
    @Published var isDemo = false
    @Published var purchaseCompletedPendingUpload = false
    
    // Store source-file data for error reporting
    private var currentSourceData: Data?
    private var currentSourceFileName: String?
    
    // Background task to keep processing when app is backgrounded
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    
    private let networkService = NetworkService()
    private var cancellables = Set<AnyCancellable>()
    private var notificationObservers: [NSObjectProtocol] = []
    private var modelContext: ModelContext?
    private let usageManager = PassUsageManager.shared
    
    // Progress handling - owned by ContentViewModel to persist across tab switches
    @Published var progressViewModel = ProgressViewModel()
    
    init() {
        // Listen for files shared through the Share Extension or "Open in".
        let sharedFileObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SharedFileReceived"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            print("🟢 ContentViewModel: SharedFileReceived notification received")
            if let userInfo = notification.userInfo,
               let filename = userInfo["filename"] as? String,
               let data = userInfo["data"] as? Data {
                print("🟢 ContentViewModel: Processing shared file: \(filename) (\(data.count) bytes)")
                Task { @MainActor in
                    self?.handleSharedFile(data: data, filename: filename)
                }
            } else {
                print("🔴 ContentViewModel: Invalid notification userInfo")
            }
        }
        notificationObservers.append(sharedFileObserver)

        // Pick up any file that arrived before we were ready (cold start race condition).
        if let pending = URLHandler.dequeuePendingFile() {
            print("🟢 ContentViewModel: Found pending file from before init: \(pending.filename)")
            handleSharedFile(data: pending.data, filename: pending.filename)
        }
        
        #if DEBUG
        // Listen for preview mock data notifications
        let previewDataObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("PreviewMockData"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let userInfo = notification.userInfo,
               let metadata = userInfo["metadata"] as? EnhancedPassMetadata {
                Task { @MainActor in
                    self?.setupPreviewState(with: metadata)
                }
            }
        }
        notificationObservers.append(previewDataObserver)
        
        let previewProcessingObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("PreviewProcessingState"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.setupProcessingPreviewState()
            }
        }
        notificationObservers.append(previewProcessingObserver)
        #endif
    }
    
    deinit {
        // Clean up cancellables to prevent memory leaks
        cancellables.removeAll()
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        notificationObservers.removeAll()
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func selectFile() {
        showingDocumentPicker = true
        hasError = false
    }

    // Compatibility for older tests/call sites.
    func selectPDF() {
        selectFile()
    }
    
    @MainActor
    func loadDemoFile() {
        // Load the demo PDF from app bundle
        guard let demoURL = Bundle.main.url(forResource: "torre_ifel", withExtension: "pdf") else {
            errorMessage = "Demo file not found. Please update the app."
            hasError = true
            return
        }
        
        do {
            let data = try Data(contentsOf: demoURL)
            
            // Create a temporary copy for preview
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempURL = tempDir.appendingPathComponent("Eiffel_Tower_Demo.pdf")
            try data.write(to: tempURL, options: [.atomic])
            
            // Set as selected file
            selectedFileURL = tempURL
            
            // Mark as demo mode
            isDemo = true
            
            // Reset any previous state
            NotificationCenter.default.post(name: NSNotification.Name("ResetPassUIState"), object: nil)
            passMetadata = nil
            warnings = []
            errorMessage = nil
            hasError = false
        } catch {
            errorMessage = "Error loading demo: \(error.localizedDescription)"
            hasError = true
        }
    }
    
    func handleSelectedDocument(url: URL) {
        // Copy the file into our sandbox for reliable preview/access
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Unable to access selected file"
            hasError = true
            return
        }

        do {
            let data = try Data(contentsOf: url)
            // Preserve original filename to help backend/AI infer better titles
            let originalName = url.lastPathComponent
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempURL = tempDir.appendingPathComponent(originalName)
            try data.write(to: tempURL, options: [.atomic])
            selectedFileURL = tempURL
            // Reset any previously generated pass UI state/metadata
            NotificationCenter.default.post(name: NSNotification.Name("ResetPassUIState"), object: nil)
            passMetadata = nil
            warnings = []
            errorMessage = nil
            hasError = false
        } catch {
            errorMessage = "Error reading file: \(error.localizedDescription)"
            hasError = true
        }
        url.stopAccessingSecurityScopedResource()
    }

    /// Entry point for files that arrive as raw bytes rather than a URL —
    /// the Photos picker and clipboard paste.
    func importFile(data: Data, filename: String) {
        handleSharedFile(data: data, filename: filename)
    }

    /// Pulls the first supported document off a paste (or drop) payload.
    func handlePastedProviders(_ providers: [NSItemProvider]) {
        guard let (provider, type) = firstSupportedItem(in: providers) else {
            errorMessage = "Nothing to paste — copy a PDF or an image first."
            hasError = true
            return
        }

        let suggestedName = provider.suggestedName
        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { [weak self] data, error in
            Task { @MainActor in
                guard let self else { return }
                guard let data, !data.isEmpty else {
                    self.errorMessage = "Couldn't read the pasted file: \(error?.localizedDescription ?? "unknown error")"
                    self.hasError = true
                    return
                }
                self.importFile(
                    data: data,
                    filename: SupportedFile.filename(suggestedName, fallbackURL: nil, type: type)
                )
            }
        }
    }

    private func firstSupportedItem(in providers: [NSItemProvider]) -> (NSItemProvider, UTType)? {
        let candidates = providers.flatMap { provider in
            provider.registeredTypeIdentifiers.compactMap { identifier -> (NSItemProvider, UTType)? in
                guard let type = SupportedFile.contentType(forIdentifier: identifier) else { return nil }
                return (provider, type)
            }
        }
        // A pasted PDF also advertises a preview image; the document wins.
        return candidates.first { $0.1.conforms(to: .pdf) } ?? candidates.first
    }

    @MainActor
    func uploadSelected() {
        guard let url = selectedFileURL else { return }
        
        // Check if user has passes remaining (unless it's a retry or demo)
        if !isRetry && !isDemo && !usageManager.canCreatePass() {
            showingPurchaseAlert = true
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            processFile(data: data, filename: url.lastPathComponent)
        } catch {
            errorMessage = "Error reading file: \(error.localizedDescription)"
            hasError = true
        }
    }
    
    @MainActor
    func retryUpload() {
        retryCount += 1
        
        // Show alert after second retry attempt
        if retryCount >= 2 {
            showingRetryAlert = true
        } else {
            isRetry = true
            uploadSelected()
        }
    }
    
    @MainActor
    func retryAfterAlert() {
        isRetry = true
        uploadSelected()
    }

    func clearSelection() {
        // Reset processing state
        isProcessing = false
        progressViewModel.stopProgress()
        
        if let url = selectedFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        selectedFileURL = nil
        errorMessage = nil
        hasError = false
        passMetadata = nil
        ticketCount = nil
        warnings = []
        isRetry = false
        retryCount = 0
        isDemo = false
        NotificationCenter.default.post(name: NSNotification.Name("ResetPassUIState"), object: nil)
    }
    
    private func handleSharedFile(data: Data, filename: String) {
        print("🟢 ContentViewModel: handleSharedFile called with \(filename)")
        // Create a temporary file for preview
        do {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempURL = tempDir.appendingPathComponent(filename)
            try data.write(to: tempURL, options: [.atomic])
            
            print("🟢 ContentViewModel: Created temporary file at: \(tempURL)")
            
            // Set the file URL for preview
            selectedFileURL = tempURL
            
            // Reset any previous state
            NotificationCenter.default.post(name: NSNotification.Name("ResetPassUIState"), object: nil)
            passMetadata = nil
            warnings = []
            errorMessage = nil
            hasError = false
            
            print("🟢 ContentViewModel: File ready for preview and manual upload")
            // Don't automatically process - let user hit "Create Pass" button
        } catch {
            print("🔴 ContentViewModel: Error handling shared file: \(error)")
            errorMessage = "Error handling shared file: \(error.localizedDescription)"
            hasError = true
        }
    }
    
    private func endBackgroundTaskIfNeeded() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
            print("🔄 Background task ended")
        }
    }
    
    // Compatibility entry point retained for existing integrations.
    func processPDF(data: Data, filename: String) {
        processFile(data: data, filename: filename)
    }

    func processFile(data: Data, filename: String) {
        isProcessing = true
        errorMessage = nil
        hasError = false
        errorCode = nil
        showingContactSupport = false
        
        // Request background execution time (~30s) so processing
        // survives the user switching to another app
        endBackgroundTaskIfNeeded()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "FileProcessing") { [weak self] in
            // Expiration handler — iOS is about to kill us
            print("⚠️ Background task expiring")
            self?.endBackgroundTaskIfNeeded()
        }
        print("🔄 Background task started (id: \(backgroundTaskID.rawValue))")
        
        // Start progress animation
        progressViewModel.startProgress()
        
        // Store the original file for potential error reporting.
        self.currentSourceData = data
        self.currentSourceFileName = filename
        
        // Pass consumption is now handled server-side
        // The server will deduct 1 PASS via RevenueCat API
        // unless this is a retry or demo

        // In screenshot mode, skip the upload entirely and use the pre-built demo pass
        if ScreenshotModeSeeder.isScreenshotMode() {
            progressViewModel.completeProgress()
            downloadAndOpenPass(passUrl: "/demo-pass")
            return
        }

        networkService.uploadFile(data: data, filename: filename, isRetry: isRetry, isDemo: isDemo)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.isProcessing = false
                        self?.progressViewModel.stopProgress()
                        self?.errorMessage = "Error: \(error.localizedDescription)"
                        self?.hasError = true
                        
                        // Check if this is a 4xx error to show contact support
                        if let networkError = error as? NetworkError,
                           let statusCode = networkError.statusCode,
                           statusCode >= 400 && statusCode < 500 {
                            self?.errorCode = "\(statusCode)"
                            self?.showingContactSupport = true
                        }
                    }
                },
                receiveValue: { [weak self] response in
                    guard let self else { return }
                    self.passMetadata = response.aiMetadata
                    self.ticketCount = response.ticketCount
                    self.warnings = response.warnings ?? []
                    if response.status == "completed", let passUrl = response.passUrl {
                        // Server done — snap progress to 100%
                        self.progressViewModel.completeProgress()
                        
                        // Update balance immediately from server response, then refresh
                        Task { @MainActor in
                            if let remaining = response.remainingPasses {
                                self.usageManager.remainingPasses = remaining
                            }
                            self.usageManager.passGenerated()
                        }
                        
                        // Show success toast for pass generation
                        let count = response.ticketCount ?? 1
                        let message = count > 1 ? "Generated \(count) passes!" : "Pass generated!"
                        NotificationCenter.default.post(
                            name: NSNotification.Name("PassGenerated"),
                            object: nil,
                            userInfo: ["message": message]
                        )
                        
                        if count > 1 {
                            self.downloadAndOpenMultiplePasses(passUrl: passUrl, count: count)
                        } else {
                            self.downloadAndOpenPass(passUrl: passUrl)
                        }
                    } else {
                        self.isProcessing = false
                        self.progressViewModel.stopProgress()
                        self.errorMessage = "Pass generation failed. Status: \(response.status)"
                        self.hasError = true
                    }
                    // Reset retry flag on success or failure
                    self.isRetry = false
                }
            )
            .store(in: &cancellables)
    }
    
    private func downloadAndOpenPass(passUrl: String) {
        errorMessage = ""
        
        networkService.downloadPass(from: passUrl)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.isProcessing = false
                        self?.progressViewModel.stopProgress()
                        self?.errorMessage = "Error downloading pass: \(error.localizedDescription)"
                        self?.hasError = true
                    }
                },
                receiveValue: { [weak self] passData in
                    self?.openPassInWallet(passData: passData)
                }
            )
            .store(in: &cancellables)
    }
    
    private func openPassInWallet(passData: Data) {
        do {
            // First validate the pass data has minimum size
            guard passData.count > 100 else {
                throw NSError(domain: "PassError", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Pass data is too small. The file may be corrupted."
                ])
            }
            
            // Save pass data to temporary file
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("pkpass")
            
            try passData.write(to: tempURL)
            
            // Create PKPass from the data with better error handling
            let pass: PKPass
            do {
                pass = try PKPass(data: passData)
            } catch let passError as NSError {
                // Check for specific PKPass errors
                if passError.domain == "PKPassKitErrorDomain" {
                    switch passError.code {
                    case 1:
                        throw NSError(domain: "PassError", code: 2, userInfo: [
                            NSLocalizedDescriptionKey: "The pass file format is invalid. Please try again or contact support."
                        ])
                    case 2:
                        throw NSError(domain: "PassError", code: 3, userInfo: [
                            NSLocalizedDescriptionKey: "The pass signature is invalid. Please try again."
                        ])
                    default:
                        throw NSError(domain: "PassError", code: 4, userInfo: [
                            NSLocalizedDescriptionKey: "Unable to read the pass file. Error: \(passError.localizedDescription)"
                        ])
                    }
                } else {
                    throw passError
                }
            }
            
            // Check if PassKit is available and pass can be added
            guard PKPassLibrary.isPassLibraryAvailable() else {
                errorMessage = "Apple Wallet is not available on this device"
                hasError = true
                return
            }
            
            // Save pass to persistent storage
            savePassToPersistentStorage(passData: passData)
            
            // Present the add pass view controller
            guard let passVC = PKAddPassesViewController(pass: pass) else {
                // PKAddPassesViewController returns nil when pass already exists in Wallet
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("PassAlreadyInWallet"),
                        object: nil,
                        userInfo: [:]
                    )
                }
                isProcessing = false
                progressViewModel.completeProgress()
                return
            }
            
            hasError = false
            
            // Store the pass data for the view to access
            NotificationCenter.default.post(
                name: NSNotification.Name("PassReadyToAdd"),
                object: nil,
                userInfo: ["passViewController": passVC, "tempURL": tempURL]
            )
            isProcessing = false
            progressViewModel.completeProgress()
            
        } catch let error as NSError {
            isProcessing = false
            progressViewModel.stopProgress()
            
            // Log detailed error for debugging
            print("❌ PKPass creation failed: \(error.domain) - Code: \(error.code) - \(error.localizedDescription)")
            print("❌ Pass data size: \(passData.count) bytes")
            
            // Provide user-friendly error message
            if error.domain == "PassError" {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = "Error creating pass: \(error.localizedDescription)"
            }
            hasError = true
        }
    }

    private func downloadAndOpenMultiplePasses(passUrl: String, count: Int) {
        errorMessage = ""

        let publishers: [AnyPublisher<(Int, Data), Error>] = (1...count).map { index in
            let urlWithQuery = "\(passUrl)?ticket_number=\(index)"
            return networkService
                .downloadPass(from: urlWithQuery)
                .map { (index, $0) }
                .eraseToAnyPublisher()
        }

        Publishers.MergeMany(publishers)
            .collect()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.isProcessing = false
                        self?.progressViewModel.stopProgress()
                        self?.errorMessage = "Error downloading passes: \(error.localizedDescription)"
                        self?.hasError = true
                    }
                },
                receiveValue: { [weak self] indexed in
                    let sorted = indexed.sorted { $0.0 < $1.0 }.map { $0.1 }
                    print("🎫 Downloaded \(indexed.count) pass files:")
                    for (index, data) in indexed {
                        print("  Pass \(index): \(data.count) bytes")
                    }
                    print("🎫 Sorted pass data sizes: \(sorted.map { $0.count })")
                    self?.openPassesInWallet(passDatas: sorted)
                }
            )
            .store(in: &cancellables)
    }

    private func openPassesInWallet(passDatas: [Data]) {
        print("🎫 Creating PKPass objects from \(passDatas.count) data blobs")
        // Save each pass to a temporary file (optional; PassKit can take Data directly)
        let passes: [PKPass] = passDatas.enumerated().compactMap { (index, data) in
            do {
                let pass = try PKPass(data: data)
                print("  Pass \(index + 1): \(pass.passTypeIdentifier) - \(pass.serialNumber)")
                return pass
            } catch {
                print("  ❌ Failed to create Pass \(index + 1): \(error.localizedDescription)")
                return nil
            }
        }

        guard !passes.isEmpty else {
            isProcessing = false
            progressViewModel.stopProgress()
            errorMessage = "Unable to read any generated pass files. Please try again or contact support."
            hasError = true
            return
        }

        guard PKPassLibrary.isPassLibraryAvailable() else {
            errorMessage = "Apple Wallet is not available on this device"
            hasError = true
            return
        }

        // Save all passes as one SavedPass entry
        saveMultiplePassesToPersistentStorage(passDatas: passDatas)

        guard let passVC = PKAddPassesViewController(passes: passes) else {
            isProcessing = false
            progressViewModel.stopProgress()
            errorMessage = "Unable to present these passes in Apple Wallet."
            hasError = true
            return
        }
        print("🎫 Created PKAddPassesViewController with \(passes.count) passes")

        errorMessage = nil
        hasError = false

        NotificationCenter.default.post(
            name: NSNotification.Name("PassReadyToAdd"),
            object: nil,
            userInfo: ["passViewController": passVC]
        )
        isProcessing = false
        progressViewModel.completeProgress()
    }

    
    #if DEBUG
    // MARK: - Preview Helpers
    
    @MainActor
    private func setupPreviewState(with metadata: EnhancedPassMetadata) {
        // Set up the view model state for preview
        self.passMetadata = metadata
        self.ticketCount = 2
        self.hasError = false
        self.isProcessing = false
        
        // Create a temporary PDF URL for display
        let tempDir = FileManager.default.temporaryDirectory
        let tempPDFURL = tempDir.appendingPathComponent("preview_ticket.pdf")
        
        // Create minimal valid PDF data for preview
        let pdfHeader = "%PDF-1.4\n"
        let pdfBody = "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
        let pdfFooter = "xref\n0 3\n0000000000 65535 f \ntrailer\n<< /Size 3 /Root 1 0 R >>\nstartxref\n9\n%%EOF"
        let pdfData = (pdfHeader + pdfBody + pdfFooter).data(using: .utf8) ?? Data()
        try? pdfData.write(to: tempPDFURL)
        
        self.selectedFileURL = tempPDFURL
        self.currentSourceFileName = "The_Weeknd_Tickets.pdf"
        
        // Simulate having a pass ready to add
        // Post notification to simulate pass ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Create a mock PKPass (note: in preview this won't actually work with real PKPass)
            // But we can simulate the UI state
            NotificationCenter.default.post(
                name: NSNotification.Name("PassReadyToAdd"),
                object: nil,
                userInfo: [
                    "passViewController": NSObject() // Mock object for preview
                ]
            )
        }
    }
    
    @MainActor  
    private func setupProcessingPreviewState() {
        // Set up processing state for preview
        self.isProcessing = true
        
        // Create a temporary PDF URL for display
        let tempDir = FileManager.default.temporaryDirectory
        let tempPDFURL = tempDir.appendingPathComponent("processing_ticket.pdf")
        
        // Create minimal valid PDF data
        let pdfHeader = "%PDF-1.4\n"
        let pdfBody = "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
        let pdfFooter = "xref\n0 3\n0000000000 65535 f \ntrailer\n<< /Size 3 /Root 1 0 R >>\nstartxref\n9\n%%EOF"
        let pdfData = (pdfHeader + pdfBody + pdfFooter).data(using: .utf8) ?? Data()
        try? pdfData.write(to: tempPDFURL)
        
        self.selectedFileURL = tempPDFURL
        self.currentSourceFileName = "Concert_Ticket.pdf"
    }
    #endif
    
    private func saveMultiplePassesToPersistentStorage(passDatas: [Data]) {
        guard let modelContext = modelContext,
              let metadata = passMetadata else {
            print("Cannot save passes: missing model context or metadata")
            return
        }
        
        // Preserve the original source bytes, filename, and type for later preview/support.
        let sourceURL = selectedFileURL
        let sourceData = sourceURL.flatMap { try? Data(contentsOf: $0) }
        let sourceFilename = sourceURL?.lastPathComponent
        let sourceTypeIdentifier = sourceFilename.flatMap { SupportedFile.contentType(for: $0)?.identifier }
        
        // Extract basic information for the SavedPass model
        let passType = metadata.eventType ?? "Pass"
        let title = metadata.title ?? metadata.eventName ?? "Untitled Pass"
        let eventDate = ScreenshotModeSeeder.isScreenshotMode() ? "2026-12-15" : metadata.date
        let venue = metadata.venueName
        let city = metadata.city
        
        // Create SavedPass instance with all passes
        let savedPass = SavedPass(
            passType: passType,
            title: title,
            eventDate: eventDate,
            venue: venue,
            city: city,
            passDatas: passDatas,
            pdfData: sourceData,
            sourceFilename: sourceFilename,
            sourceContentTypeIdentifier: sourceTypeIdentifier,
            metadata: metadata
        )
        
        // Insert into context
        modelContext.insert(savedPass)
        
        // Save context
        do {
            try modelContext.save()
            print("Successfully saved \(passDatas.count) passes: \(title)")
        } catch {
            print("Error saving passes: \(error)")
        }
    }
    
    private func savePassToPersistentStorage(passData: Data, ticketNumber: Int? = nil) {
        guard let modelContext = modelContext,
              let metadata = passMetadata else {
            print("Cannot save pass: missing model context or metadata")
            return
        }
        
        // Preserve the original source bytes, filename, and type for later preview/support.
        let sourceURL = selectedFileURL
        let sourceData = sourceURL.flatMap { try? Data(contentsOf: $0) }
        let sourceFilename = sourceURL?.lastPathComponent
        let sourceTypeIdentifier = sourceFilename.flatMap { SupportedFile.contentType(for: $0)?.identifier }
        
        // Extract basic information for the SavedPass model
        let passType = metadata.eventType ?? "Pass"
        let title = metadata.title ?? metadata.eventName ?? "Untitled Pass"
        let eventDate = ScreenshotModeSeeder.isScreenshotMode() ? "2026-12-15" : metadata.date
        let venue = metadata.venueName
        let city = metadata.city
        
        // Create title with ticket number if multiple passes
        let finalTitle = if let ticketNumber = ticketNumber, let ticketCount = ticketCount, ticketCount > 1 {
            "\(title) - Ticket \(ticketNumber)"
        } else {
            title
        }
        
        // Create SavedPass instance
        let savedPass = SavedPass(
            passType: passType,
            title: finalTitle,
            eventDate: eventDate,
            venue: venue,
            city: city,
            passDatas: [passData],
            pdfData: sourceData,
            sourceFilename: sourceFilename,
            sourceContentTypeIdentifier: sourceTypeIdentifier,
            metadata: metadata
        )
        
        // Insert into context
        modelContext.insert(savedPass)
        
        // Save context
        do {
            try modelContext.save()
            print("Successfully saved pass: \(finalTitle)")
        } catch {
            print("Error saving pass: \(error)")
        }
    }
    
    func contactSupport() {
        guard let errorCode,
              let attachmentData = currentSourceData,
              let fileName = currentSourceFileName else {
            print("Missing data for support email")
            return
        }

        let appUserID = Purchases.shared.appUserID
        let mimeType = SupportedFile.mimeType(for: fileName)
        let subject = "Pass Generation Error - Code \(errorCode)"
        let body = """
Hi Add2Wallet Support,

I encountered an error while trying to generate a pass from a file. Here are the details:

Error Code: \(errorCode)
Filename: \(fileName)
User ID: \(appUserID)
App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")

Please help me resolve this issue. The original file is attached to this email.

Thank you!
"""

        _ = createTempFile(data: attachmentData, fileName: fileName)

        if let mailURL = createMailURL(to: "andresboedo@gmail.com", subject: subject, body: body),
           UIApplication.shared.canOpenURL(mailURL) {
            UIApplication.shared.open(mailURL)
        }

        sendSupportEmail(
            subject: subject,
            body: body,
            attachmentData: attachmentData,
            mimeType: mimeType,
            fileName: fileName
        )
    }

    private func createTempFile(data: Data, fileName: String) -> URL? {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(URL(fileURLWithPath: fileName).lastPathComponent)

        do {
            try data.write(to: tempURL)
            return tempURL
        } catch {
            print("Error creating temporary attachment: \(error)")
            return nil
        }
    }

    private func createMailURL(to: String, subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = to
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }

    private func sendSupportEmail(
        subject: String,
        body: String,
        attachmentData: Data,
        mimeType: String,
        fileName: String
    ) {
        let userInfo: [AnyHashable: Any] = [
            "subject": subject,
            "body": body,
            "attachmentData": attachmentData,
            "attachmentMIMEType": mimeType,
            "fileName": fileName
        ]
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowSupportEmail"),
            object: nil,
            userInfo: userInfo
        )
    }
}
