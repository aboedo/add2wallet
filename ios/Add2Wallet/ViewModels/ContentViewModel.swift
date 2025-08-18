import SwiftUI
import Combine
import UniformTypeIdentifiers
import PassKit
import SwiftData
import RevenueCat
import UIKit

@MainActor
class ContentViewModel: ObservableObject {
    @Published var isProcessing = false
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
    @Published var progress: Double = 0.0
    @Published var progressMessage: String = ""
    @Published var isRetry = false
    @Published var showingPurchaseAlert = false
    @Published var retryCount = 0
    @Published var showingRetryAlert = false
    @Published var isDemo = false
    
    // Store PDF data for error reporting
    private var currentPDFData: Data?
    private var currentPDFFileName: String?
    
    private let networkService = NetworkService()
    private var cancellables = Set<AnyCancellable>()
    private var modelContext: ModelContext?
    private var phraseTimer: AnyCancellable?
    private var progressTimer: AnyCancellable?
    private let usageManager = PassUsageManager.shared
    private let phrases: [String] = [
        "Sharpening digital scissors ✂️",
        "Teaching the pass to be classy 🧣",
        "Taming barcodes in the wild 🦓",
        "Politely asking pixels to line up 📐",
        "Squeezing the PDF into your Wallet 💼",
        "Convincing Apple to like this pass 🍏",
        "Adding just a pinch of magic ✨",
        "Enrolling pass in wallet etiquette school 🎓",
        "Ironing out the manifest wrinkles 🧺",
        "Signing with a very fancy pen 🖋️",
    ]
    
    init() {
        // Listen for shared PDFs from the Share Extension
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SharedPDFReceived"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            print("🟢 ContentViewModel: SharedPDFReceived notification received")
            if let userInfo = notification.userInfo,
               let filename = userInfo["filename"] as? String,
               let data = userInfo["data"] as? Data {
                print("🟢 ContentViewModel: Processing shared PDF: \(filename) (\(data.count) bytes)")
                self?.handleSharedPDF(data: data, filename: filename)
            } else {
                print("🔴 ContentViewModel: Invalid notification userInfo")
            }
        }
        
        #if DEBUG
        // Listen for preview mock data notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("PreviewMockData"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let userInfo = notification.userInfo,
               let metadata = userInfo["metadata"] as? EnhancedPassMetadata {
                self?.setupPreviewState(with: metadata)
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("PreviewProcessingState"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.setupProcessingPreviewState()
        }
        #endif
    }
    
    deinit {
        // Clean up timers and cancellables to prevent memory leaks
        progressTimer?.cancel()
        progressTimer = nil
        phraseTimer?.cancel()
        phraseTimer = nil
        cancellables.removeAll()
        
        NotificationCenter.default.removeObserver(self)
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func selectPDF() {
        showingDocumentPicker = true
        hasError = false
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
        // Copy PDF into our sandbox for reliable preview/access
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
            errorMessage = "Error reading PDF: \(error.localizedDescription)"
            hasError = true
        }
        url.stopAccessingSecurityScopedResource()
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
            processPDF(data: data, filename: url.lastPathComponent)
        } catch {
            errorMessage = "Error reading PDF: \(error.localizedDescription)"
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
        // Stop any running animations/timers
        if isProcessing {
            stopProgressAnimation()
            stopPhraseCycling()
            isProcessing = false
        }
        
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
    
    private func handleSharedPDF(data: Data, filename: String) {
        print("🟢 ContentViewModel: handleSharedPDF called with \(filename)")
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
            
            print("🟢 ContentViewModel: PDF ready for preview and manual upload")
            // Don't automatically process - let user hit "Create Pass" button
        } catch {
            print("🔴 ContentViewModel: Error handling shared PDF: \(error)")
            errorMessage = "Error handling shared PDF: \(error.localizedDescription)"
            hasError = true
        }
    }
    
    func processPDF(data: Data, filename: String) {
        isProcessing = true
        errorMessage = nil
        startPhraseCycling()
        startProgressAnimation()
        hasError = false
        errorCode = nil
        showingContactSupport = false
        progress = 0.0
        
        // Store PDF data for potential error reporting
        self.currentPDFData = data
        self.currentPDFFileName = filename
        
        // Pass consumption is now handled server-side
        // The server will deduct 1 PASS via RevenueCat API
        // unless this is a retry or demo
        
        networkService.uploadPDF(data: data, filename: filename, isRetry: isRetry, isDemo: isDemo)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.isProcessing = false
                        self?.stopPhraseCycling()
                        self?.stopProgressAnimation()
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
                        // Refresh balance after successful pass generation
                        Task { @MainActor in
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
                        self.stopPhraseCycling()
                        self.stopProgressAnimation()
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
                        self?.stopPhraseCycling()
                        self?.stopProgressAnimation()
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
                throw NSError(domain: "PassError", code: 5, userInfo: [
                    NSLocalizedDescriptionKey: "Unable to create pass viewer. Please try again."
                ])
            }
            
            hasError = false
            
            // Store the pass data for the view to access
            NotificationCenter.default.post(
                name: NSNotification.Name("PassReadyToAdd"),
                object: nil,
                userInfo: ["passViewController": passVC, "tempURL": tempURL]
            )
            isProcessing = false
            stopPhraseCycling()
            completeProgress()
            
        } catch let error as NSError {
            isProcessing = false
            stopPhraseCycling()
            stopProgressAnimation()
            
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
                        self?.stopPhraseCycling()
                        self?.stopProgressAnimation()
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
        do {
            print("🎫 Creating PKPass objects from \(passDatas.count) data blobs")
            // Save each pass to a temporary file (optional; PassKit can take Data directly)
            let passes: [PKPass] = try passDatas.enumerated().compactMap { (index, data) in
                do {
                    let pass = try PKPass(data: data)
                    print("  Pass \(index + 1): \(pass.passTypeIdentifier) - \(pass.serialNumber)")
                    return pass
                } catch {
                    print("  ❌ Failed to create Pass \(index + 1): \(error.localizedDescription)")
                    return nil
                }
            }

            guard PKPassLibrary.isPassLibraryAvailable() else {
                errorMessage = "Apple Wallet is not available on this device"
                hasError = true
                return
            }

            // Save all passes as one SavedPass entry
            saveMultiplePassesToPersistentStorage(passDatas: passDatas)

            let passVC = PKAddPassesViewController(passes: passes)
            print("🎫 Created PKAddPassesViewController with \(passes.count) passes")

            errorMessage = nil
            hasError = false

            NotificationCenter.default.post(
                name: NSNotification.Name("PassReadyToAdd"),
                object: nil,
                userInfo: ["passViewController": passVC!]
            )
            isProcessing = false
            stopPhraseCycling()
            completeProgress()
        } catch {
            isProcessing = false
            stopPhraseCycling()
            stopProgressAnimation()
            errorMessage = "Error creating passes: \(error.localizedDescription)"
            hasError = true
        }
    }

    private func startPhraseCycling() {
        // Immediately set a phrase
        funnyPhrase = phrases.randomElement() ?? "Getting things ready..."
        phraseTimer?.cancel()
        
        // Coordinate phrase timer with progress timer to avoid overlapping UI updates
        // Use 2.0s interval (10x the progress timer) for better coordination
        phraseTimer = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                var next = phrases.randomElement() ?? "Almost there..."
                if next == funnyPhrase { next = phrases.shuffled().first ?? next }
                
                // Use animation to coordinate with progress updates
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.funnyPhrase = next
                }
            }
    }

    private func stopPhraseCycling() {
        phraseTimer?.cancel()
        phraseTimer = nil
        funnyPhrase = ""
    }
    
    private func startProgressAnimation() {
        progress = 0.0
        progressMessage = "Analyzing PDF..."
        
        // Define progress steps with non-linear timing
        let steps: [(Double, String, Double)] = [
            (0.15, "Analyzing PDF...", 3.0),
            (0.40, "Extracting barcodes...", 7.0),
            (0.65, "Processing metadata...", 8.0),
            (0.85, "Generating pass...", 7.0),
            (0.95, "Signing certificate...", 5.0)
        ]
        
        var currentStep = 0
        var elapsedTime: Double = 0
        let timerInterval: Double = 0.2 // Reduced from 0.1s to 0.2s for better performance
        
        progressTimer?.cancel()
        progressTimer = Timer.publish(every: timerInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                elapsedTime += timerInterval
                
                // Pre-calculate cumulative times to avoid repeated calculations
                var cumulativeTime: Double = 0
                for i in 0..<currentStep {
                    cumulativeTime += steps[i].2
                }
                
                var shouldUpdateMessage = false
                var newMessage = ""
                var newProgress = self.progress
                
                // Check if we should move to next step
                if currentStep < steps.count {
                    let (targetProgress, message, duration) = steps[currentStep]
                    
                    if elapsedTime >= cumulativeTime + duration {
                        // Move to next step
                        if currentStep < steps.count - 1 {
                            currentStep += 1
                            newMessage = steps[currentStep].1
                            shouldUpdateMessage = true
                        }
                    }
                    
                    // Calculate progress smoothly towards target
                    let startProgress = currentStep > 0 ? steps[currentStep - 1].0 : 0.0
                    let progressRange = targetProgress - startProgress
                    let stepElapsed = elapsedTime - cumulativeTime
                    let stepProgress = min(stepElapsed / duration, 1.0)
                    
                    newProgress = startProgress + (progressRange * stepProgress)
                }
                
                // Batch UI updates with animation to reduce redraws
                withAnimation(.easeInOut(duration: 0.15)) {
                    self.progress = newProgress
                    if shouldUpdateMessage {
                        self.progressMessage = newMessage
                    }
                }
                
                // Stop at 95% and wait for actual completion
                if newProgress >= 0.95 {
                    self.progressTimer?.cancel()
                    self.progressTimer = nil
                }
            }
    }
    
    private func stopProgressAnimation() {
        progressTimer?.cancel()
        progressTimer = nil
        progress = 0.0
        progressMessage = ""
    }
    
    private func completeProgress() {
        // Animate to 100% completion
        withAnimation(.easeInOut(duration: 0.3)) {
            progress = 1.0
            progressMessage = "Complete!"
        }
        
        // Reset after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.stopProgressAnimation()
        }
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
        self.currentPDFFileName = "The_Weeknd_Tickets.pdf"
        
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
        self.progress = 0.65
        self.progressMessage = "Analyzing ticket contents..."
        self.funnyPhrase = phrases.randomElement() ?? ""
        
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
        self.currentPDFFileName = "Concert_Ticket.pdf"
    }
    #endif
    
    private func saveMultiplePassesToPersistentStorage(passDatas: [Data]) {
        guard let modelContext = modelContext,
              let metadata = passMetadata else {
            print("Cannot save passes: missing model context or metadata")
            return
        }
        
        // Get the PDF data from the selected file
        var pdfData: Data? = nil
        if let pdfURL = selectedFileURL {
            pdfData = try? Data(contentsOf: pdfURL)
        }
        
        // Extract basic information for the SavedPass model
        let passType = metadata.eventType ?? "Pass"
        let title = metadata.title ?? metadata.eventName ?? "Untitled Pass"
        let eventDate = metadata.date
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
            pdfData: pdfData,
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
        
        // Get the PDF data from the selected file
        var pdfData: Data? = nil
        if let pdfURL = selectedFileURL {
            pdfData = try? Data(contentsOf: pdfURL)
        }
        
        // Extract basic information for the SavedPass model
        let passType = metadata.eventType ?? "Pass"
        let title = metadata.title ?? metadata.eventName ?? "Untitled Pass"
        let eventDate = metadata.date
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
            pdfData: pdfData,
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
        guard let errorCode = errorCode,
              let pdfData = currentPDFData,
              let fileName = currentPDFFileName else {
            print("Missing data for support email")
            return
        }
        
        // Get the user's app user ID from RevenueCat
        let appUserID = Purchases.shared.appUserID
        
        // Create email content
        let subject = "Pass Generation Error - Code \(errorCode)"
        let body = """
Hi Add2Wallet Support,

I encountered an error while trying to generate a pass from a PDF. Here are the details:

Error Code: \(errorCode)
PDF Filename: \(fileName)
User ID: \(appUserID)
App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")

Please help me resolve this issue. The original PDF is attached to this email.

Thank you!
"""
        
        // Create temporary file for PDF attachment
        let tempURL = createTempPDFFile(data: pdfData, fileName: fileName)
        
        // Open Mail app with pre-filled content
        if let mailURL = createMailURL(to: "andresboedo@gmail.com", subject: subject, body: body) {
            if UIApplication.shared.canOpenURL(mailURL) {
                UIApplication.shared.open(mailURL)
            }
        }
        
        // Also trigger MFMailComposeViewController as fallback
        sendSupportEmail(subject: subject, body: body, pdfData: pdfData, fileName: fileName)
    }
    
    private func createTempPDFFile(data: Data, fileName: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try data.write(to: tempURL)
            return tempURL
        } catch {
            print("Error creating temp PDF file: \(error)")
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
    
    private func sendSupportEmail(subject: String, body: String, pdfData: Data, fileName: String) {
        // Post notification to trigger MFMailComposeViewController from the view
        let userInfo: [AnyHashable: Any] = [
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
