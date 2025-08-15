import XCTest
import Combine
@testable import Add2Wallet

@MainActor
class ContentViewModelTests: XCTestCase {
    var viewModel: ContentViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = ContentViewModel()
    }
    
    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }
    
    func testInitialState() {
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertNil(viewModel.statusMessage)
        XCTAssertFalse(viewModel.hasError)
    }
    
    func testSelectPDF() {
        viewModel.selectPDF()
        
        XCTAssertTrue(viewModel.showingDocumentPicker)
        XCTAssertFalse(viewModel.hasError)
    }
    
    func testProcessPDFStartsProcessing() {
        let testData = "Test PDF".data(using: .utf8)!
        
        viewModel.processPDF(data: testData, filename: "test.pdf")
        
        XCTAssertTrue(viewModel.isProcessing)
        XCTAssertNil(viewModel.statusMessage)
        XCTAssertFalse(viewModel.hasError)
    }
    
    func testClearSelection() {
        // Set some initial state
        viewModel.selectedFileURL = URL(fileURLWithPath: "/tmp/test.pdf")
        viewModel.statusMessage = "Test message"
        viewModel.hasError = true
        
        viewModel.clearSelection()
        
        XCTAssertNil(viewModel.selectedFileURL)
        XCTAssertNil(viewModel.statusMessage)
        XCTAssertFalse(viewModel.hasError)
        XCTAssertFalse(viewModel.isRetry)
        XCTAssertEqual(viewModel.retryCount, 0)
        XCTAssertFalse(viewModel.isDemo)
    }
    
    func testLoadDemoFile() {
        viewModel.loadDemoFile()
        
        XCTAssertNotNil(viewModel.selectedFileURL)
        XCTAssertTrue(viewModel.isDemo)
        XCTAssertFalse(viewModel.hasError)
        XCTAssertNil(viewModel.statusMessage)
    }
}