import Foundation
import Combine
@testable import Add2Wallet

// MARK: - Mock Network Service

class MockNetworkService {
    
    // MARK: - Configuration
    
    indirect enum MockResponse {
        case success(UploadResponse)
        case failure(Error)
        case delay(TimeInterval, MockResponse)
    }
    
    indirect enum MockDownloadResponse {
        case success(Data)
        case failure(Error)
        case delay(TimeInterval, MockDownloadResponse)
    }
    
    var uploadResponse: MockResponse = .success(UploadResponse(
        jobId: "mock-job-123",
        status: "completed",
        passUrl: "/pass/mock-job-123",
        aiMetadata: TestHelpers.createTestEnhancedPassMetadata(),
        ticketCount: 1,
        warnings: nil
    ))
    
    var downloadResponse: MockDownloadResponse = .success(Data())
    
    // MARK: - Mock Implementation
    
    func uploadPDF(data: Data, filename: String, isRetry: Bool = false, isDemo: Bool = false) -> AnyPublisher<UploadResponse, Error> {
        return executeUploadResponse()
    }
    
    func downloadPass(from passUrl: String) -> AnyPublisher<Data, Error> {
        return executeDownloadResponse()
    }
    
    // MARK: - Helper Methods
    
    private func executeUploadResponse() -> AnyPublisher<UploadResponse, Error> {
        switch uploadResponse {
        case .success(let response):
            return Just(response)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
            
        case .failure(let error):
            return Fail(error: error)
                .eraseToAnyPublisher()
            
        case .delay(let timeInterval, let nestedResponse):
            let originalResponse = uploadResponse
            uploadResponse = nestedResponse
            
            return Just(())
                .delay(for: .seconds(timeInterval), scheduler: DispatchQueue.main)
                .flatMap { _ in
                    self.executeUploadResponse()
                }
                .handleEvents(receiveCompletion: { _ in
                    self.uploadResponse = originalResponse
                })
                .eraseToAnyPublisher()
        }
    }
    
    private func executeDownloadResponse() -> AnyPublisher<Data, Error> {
        switch downloadResponse {
        case .success(let data):
            return Just(data)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
            
        case .failure(let error):
            return Fail(error: error)
                .eraseToAnyPublisher()
            
        case .delay(let timeInterval, let nestedResponse):
            let originalResponse = downloadResponse
            downloadResponse = nestedResponse
            
            return Just(())
                .delay(for: .seconds(timeInterval), scheduler: DispatchQueue.main)
                .flatMap { _ in
                    self.executeDownloadResponse()
                }
                .handleEvents(receiveCompletion: { _ in
                    self.downloadResponse = originalResponse
                })
                .eraseToAnyPublisher()
        }
    }
    
    // MARK: - Configuration Helpers
    
    func setSuccessResponse(_ response: UploadResponse) {
        uploadResponse = .success(response)
    }
    
    func setErrorResponse(_ error: Error) {
        uploadResponse = .failure(error)
    }
    
    func setDelayedResponse(_ response: UploadResponse, delay: TimeInterval) {
        uploadResponse = .delay(delay, .success(response))
    }
    
    func setDownloadSuccessResponse(_ data: Data) {
        downloadResponse = .success(data)
    }
    
    func setDownloadErrorResponse(_ error: Error) {
        downloadResponse = .failure(error)
    }
    
    func setDelayedDownloadResponse(_ data: Data, delay: TimeInterval) {
        downloadResponse = .delay(delay, .success(data))
    }
    
    // MARK: - Predefined Responses
    
    func configureForMultiTicketResponse() {
        guard let jsonData = TestHelpers.loadTestJSON(named: "mock_multi_ticket_response"),
              let response = try? JSONDecoder().decode(UploadResponse.self, from: jsonData) else {
            return
        }
        setSuccessResponse(response)
    }
    
    func configureForErrorResponse() {
        setErrorResponse(NetworkError.serverError("Test server error", statusCode: 400))
    }
    
    func configureForNetworkTimeout() {
        setErrorResponse(NetworkError.invalidResponse)
    }
    
    func configureForInvalidPDFError() {
        setErrorResponse(NetworkError.serverError("Invalid PDF format", statusCode: 422))
    }
}

// MARK: - Mock Network Errors

enum MockNetworkError: Error, LocalizedError {
    case mockError(String)
    case timeout
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .mockError(let message):
            return "Mock Error: \(message)"
        case .timeout:
            return "Mock network timeout"
        case .invalidData:
            return "Mock invalid data error"
        }
    }
}