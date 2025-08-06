import SwiftUI
import Combine

class ContentViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var statusMessage: String?
    @Published var hasError = false
    
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
        statusMessage = "PDF selection will be implemented with document picker"
        hasError = false
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
                    self?.statusMessage = "PDF uploaded successfully! Job ID: \(response.jobId)"
                    self?.hasError = false
                }
            )
            .store(in: &cancellables)
    }
}