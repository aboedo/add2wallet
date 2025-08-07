import SwiftUI
import Combine
import UniformTypeIdentifiers
import PassKit

class ContentViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var statusMessage: String?
    @Published var funnyPhrase: String = ""
    @Published var hasError = false
    @Published var showingDocumentPicker = false
    @Published var selectedFileURL: URL?
    @Published var passMetadata: EnhancedPassMetadata?
    @Published var ticketCount: Int? = nil
    
    private let networkService = NetworkService()
    private var cancellables = Set<AnyCancellable>()
    private var phraseTimer: AnyCancellable?
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
            if let userInfo = notification.userInfo,
               let filename = userInfo["filename"] as? String,
               let data = userInfo["data"] as? Data {
                self?.processPDF(data: data, filename: filename)
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
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
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("pdf")
            try data.write(to: tempURL, options: [.atomic])
            selectedFileURL = tempURL
            // Reset any previously generated pass UI state/metadata
            NotificationCenter.default.post(name: NSNotification.Name("ResetPassUIState"), object: nil)
            passMetadata = nil
            statusMessage = "Ready to upload \(url.lastPathComponent)"
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
        NotificationCenter.default.post(name: NSNotification.Name("ResetPassUIState"), object: nil)
    }
    
    func processPDF(data: Data, filename: String) {
        isProcessing = true
        statusMessage = "Processing \(filename)..."
        startPhraseCycling()
        hasError = false
        
        networkService.uploadPDF(data: data, filename: filename)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.isProcessing = false
                        self?.stopPhraseCycling()
                        self?.statusMessage = "Error: \(error.localizedDescription)"
                        self?.hasError = true
                    }
                },
                receiveValue: { [weak self] response in
                    self?.passMetadata = response.aiMetadata
                    self?.ticketCount = response.ticketCount
                    if response.status == "completed", let passUrl = response.passUrl {
                        self?.downloadAndOpenPass(passUrl: passUrl)
                    } else {
                        self?.isProcessing = false
                        self?.stopPhraseCycling()
                        self?.statusMessage = "Pass generation failed. Status: \(response.status)"
                        self?.hasError = true
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    private func downloadAndOpenPass(passUrl: String) {
        statusMessage = "Downloading pass..."
        
        networkService.downloadPass(from: passUrl)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.isProcessing = false
                        self?.stopPhraseCycling()
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
            
            // Present the add pass view controller
            let passVC = PKAddPassesViewController(pass: pass)
            
            // For now, show success message - we'll need to present the VC from the View
            statusMessage = "Pass ready! Tap to add to Wallet"
            hasError = false
            
            // Store the pass data for the view to access
            NotificationCenter.default.post(
                name: NSNotification.Name("PassReadyToAdd"),
                object: nil,
                userInfo: ["passViewController": passVC!, "tempURL": tempURL]
            )
            isProcessing = false
            stopPhraseCycling()
            
        } catch {
            isProcessing = false
            stopPhraseCycling()
            statusMessage = "Error creating pass: \(error.localizedDescription)"
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
}
