import SwiftUI
import Combine
import UniformTypeIdentifiers
import PassKit

class ContentViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var statusMessage: String?
    @Published var hasError = false
    @Published var showingDocumentPicker = false
    
    private let networkService = NetworkService()
    private var cancellables = Set<AnyCancellable>()
    
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
        guard url.startAccessingSecurityScopedResource() else {
            statusMessage = "Unable to access selected file"
            hasError = true
            return
        }
        
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let data = try Data(contentsOf: url)
            let filename = url.lastPathComponent
            processPDF(data: data, filename: filename)
        } catch {
            statusMessage = "Error reading PDF: \(error.localizedDescription)"
            hasError = true
        }
    }
    
    func processPDF(data: Data, filename: String) {
        isProcessing = true
        statusMessage = "Processing \(filename)..."
        hasError = false
        
        networkService.uploadPDF(data: data, filename: filename)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isProcessing = false
                    if case .failure(let error) = completion {
                        self?.statusMessage = "Error: \(error.localizedDescription)"
                        self?.hasError = true
                    }
                },
                receiveValue: { [weak self] response in
                    if response.status == "completed", let passUrl = response.passUrl {
                        self?.downloadAndOpenPass(passUrl: passUrl)
                    } else {
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
                userInfo: ["passViewController": passVC, "tempURL": tempURL]
            )
            
        } catch {
            statusMessage = "Error creating pass: \(error.localizedDescription)"
            hasError = true
        }
    }
}