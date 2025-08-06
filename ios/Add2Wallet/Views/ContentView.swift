import SwiftUI
import UniformTypeIdentifiers
import PassKit

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @State private var passViewController: PKAddPassesViewController?
    @State private var showingAddPassVC = false
    
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
                
                if passViewController != nil {
                    Button(action: {
                        showingAddPassVC = true
                    }) {
                        Label("Add to Wallet", systemImage: "plus.rectangle.on.folder")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationBarHidden(true)
            .onAppear {
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("PassReadyToAdd"),
                    object: nil,
                    queue: .main
                ) { notification in
                    if let userInfo = notification.userInfo,
                       let passVC = userInfo["passViewController"] as? PKAddPassesViewController {
                        self.passViewController = passVC
                    }
                }
            }
            .sheet(isPresented: $showingAddPassVC) {
                if let passVC = passViewController {
                    PassKitView(passViewController: passVC)
                }
            }
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

struct PassKitView: UIViewControllerRepresentable {
    let passViewController: PKAddPassesViewController
    
    func makeUIViewController(context: Context) -> PKAddPassesViewController {
        return passViewController
    }
    
    func updateUIViewController(_ uiViewController: PKAddPassesViewController, context: Context) {
        // No updates needed
    }
}

#Preview {
    ContentView()
}