import SwiftUI
import UIKit
import VisionKit

/// The system document scanner, handed back as a PDF.
///
/// A photo of a ticket is a photo: taken at an angle, with the table around it
/// and whatever light the room had. `VNDocumentCameraViewController` is the
/// same camera with edge detection, perspective correction and contrast on top
/// — the one in Notes — and it takes several pages in one go, which is what a
/// booking of four tickets actually is.
///
/// Pages come out as a PDF rather than as images because that is the shape the
/// rest of the system is best at: the extractor reads text per page, barcodes
/// carry the page they were found on, and a multi-page document is already how
/// a multi-ticket booking is understood end to end.
struct DocumentScanner: UIViewControllerRepresentable {
    /// PDF bytes of the scan, or nil when the person backed out.
    let onScan: (Data?) -> Void

    /// Longest side of a page in the PDF.
    ///
    /// The scanner hands back something like 12 megapixels a page, and three of
    /// those sail past the 10 MB the server accepts. 2200 px down the long edge
    /// is around 200 dpi on A4 — well above what the barcode reader and the
    /// text extraction need, and small enough that a five-page booking still
    /// fits.
    static let maxPageDimension: CGFloat = 2200

    /// High: fine barcode bars are the first thing a hard compression eats.
    static let jpegQuality: CGFloat = 0.85

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let parent: DocumentScanner

        init(_ parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onScan(DocumentScanner.pdf(from: pages))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onScan(nil)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            parent.onScan(nil)
        }
    }

    /// One PDF page per scanned page, at the page's own aspect ratio.
    ///
    /// Each page is re-encoded as JPEG first. Drawing the raw bitmap into a PDF
    /// context stores it uncompressed, which turns a three-page scan into tens
    /// of megabytes for no visible gain.
    static func pdf(from pages: [UIImage]) -> Data? {
        let prepared = pages.compactMap(compressed)
        guard let first = prepared.first else { return nil }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: first.size))
        let data = renderer.pdfData { context in
            for page in prepared {
                let bounds = CGRect(origin: .zero, size: page.size)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                // `draw` applies `imageOrientation`, so a page held sideways
                // lands upright in the PDF rather than carrying a tag the
                // server has no reason to honour.
                page.draw(in: bounds)
            }
        }
        return data.isEmpty ? nil : data
    }

    private static func compressed(_ image: UIImage) -> UIImage? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxPageDimension ? maxPageDimension / longest : 1

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }

        guard let data = resized.jpegData(compressionQuality: jpegQuality) else { return resized }
        return UIImage(data: data) ?? resized
    }
}
