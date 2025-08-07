import SwiftUI
import PDFKit

struct PDFPreviewView: UIViewRepresentable {
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

#Preview {
    PDFPreviewView(url: URL(fileURLWithPath: "/dev/null"))
        .frame(height: 300)
        .padding()
}