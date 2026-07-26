import SwiftUI

struct FullScreenFileView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            FilePreviewView(url: url)
                .navigationTitle(url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                        .fontWeight(.medium)
                    }
                }
                .edgesIgnoringSafeArea(.bottom)
        }
    }
}

typealias FullScreenPDFView = FullScreenFileView
