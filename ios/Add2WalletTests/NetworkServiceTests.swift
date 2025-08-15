import XCTest
import Combine
@testable import Add2Wallet

class NetworkServiceTests: XCTestCase {
    var mockNetworkService: MockNetworkService!
    var realNetworkService: NetworkService!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        mockNetworkService = MockNetworkService()
        realNetworkService = NetworkService()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables = nil
        mockNetworkService = nil
        realNetworkService = nil
        super.tearDown()
    }
    
    // MARK: - Mock Network Service Tests
    
    func testMockUploadPDFSuccess() {
        let expectation = XCTestExpectation(description: "Mock upload success")
        let testData = TestHelpers.createTestPDFData()
        
        // Configure mock for success
        let expectedResponse = UploadResponse(
            jobId: "test-123",
            status: "completed",
            passUrl: "/pass/test-123",
            aiMetadata: TestHelpers.createTestEnhancedPassMetadata(),
            ticketCount: 1,
            warnings: nil
        )
        mockNetworkService.setSuccessResponse(expectedResponse)
        
        mockNetworkService.uploadPDF(data: testData, filename: "test.pdf")
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Mock upload failed with error: \(error)")
                    }
                },
                receiveValue: { response in
                    XCTAssertEqual(response.jobId, "test-123")
                    XCTAssertEqual(response.status, "completed")
                    XCTAssertEqual(response.passUrl, "/pass/test-123")
                    XCTAssertNotNil(response.aiMetadata)
                    XCTAssertEqual(response.ticketCount, 1)
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testMockUploadPDFError() {
        let expectation = XCTestExpectation(description: "Mock upload error")
        let testData = TestHelpers.createTestPDFData()
        
        // Configure mock for error
        mockNetworkService.setErrorResponse(NetworkError.serverError("Invalid PDF format", statusCode: 422))
        
        mockNetworkService.uploadPDF(data: testData, filename: "invalid.pdf")
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        if let networkError = error as? NetworkError,
                           case .serverError(let message, let statusCode) = networkError {
                            XCTAssertEqual(message, "Invalid PDF format")
                            XCTAssertEqual(statusCode, 422)
                            expectation.fulfill()
                        } else {
                            XCTFail("Expected NetworkError.serverError")
                        }
                    }
                },
                receiveValue: { _ in
                    XCTFail("Should not succeed with invalid PDF")
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testMockUploadPDFWithDelay() {
        let expectation = XCTestExpectation(description: "Mock upload with delay")
        let testData = TestHelpers.createTestPDFData()
        
        // Configure mock for delayed response
        let expectedResponse = UploadResponse(
            jobId: "delayed-123",
            status: "completed",
            passUrl: "/pass/delayed-123",
            aiMetadata: nil,
            ticketCount: 1,
            warnings: nil
        )
        mockNetworkService.setDelayedResponse(expectedResponse, delay: 0.5)
        
        let startTime = Date()
        
        mockNetworkService.uploadPDF(data: testData, filename: "test.pdf")
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Mock upload failed with error: \(error)")
                    }
                },
                receiveValue: { response in
                    let elapsed = Date().timeIntervalSince(startTime)
                    XCTAssertGreaterThan(elapsed, 0.4) // Should take at least 0.4 seconds
                    XCTAssertEqual(response.jobId, "delayed-123")
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testMockDownloadPassSuccess() {
        let expectation = XCTestExpectation(description: "Mock download success")
        let expectedData = "Mock pass data".data(using: .utf8)!
        
        mockNetworkService.setDownloadSuccessResponse(expectedData)
        
        mockNetworkService.downloadPass(from: "/pass/test-123")
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Mock download failed with error: \(error)")
                    }
                },
                receiveValue: { data in
                    XCTAssertEqual(data, expectedData)
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testMockDownloadPassError() {
        let expectation = XCTestExpectation(description: "Mock download error")
        
        mockNetworkService.setDownloadErrorResponse(NetworkError.serverError("Pass not found", statusCode: 404))
        
        mockNetworkService.downloadPass(from: "/pass/missing")
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        if let networkError = error as? NetworkError,
                           case .serverError(let message, let statusCode) = networkError {
                            XCTAssertEqual(message, "Pass not found")
                            XCTAssertEqual(statusCode, 404)
                            expectation.fulfill()
                        } else {
                            XCTFail("Expected NetworkError.serverError")
                        }
                    }
                },
                receiveValue: { _ in
                    XCTFail("Should not succeed with missing pass")
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testMockMultiTicketResponse() {
        let expectation = XCTestExpectation(description: "Mock multi-ticket response")
        let testData = TestHelpers.createTestPDFData()
        
        // Configure mock for multi-ticket response
        mockNetworkService.configureForMultiTicketResponse()
        
        mockNetworkService.uploadPDF(data: testData, filename: "multi_ticket.pdf")
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Mock upload failed with error: \(error)")
                    }
                },
                receiveValue: { response in
                    XCTAssertEqual(response.ticketCount, 4)
                    XCTAssertNotNil(response.warnings)
                    XCTAssertTrue(response.warnings?.contains("Multiple barcodes detected. Generated 4 separate passes.") ?? false)
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - Real Network Service Tests (Integration)
    
    func testRealNetworkServiceInitialization() {
        XCTAssertNotNil(realNetworkService)
        // Verify that the real network service is properly configured
        // These are structural tests that don't require network access
    }
    
    func testNetworkErrorTypes() {
        // Test error type creation and properties
        let invalidURLError = NetworkError.invalidURL
        XCTAssertEqual(invalidURLError.errorDescription, "Invalid server URL")
        XCTAssertNil(invalidURLError.statusCode)
        
        let serverError = NetworkError.serverError("Test error", statusCode: 500)
        XCTAssertEqual(serverError.errorDescription, "Test error (Code: 500)")
        XCTAssertEqual(serverError.statusCode, 500)
        
        let decodingError = NetworkError.decodingError
        XCTAssertEqual(decodingError.errorDescription, "Failed to decode server response")
        XCTAssertNil(decodingError.statusCode)
    }
    
    func testUploadResponseDecoding() {
        // Test that we can properly decode JSON responses
        guard let jsonData = TestHelpers.loadTestJSON(named: "mock_upload_response") else {
            XCTFail("Failed to load mock_upload_response.json")
            return
        }
        
        do {
            let response = try JSONDecoder().decode(UploadResponse.self, from: jsonData)
            XCTAssertEqual(response.jobId, "test-job-123")
            XCTAssertEqual(response.status, "completed")
            XCTAssertEqual(response.passUrl, "/pass/test-job-123")
            XCTAssertNotNil(response.aiMetadata)
            XCTAssertEqual(response.ticketCount, 1)
            XCTAssertEqual(response.warnings?.count, 0)
        } catch {
            XCTFail("Failed to decode UploadResponse: \(error)")
        }
    }
    
    func testErrorResponseDecoding() {
        // Test that we can properly decode error responses
        guard let jsonData = TestHelpers.loadTestJSON(named: "mock_error_response") else {
            XCTFail("Failed to load mock_error_response.json")
            return
        }
        
        do {
            let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: jsonData)
            XCTAssertEqual(errorResponse.error, "Invalid PDF format. Please ensure the file is a valid PDF document.")
        } catch {
            XCTFail("Failed to decode ErrorResponse: \(error)")
        }
    }
    
    func testEnhancedPassMetadataDecoding() {
        // Test that metadata decoding works properly
        guard let jsonData = TestHelpers.loadTestJSON(named: "mock_upload_response") else {
            XCTFail("Failed to load mock_upload_response.json")
            return
        }
        
        do {
            let response = try JSONDecoder().decode(UploadResponse.self, from: jsonData)
            guard let metadata = response.aiMetadata else {
                XCTFail("No metadata in response")
                return
            }
            
            XCTAssertEqual(metadata.eventType, "concert")
            XCTAssertEqual(metadata.eventName, "Test Concert")
            XCTAssertEqual(metadata.title, "Test Event Title")
            XCTAssertEqual(metadata.date, "2024-12-15")
            XCTAssertEqual(metadata.time, "19:30")
            XCTAssertEqual(metadata.venueName, "Test Venue")
            XCTAssertEqual(metadata.city, "Test City")
            XCTAssertEqual(metadata.barcodeData, "123456789")
            XCTAssertEqual(metadata.backgroundColor, "rgb(255,45,85)")
            XCTAssertEqual(metadata.aiProcessed, true)
            XCTAssertEqual(metadata.confidenceScore, 85)
        } catch {
            XCTFail("Failed to decode metadata: \(error)")
        }
    }
    
    // MARK: - Edge Cases and Error Handling
    
    func testUploadWithRetryFlag() {
        let expectation = XCTestExpectation(description: "Upload with retry flag")
        let testData = TestHelpers.createTestPDFData()
        
        let expectedResponse = UploadResponse(
            jobId: "retry-123",
            status: "completed",
            passUrl: "/pass/retry-123",
            aiMetadata: nil,
            ticketCount: 1,
            warnings: nil
        )
        mockNetworkService.setSuccessResponse(expectedResponse)
        
        mockNetworkService.uploadPDF(data: testData, filename: "test.pdf", isRetry: true)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Upload failed with error: \(error)")
                    }
                },
                receiveValue: { response in
                    XCTAssertEqual(response.jobId, "retry-123")
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testUploadWithDemoFlag() {
        let expectation = XCTestExpectation(description: "Upload with demo flag")
        let testData = TestHelpers.createTestPDFData()
        
        let expectedResponse = UploadResponse(
            jobId: "demo-123",
            status: "completed",
            passUrl: "/pass/demo-123",
            aiMetadata: nil,
            ticketCount: 1,
            warnings: nil
        )
        mockNetworkService.setSuccessResponse(expectedResponse)
        
        mockNetworkService.uploadPDF(data: testData, filename: "demo.pdf", isDemo: true)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Upload failed with error: \(error)")
                    }
                },
                receiveValue: { response in
                    XCTAssertEqual(response.jobId, "demo-123")
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testDownloadPassWithTicketNumber() {
        let expectation = XCTestExpectation(description: "Download pass with ticket number")
        let expectedData = "Mock ticket 2 data".data(using: .utf8)!
        
        mockNetworkService.setDownloadSuccessResponse(expectedData)
        
        mockNetworkService.downloadPass(from: "/pass/test-123?ticket_number=2")
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Download failed with error: \(error)")
                    }
                },
                receiveValue: { data in
                    XCTAssertEqual(data, expectedData)
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2.0)
    }
}