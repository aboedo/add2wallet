import SwiftUI
import Combine
import UniformTypeIdentifiers
import PassKit
import SwiftData

class ContentViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var statusMessage: String?
    @Published var funnyPhrase: String = ""
    @Published var hasError = false
    @Published var showingDocumentPicker = false
    @Published var selectedFileURL: URL?
    @Published var passMetadata: EnhancedPassMetadata?
    @Published var ticketCount: Int? = nil
    @Published var warnings: [String] = []
    @Published var progress: Double = 0.0
    @Published var progressMessage: String = ""
    
    private let networkService = NetworkService()
    private var cancellables = Set<AnyCancellable>()
    private var modelContext: ModelContext?
    private var phraseTimer: AnyCancellable?
    private var progressTimer: AnyCancellable?
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
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func selectPDF() {
        showingDocumentPicker = true
        hasError = false
    }
    
    func handleSelectedDocument(url: URL) {
        // Copy PDF into our sandbox for reliable preview/access
        guard url.startAccessingSecurityScopedResource() else {
            statusMessage = "Unable to access selected file"
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
            statusMessage = nil
            hasError = false
        } catch {
            statusMessage = "Error reading PDF: \(error.localizedDescription)"
            hasError = true
        }
        url.stopAccessingSecurityScopedResource()
    }

    func uploadSelected() {
        guard let url = selectedFileURL else { return }
        do {
            let data = try Data(contentsOf: url)
            processPDF(data: data, filename: url.lastPathComponent)
        } catch {
            statusMessage = "Error reading PDF: \(error.localizedDescription)"
            hasError = true
        }
    }

    func clearSelection() {
        if let url = selectedFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        selectedFileURL = nil
        statusMessage = nil
        hasError = false
        passMetadata = nil
        ticketCount = nil
        warnings = []
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
            statusMessage = nil
            hasError = false
            
            print("🟢 ContentViewModel: PDF ready for preview and manual upload")
            // Don't automatically process - let user hit "Create Pass" button
        } catch {
            print("🔴 ContentViewModel: Error handling shared PDF: \(error)")
            statusMessage = "Error handling shared PDF: \(error.localizedDescription)"
            hasError = true
        }
    }
    
    func processPDF(data: Data, filename: String) {
        isProcessing = true
        statusMessage = nil
        startPhraseCycling()
        startProgressAnimation()
        hasError = false
        progress = 0.0
        
        networkService.uploadPDF(data: data, filename: filename)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.isProcessing = false
                        self?.stopPhraseCycling()
                        self?.stopProgressAnimation()
                        self?.statusMessage = "Error: \(error.localizedDescription)"
                        self?.hasError = true
                    }
                },
                receiveValue: { [weak self] response in
                    guard let self else { return }
                    self.passMetadata = response.aiMetadata
                    self.ticketCount = response.ticketCount
                    self.warnings = response.warnings ?? []
                    if response.status == "completed", let passUrl = response.passUrl {
                        let count = response.ticketCount ?? 1
                        if count > 1 {
                            self.downloadAndOpenMultiplePasses(passUrl: passUrl, count: count)
                        } else {
                            self.downloadAndOpenPass(passUrl: passUrl)
                        }
                    } else {
                        self.isProcessing = false
                        self.stopPhraseCycling()
                        self.stopProgressAnimation()
                        self.statusMessage = "Pass generation failed. Status: \(response.status)"
                        self.hasError = true
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    private func downloadAndOpenPass(passUrl: String) {
        statusMessage = ""
        
        networkService.downloadPass(from: passUrl)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.isProcessing = false
                        self?.stopPhraseCycling()
                        self?.stopProgressAnimation()
                        self?.statusMessage = "Error downloading pass: \(error.localizedDescription)"
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
            // Save pass data to temporary file
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("pkpass")
            
            try passData.write(to: tempURL)
            
            // Create PKPass from the data
            let pass = try PKPass(data: passData)
            
            // Check if PassKit is available and pass can be added
            guard PKPassLibrary.isPassLibraryAvailable() else {
                statusMessage = "Apple Wallet is not available on this device"
                hasError = true
                return
            }
            
            // Save pass to persistent storage
            savePassToPersistentStorage(passData: passData)
            
            // Present the add pass view controller
            let passVC = PKAddPassesViewController(pass: pass)
            
            hasError = false
            
            // Store the pass data for the view to access
            NotificationCenter.default.post(
                name: NSNotification.Name("PassReadyToAdd"),
                object: nil,
                userInfo: ["passViewController": passVC!, "tempURL": tempURL]
            )
            isProcessing = false
            stopPhraseCycling()
            completeProgress()
            
        } catch {
            isProcessing = false
            stopPhraseCycling()
            stopProgressAnimation()
            statusMessage = "Error creating pass: \(error.localizedDescription)"
            hasError = true
        }
    }

    private func downloadAndOpenMultiplePasses(passUrl: String, count: Int) {
        statusMessage = "Downloading passes..."

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
                        self?.statusMessage = "Error downloading passes: \(error.localizedDescription)"
                        self?.hasError = true
                    }
                },
                receiveValue: { [weak self] indexed in
                    let sorted = indexed.sorted { $0.0 < $1.0 }.map { $0.1 }
                    self?.openPassesInWallet(passDatas: sorted)
                }
            )
            .store(in: &cancellables)
    }

    private func openPassesInWallet(passDatas: [Data]) {
        do {
            // Save each pass to a temporary file (optional; PassKit can take Data directly)
            let passes: [PKPass] = try passDatas.map { try PKPass(data: $0) }

            guard PKPassLibrary.isPassLibraryAvailable() else {
                statusMessage = "Apple Wallet is not available on this device"
                hasError = true
                return
            }

            // Save all passes as one SavedPass entry
            saveMultiplePassesToPersistentStorage(passDatas: passDatas)

            let passVC = PKAddPassesViewController(passes: passes)

            statusMessage = nil
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
            statusMessage = "Error creating passes: \(error.localizedDescription)"
            hasError = true
        }
    }

    private func startPhraseCycling() {
        // Immediately set a phrase
        funnyPhrase = phrases.randomElement() ?? "Getting things ready..."
        phraseTimer?.cancel()
        phraseTimer = Timer.publish(every: 1.8, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                var next = phrases.randomElement() ?? "Almost there..."
                if next == funnyPhrase { next = phrases.shuffled().first ?? next }
                funnyPhrase = next
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
            (0.65, "Processing with AI...", 8.0),
            (0.85, "Generating pass...", 7.0),
            (0.95, "Signing certificate...", 5.0)
        ]
        
        var currentStep = 0
        var elapsedTime: Double = 0
        
        progressTimer?.cancel()
        progressTimer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                elapsedTime += 0.1
                
                // Check if we should move to next step
                if currentStep < steps.count {
                    let (targetProgress, _, duration) = steps[currentStep]
                    
                    // Calculate cumulative time for this step
                    var cumulativeTime: Double = 0
                    for i in 0..<currentStep {
                        cumulativeTime += steps[i].2
                    }
                    
                    if elapsedTime >= cumulativeTime + duration {
                        // Move to next step
                        if currentStep < steps.count - 1 {
                            currentStep += 1
                            self.progressMessage = steps[currentStep].1
                        }
                    }
                    
                    // Animate progress smoothly towards target
                    let startProgress = currentStep > 0 ? steps[currentStep - 1].0 : 0.0
                    let progressRange = targetProgress - startProgress
                    let stepElapsed = elapsedTime - cumulativeTime
                    let stepProgress = min(stepElapsed / duration, 1.0)
                    
                    self.progress = startProgress + (progressRange * stepProgress)
                }
                
                // Stop at 95% and wait for actual completion
                if self.progress >= 0.95 {
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
}
