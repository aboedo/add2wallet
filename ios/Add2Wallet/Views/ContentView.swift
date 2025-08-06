import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Add2Wallet")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Convert PDFs to Apple Wallet passes")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if viewModel.isProcessing {
                    ProgressView("Processing...")
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    VStack(spacing: 16) {
                        Button(action: {
                            viewModel.selectPDF()
                        }) {
                            Label("Select PDF", systemImage: "doc.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        
                        VStack(spacing: 8) {
                            Text("Or use the Share Extension from any app")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("Open a PDF in Files, Safari, or any app and tap the Share button, then select \"Add to Wallet\"")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                }
                
                if let message = viewModel.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(viewModel.hasError ? .red : .green)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                
                Spacer()
            }
            .padding()
            .navigationBarHidden(true)
            .fileImporter(
                isPresented: $viewModel.showingDocumentPicker,
                allowedContentTypes: [UTType.pdf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        viewModel.handleSelectedDocument(url: url)
                    }
                case .failure(let error):
                    viewModel.statusMessage = "Error selecting PDF: \(error.localizedDescription)"
                    viewModel.hasError = true
                }
            }
        }
    }
}

#Preview {
    ContentView()
}