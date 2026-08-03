import XCTest
import Combine
import UniformTypeIdentifiers
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
        XCTAssertNil(viewModel.errorMessage)
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
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.hasError)
    }
    
    func testClearSelection() {
        // Set some initial state
        viewModel.selectedFileURL = URL(fileURLWithPath: "/tmp/test.pdf")
        viewModel.errorMessage = "Test message"
        viewModel.hasError = true
        
        viewModel.clearSelection()
        
        XCTAssertNil(viewModel.selectedFileURL)
        XCTAssertNil(viewModel.errorMessage)
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
        XCTAssertNil(viewModel.errorMessage)
    }

    func testImportFileKeepsFilename() {
        viewModel.importFile(data: Data("screenshot".utf8), filename: "photo.png")

        let url = try? XCTUnwrap(viewModel.selectedFileURL)
        XCTAssertEqual(url?.lastPathComponent, "photo.png")
        XCTAssertFalse(viewModel.hasError)
    }

    func testHandlePastedProvidersPrefersPDFOverPreviewImage() {
        // A pasted PDF also advertises a preview image; the document must win.
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(Data("png".utf8), nil)
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.pdf.identifier, visibility: .all) { completion in
            completion(Data("%PDF-1.4".utf8), nil)
            return nil
        }
        provider.suggestedName = "ticket"

        let imported = expectation(description: "pasted file imported")
        let cancellable = viewModel.$selectedFileURL
            .compactMap { $0 }
            .sink { _ in imported.fulfill() }

        viewModel.handlePastedProviders([provider])

        wait(for: [imported], timeout: 5)
        cancellable.cancel()

        XCTAssertEqual(viewModel.selectedFileURL?.pathExtension, "pdf")
        XCTAssertFalse(viewModel.hasError)
    }

    func testHandlePastedProvidersRejectsUnsupportedContent() {
        let provider = NSItemProvider(object: "just some text" as NSString)

        viewModel.handlePastedProviders([provider])

        XCTAssertNil(viewModel.selectedFileURL)
        XCTAssertTrue(viewModel.hasError)
        XCTAssertNotNil(viewModel.errorMessage)
    }
}