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
                    ProcessingView(phrase: viewModel.funnyPhrase)
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

// Inline ProcessingView to avoid scope issues during build
struct ProcessingView: View {
    let phrase: String

    @State private var rotateRing = false
    @State private var pulseCenter = false
    @State private var phraseOpacity: Double = 0.0

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(AngularGradient(
                        gradient: Gradient(colors: [
                            Color.blue, Color.purple, Color.pink, Color.orange, Color.blue
                        ]),
                        center: .center
                    ), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(rotateRing ? 360 : 0))
                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: rotateRing)

                Image(systemName: "wand.and.stars")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                    .scaleEffect(pulseCenter ? 1.06 : 0.94)
                    .shadow(color: .yellow.opacity(0.4), radius: pulseCenter ? 16 : 6)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseCenter)
            }

            Text(phrase)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .opacity(phraseOpacity)
                .onChange(of: phrase) { _ in
                    withAnimation(.easeInOut(duration: 0.25)) { phraseOpacity = 0.0 }
                    withAnimation(.easeInOut(duration: 0.25).delay(0.25)) { phraseOpacity = 1.0 }
                }
        }
        .onAppear {
            rotateRing = true
            pulseCenter = true
            phraseOpacity = 1.0
        }
    }
}

#Preview {
    ContentView()
}