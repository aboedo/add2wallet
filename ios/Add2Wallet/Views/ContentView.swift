import SwiftUI

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
                        
                        Text("Or use the Share Extension from any app")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
        }
    }
}

#Preview {
    ContentView()
}