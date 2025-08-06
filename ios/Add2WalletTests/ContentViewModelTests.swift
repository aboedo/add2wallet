import XCTest
import Combine
@testable import Add2Wallet

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
        
        XCTAssertNotNil(viewModel.statusMessage)
        XCTAssertFalse(viewModel.hasError)
        XCTAssertEqual(viewModel.statusMessage, "PDF selection will be implemented with document picker")
    }
    
    func testProcessPDFStartsProcessing() {
        let testData = "Test PDF".data(using: .utf8)!
        
        viewModel.processPDF(data: testData, filename: "test.pdf")
        
        XCTAssertTrue(viewModel.isProcessing)
        XCTAssertNil(viewModel.statusMessage)
        XCTAssertFalse(viewModel.hasError)
    }
}