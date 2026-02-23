import SwiftUI

struct HeroCardStack: View {
    let remainingPasses: Int
    let isLoadingBalance: Bool
    let passColor: Color?
    var isProcessing: Bool = false
    let onSelectPDF: () -> Void
    let onSamplePDF: () -> Void
    @State private var buttonBounce = 0
    
    var body: some View {
        VStack(spacing: ThemeManager.Spacing.md) {
            // Top: App name + value prop
            VStack(spacing: ThemeManager.Spacing.xs) {
                Text("Add2Wallet")
                    .font(ThemeManager.Typography.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Convert PDFs to Apple Wallet passes")
                    .font(ThemeManager.Typography.body)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
            
            // Middle: Primary button — changes copy when processing
            Button(action: {
                ThemeManager.Haptics.light()
                buttonBounce += 1
                onSelectPDF()
            }) {
                Label(
                    isProcessing ? "PDF uploaded, processing…" : "Select PDF",
                    systemImage: isProcessing ? "arrow.trianglehead.2.clockwise" : "doc.text.fill"
                )
                    .font(ThemeManager.Typography.bodySemibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ThemeManager.Spacing.md)
                    .background(
                        .white.opacity(0.2),
                        in: RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.medium)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.medium)
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
                    .symbolEffect(.bounce, value: buttonBounce)
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
            
            // Usage counter
            HStack {
                Spacer()
                
                if isLoadingBalance {
                    SwiftUI.ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white.opacity(0.8))
                } else {
                    Text("\(remainingPasses) passes left")
                        .font(ThemeManager.Typography.footnoteMonospaced)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, ThemeManager.Spacing.sm)
                        .padding(.vertical, ThemeManager.Spacing.xs)
                        .background(
                            .white.opacity(0.15),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(.white.opacity(0.2), lineWidth: 1)
                        )
                }
            }
        }
        .padding(ThemeManager.Spacing.cardPadding)
        .background(
            LinearGradient(
                colors: [
                    passColor?.opacity(0.8) ?? ThemeManager.Colors.brandPrimary,
                    passColor ?? ThemeManager.Colors.brandSecondary
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.card))
    }
}

#Preview {
    VStack(spacing: 20) {
        HeroCardStack(
            remainingPasses: 9,
            isLoadingBalance: false,
            passColor: nil,
            onSelectPDF: { print("Select PDF") },
            onSamplePDF: { print("Sample PDF") }
        )
        
        HeroCardStack(
            remainingPasses: 5,
            isLoadingBalance: false,
            passColor: .purple,
            onSelectPDF: { print("Select PDF") },
            onSamplePDF: { print("Sample PDF") }
        )
        
        Text("Other content below...")
            .font(.title2)
            .foregroundColor(.secondary)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}