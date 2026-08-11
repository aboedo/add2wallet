import SwiftUI
import UIKit

/// The camera, as one photo handed back as bytes.
///
/// `UIImagePickerController` rather than an AVFoundation session: the whole
/// requirement is a single still with the system's own shutter, review and
/// retake. Building that on a capture session is a few hundred lines to arrive
/// back where we started, and this one is still the shortest path to a photo.
struct CameraCapture: UIViewControllerRepresentable {
    /// JPEG bytes of the photo, or nil when the person backed out.
    let onCapture: (Data?) -> Void

    /// High, on purpose. The barcode scanner reads at several DPIs and fine
    /// bars are the first thing a hard compression eats.
    private static let jpegQuality: CGFloat = 0.9

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraCapture

        init(_ parent: CameraCapture) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
            parent.onCapture(image.flatMap(CameraCapture.jpegData))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCapture(nil)
        }
    }

    /// Upright pixels, not an orientation tag.
    ///
    /// A photo taken in portrait comes back as landscape pixels plus
    /// `imageOrientation`, and `jpegData` records that as EXIF rather than
    /// rotating anything. iOS honours the tag; the server's rendering and the
    /// model reading the image do not have to, and a ticket that arrives
    /// sideways reads as an unrecognisable document rather than a bad photo.
    static func jpegData(from image: UIImage) -> Data? {
        guard image.imageOrientation != .up else {
            return image.jpegData(compressionQuality: jpegQuality)
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        let upright = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return upright.jpegData(compressionQuality: jpegQuality)
    }
}
