import XCTest
import Combine
@testable import Add2Wallet

@MainActor
class ShareExtensionTests: XCTestCase {
    var viewModel: ContentViewModel!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        viewModel = ContentViewModel()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables = nil
        viewModel = nil
        super.tearDown()
    }
    
    func testSharedPDFNotification() async {
        let expectation = XCTestExpectation(description: "Shared PDF notification")
        let testData = "Test PDF Content".data(using: .utf8)!
        let testFilename = "test.pdf"
        
        // Monitor for processing state change
        viewModel.$isProcessing.sink { isProcessing in
            if isProcessing {
                expectation.fulfill()
            }
        }.store(in: &cancellables)
        
        // Simulate shared PDF notification using NotificationManager
        NotificationManager.postSharedPDFReceived(filename: testFilename, data: testData)
        
        await fulfillment(of: [expectation], timeout: 2.0)
        
        XCTAssertTrue(viewModel.isProcessing)
        XCTAssertFalse(viewModel.hasError)
    }
    
    func testSharedPDFWithInvalidData() {
        // Test with missing filename - should not trigger processing
        NotificationCenter.default.post(
            name: NSNotification.Name("SharedPDFReceived"),
            object: nil,
            userInfo: ["data": Data()]
        )
        
        XCTAssertFalse(viewModel.isProcessing)
        
        // Test with missing data - should not trigger processing
        NotificationCenter.default.post(
            name: NSNotification.Name("SharedPDFReceived"),
            object: nil,
            userInfo: ["filename": "test.pdf"]
        )
        
        XCTAssertFalse(viewModel.isProcessing)
    }
    
    func testSharedContainerPath() {
        let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.andresboedo.add2wallet")
        
        // The shared container should be accessible (though may be nil in simulator without proper provisioning)
        // This test mainly checks that the API works
        if let container = sharedContainer {
            XCTAssertTrue(container.path.contains("group.com.andresboedo.add2wallet"))
        }
    }
}