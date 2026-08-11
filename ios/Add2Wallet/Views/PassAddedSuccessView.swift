import SwiftUI
import PassKit

struct PassAddedSuccessView: View {
    @Binding var isPresented: Bool
    let passCount: Int
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: ThemeManager.Spacing.xl) {
                Spacer()
                
                // Success icon
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: ThemeManager.IconSize.hero))
                    .foregroundColor(.green)
                    .symbolEffect(.bounce, value: isPresented)
                
                // Success message
                VStack(spacing: ThemeManager.Spacing.md) {
                    Text(passCount > 1 ? "Passes Successfully Added!" : "Pass Successfully Added!")
                        .font(ThemeManager.Typography.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text("You can view \(passCount > 1 ? "them" : "it") in Apple Wallet any time.")
                        .font(ThemeManager.Typography.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // Action buttons
                VStack(spacing: ThemeManager.Spacing.md) {
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
                            .cornerRadius(ThemeManager.CornerRadius.control)
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
                            .cornerRadius(ThemeManager.CornerRadius.control)
                            .fontWeight(.medium)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, ThemeManager.Spacing.xl)
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