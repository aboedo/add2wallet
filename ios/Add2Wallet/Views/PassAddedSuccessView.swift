import SwiftUI
import PassKit

struct PassAddedSuccessView: View {
    @Binding var isPresented: Bool
    let passCount: Int
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()
                
                // Success icon
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 100))
                    .foregroundColor(.green)
                    .symbolEffect(.bounce, value: isPresented)
                
                // Success message
                VStack(spacing: 12) {
                    Text(passCount > 1 ? "Passes Successfully Added!" : "Pass Successfully Added!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text("You can view \(passCount > 1 ? "them" : "it") in Apple Wallet any time.")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 16) {
                    Button(action: {
                        // Open Apple Wallet
                        if let url = URL(string: "shoebox://") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Label("Open in Wallet", systemImage: "wallet.pass")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .fontWeight(.semibold)
                    }
                    
                    Button(action: {
                        onDismiss()
                        isPresented = false
                    }) {
                        Text("OK")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                            .fontWeight(.medium)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .navigationBarHidden(true)
            .background(
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.systemGray6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
        }
    }
}

#Preview {
    PassAddedSuccessView(
        isPresented: .constant(true),
        passCount: 1,
        onDismiss: {}
    )
}