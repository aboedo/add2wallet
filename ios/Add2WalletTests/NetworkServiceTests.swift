import XCTest
import Combine
@testable import Add2Wallet

class NetworkServiceTests: XCTestCase {
    var networkService: NetworkService!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        networkService = NetworkService()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables = nil
        networkService = nil
        super.tearDown()
    }
    
    func testUploadPDFWithValidData() {
        let expectation = XCTestExpectation(description: "Upload PDF")
        let testData = "Test PDF Content".data(using: .utf8)!
        
        networkService.uploadPDF(data: testData, filename: "test.pdf")
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Upload failed with error: \(error)")
                    }
                },
                receiveValue: { response in
                    XCTAssertNotNil(response.jobId)
                    XCTAssertEqual(response.status, "processing")
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testUploadPDFWithEmptyData() {
        let expectation = XCTestExpectation(description: "Upload empty PDF")
        let emptyData = Data()
        
        networkService.uploadPDF(data: emptyData, filename: "empty.pdf")
            .sink(
                receiveCompletion: { completion in
                    if case .failure = completion {
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in
                    XCTFail("Should not succeed with empty data")
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 5.0)
    }
}