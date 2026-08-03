import SwiftUI
import PDFKit
import UIKit

struct FilePreviewView: View {
    let url: URL

    var body: some View {
        Group {
            if SupportedFile.isImage(url) {
                ImageFilePreviewView(url: url)
            } else {
                PDFFilePreviewView(url: url)
            }
        }
        .background(Color(.secondarySystemBackground))
    }
}

private struct PDFFilePreviewView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView(frame: .zero)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .secondarySystemBackground
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document == nil || uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
            uiView.autoScales = true
        }
    }
}

private struct ImageFilePreviewView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .secondarySystemBackground
        // A bare UIImageView reports the pixel size of its image as its intrinsic
        // content size. Left alone, a tall screenshot demands its full width from
        // SwiftUI and blows out every ancestor's layout.
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.image = UIImage(contentsOfFile: url.path)
        uiView.accessibilityLabel = url.lastPathComponent
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        // .scaleAspectFit letterboxes the image inside whatever we are given, so
        // take the proposal rather than the image's pixel dimensions. Only when a
        // dimension is genuinely unconstrained do we derive it from the aspect ratio.
        let size = uiView.image?.size ?? .zero
        let aspect = size.height > 0 ? size.width / size.height : 1

        switch (proposal.width, proposal.height) {
        case let (width?, height?) where width.isFinite && height.isFinite:
            return CGSize(width: width, height: height)
        case let (width?, _) where width.isFinite:
            return CGSize(width: width, height: width / aspect)
        case let (_, height?) where height.isFinite:
            return CGSize(width: height * aspect, height: height)
        default:
            return size == .zero ? nil : size
        }
    }
}

// Compatibility wrapper for older previews and call sites.
struct PDFPreviewView: View {
    let url: URL

    var body: some View {
        FilePreviewView(url: url)
    }
}

#Preview {
    FilePreviewView(url: URL(fileURLWithPath: "/dev/null"))
        .frame(height: 300)
        .padding()
}
