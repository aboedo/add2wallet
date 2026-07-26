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
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.image = UIImage(contentsOfFile: url.path)
        uiView.accessibilityLabel = url.lastPathComponent
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
