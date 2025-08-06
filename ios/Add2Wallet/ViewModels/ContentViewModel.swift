import SwiftUI
import Combine

class ContentViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var statusMessage: String?
    @Published var hasError = false
    
    private let networkService = NetworkService()
    private var cancellables = Set<AnyCancellable>()
    
    func selectPDF() {
        statusMessage = "PDF selection will be implemented with document picker"
        hasError = false
    }
    
    func processPDF(data: Data, filename: String) {
        isProcessing = true
        statusMessage = nil
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