import XCTest
import Combine
@testable import Add2Wallet

@MainActor
final class ShareExtensionTests: XCTestCase {
    private var viewModel: ContentViewModel!

    override func setUp() {
        super.setUp()
        _ = URLHandler.dequeuePendingFile()
        viewModel = ContentViewModel()
    }

    override func tearDown() {
        viewModel.clearSelection()
        viewModel = nil
        _ = URLHandler.dequeuePendingFile()
        super.tearDown()
    }

    func testSharedImageNotificationPreservesFilenameAndPreviewsBeforeUpload() async {
        let testData = Data([0x89, 0x50, 0x4E, 0x47])
        let testFilename = "mobile-ticket.png"

        NotificationManager.postSharedFileReceived(filename: testFilename, data: testData)
        await Task.yield()

        XCTAssertEqual(viewModel.selectedFileURL?.lastPathComponent, testFilename)
        XCTAssertEqual(try? Data(contentsOf: viewModel.selectedFileURL!), testData)
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertFalse(viewModel.hasError)
    }

    func testSharedFileWithInvalidNotificationDataIsIgnored() {
        NotificationCenter.default.post(
            name: NSNotification.Name("SharedFileReceived"),
            object: nil,
            userInfo: ["data": Data()]
        )
        XCTAssertNil(viewModel.selectedFileURL)

        NotificationCenter.default.post(
            name: NSNotification.Name("SharedFileReceived"),
            object: nil,
            userInfo: ["filename": "test.heic"]
        )
        XCTAssertNil(viewModel.selectedFileURL)
    }

    func testPendingSharedImagePreservesExtension() {
        let data = Data([0x00, 0x01])
        URLHandler.enqueueFile(filename: "Boarding Pass.HEIC", data: data)

        let pending = URLHandler.dequeuePendingFile()
        XCTAssertEqual(pending?.filename, "Boarding Pass.HEIC")
        XCTAssertEqual(pending?.data, data)
    }
}
