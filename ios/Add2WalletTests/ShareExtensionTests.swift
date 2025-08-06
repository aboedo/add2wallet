import XCTest
@testable import Add2Wallet

class ShareExtensionTests: XCTestCase {
    var viewModel: ContentViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = ContentViewModel()
    }
    
    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }
    
    func testSharedPDFNotification() {
        let expectation = XCTestExpectation(description: "Shared PDF notification")
        let testData = "Test PDF Content".data(using: .utf8)!
        let testFilename = "test.pdf"
        
        // Monitor for processing state change
        let cancellable = viewModel.$isProcessing.sink { isProcessing in
            if isProcessing {
                expectation.fulfill()
            }
        }
        
        // Simulate shared PDF notification
        NotificationCenter.default.post(
            name: NSNotification.Name("SharedPDFReceived"),
            object: nil,
            userInfo: ["filename": testFilename, "data": testData]
        )
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertTrue(viewModel.isProcessing)
        XCTAssertEqual(viewModel.statusMessage, "Processing \(testFilename)...")
        XCTAssertFalse(viewModel.hasError)
        
        cancellable.cancel()
    }
    
    func testSharedPDFWithInvalidData() {
        // Test with missing filename
        NotificationCenter.default.post(
            name: NSNotification.Name("SharedPDFReceived"),
            object: nil,
            userInfo: ["data": Data()]
        )
        
        XCTAssertFalse(viewModel.isProcessing)
        
        // Test with missing data
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