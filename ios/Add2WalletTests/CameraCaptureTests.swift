import XCTest
import UIKit
import UniformTypeIdentifiers
@testable import Add2Wallet

/// What the camera hands to the uploader.
///
/// The camera returns landscape pixels with an orientation tag, and `jpegData`
/// records that tag rather than rotating anything. iOS honours it; the server
/// rendering the image and the model reading it need not, and a sideways
/// ticket reads as an unrecognisable document rather than a bad photo.
final class CameraCaptureTests: XCTestCase {

    /// A frame as the camera produces it: 40×20 pixels, tagged `.right`, which
    /// is a 20×40 portrait photo once the tag is applied.
    private func cameraFrame(orientation: UIImage.Orientation) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let pixels = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20), format: format)
            .image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
            }
        return UIImage(cgImage: try XCTUnwrap(pixels.cgImage), scale: 1, orientation: orientation)
    }

    func testAPortraitPhotoArrivesWithUprightPixelsNotATag() throws {
        let data = try XCTUnwrap(CameraCapture.jpegData(from: cameraFrame(orientation: .right)))
        let decoded = try XCTUnwrap(UIImage(data: data)?.cgImage)

        XCTAssertEqual(decoded.width, 20, "pixels should be rotated, not annotated")
        XCTAssertEqual(decoded.height, 40)
    }

    func testAnAlreadyUprightPhotoIsNotRedrawn() throws {
        let data = try XCTUnwrap(CameraCapture.jpegData(from: cameraFrame(orientation: .up)))
        let decoded = try XCTUnwrap(UIImage(data: data)?.cgImage)

        XCTAssertEqual(decoded.width, 40)
        XCTAssertEqual(decoded.height, 20)
    }

    func testTheCaptureIsAJPEGTheBackendAccepts() throws {
        let data = try XCTUnwrap(CameraCapture.jpegData(from: cameraFrame(orientation: .right)))

        XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8], "JPEG magic bytes")
        XCTAssertTrue(SupportedFile.isSupported(.jpeg))
    }
}
