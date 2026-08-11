import XCTest
import PDFKit
import UIKit
@testable import Add2Wallet

/// What the scanner hands to the uploader.
///
/// Pages become a PDF because that is the shape the rest of the system is best
/// at — text per page, barcodes tagged with the page they came from, and a
/// multi-page document already understood as a multi-ticket booking.
final class DocumentScannerTests: XCTestCase {

    /// A scanned page: `width`×`height` pixels at scale 1, optionally carrying
    /// the orientation tag a sideways capture would.
    private func page(
        width: CGFloat,
        height: CGFloat,
        orientation: UIImage.Orientation = .up
    ) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let pixels = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            .image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                UIColor.black.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width / 4, height: height / 4))
            }
        return UIImage(cgImage: try XCTUnwrap(pixels.cgImage), scale: 1, orientation: orientation)
    }

    private func document(_ data: Data?) throws -> PDFDocument {
        try XCTUnwrap(PDFDocument(data: try XCTUnwrap(data)))
    }

    func testNothingScannedIsNoDocument() {
        XCTAssertNil(DocumentScanner.pdf(from: []), "an empty scan must not produce an empty PDF")
    }

    func testEveryScannedPageBecomesAPDFPage() throws {
        let pages = try [page(width: 800, height: 1000), page(width: 800, height: 1000), page(width: 800, height: 1000)]
        XCTAssertEqual(try document(DocumentScanner.pdf(from: pages)).pageCount, 3)
    }

    func testTheOutputIsRecognisablyAPDF() throws {
        let data = try XCTUnwrap(DocumentScanner.pdf(from: [page(width: 400, height: 500)]))
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "%PDF")
    }

    /// The one that stops a sideways ticket reaching the extractor: `draw`
    /// applies `imageOrientation`, so the page lands upright rather than
    /// carrying a tag the server has no reason to honour.
    func testAPageHeldSidewaysLandsUpright() throws {
        let sideways = try page(width: 1000, height: 800, orientation: .right)
        let bounds = try XCTUnwrap(document(DocumentScanner.pdf(from: [sideways])).page(at: 0))
            .bounds(for: .mediaBox)

        XCTAssertGreaterThan(bounds.height, bounds.width, "a portrait page must not come out landscape")
    }

    func testAnOversizePageIsBroughtUnderTheUploadLimit() throws {
        let huge = try page(width: 4000, height: 3000)
        let bounds = try XCTUnwrap(document(DocumentScanner.pdf(from: [huge])).page(at: 0))
            .bounds(for: .mediaBox)

        XCTAssertEqual(bounds.width, DocumentScanner.maxPageDimension, accuracy: 1)
        XCTAssertEqual(bounds.height, DocumentScanner.maxPageDimension * 0.75, accuracy: 1, "aspect ratio is kept")
    }

    func testAPageThatAlreadyFitsIsLeftAtItsOwnSize() throws {
        let modest = try page(width: 800, height: 1000)
        let bounds = try XCTUnwrap(document(DocumentScanner.pdf(from: [modest])).page(at: 0))
            .bounds(for: .mediaBox)

        XCTAssertEqual(bounds.width, 800, accuracy: 1)
        XCTAssertEqual(bounds.height, 1000, accuracy: 1)
    }

    /// Three full-size pages used to be tens of megabytes drawn as raw bitmaps;
    /// the server refuses anything over 10 MB.
    func testAThreePageScanFitsInTheUpload() throws {
        let pages = try (0..<3).map { _ in try page(width: 3024, height: 4032) }
        let data = try XCTUnwrap(DocumentScanner.pdf(from: pages))

        XCTAssertLessThan(data.count, 10 * 1024 * 1024)
    }
}
