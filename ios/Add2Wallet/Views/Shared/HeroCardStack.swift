import SwiftUI
import UniformTypeIdentifiers

struct HeroCardStack: View {
    let remainingPasses: Int
    let isLoadingBalance: Bool
    let passColor: Color?
    var isProcessing: Bool = false
    let onSelectPDF: () -> Void
    let onSamplePDF: () -> Void
    var onSelectPhoto: () -> Void = {}
    var onPaste: ([NSItemProvider]) -> Void = { _ in }
    @State private var buttonBounce = 0

    /// Everything drawn on this card, and the card's own fill, are two halves
    /// of one decision. A pass colour is always saturated and dark enough that
    /// white reads on it. Ink is not: it flips to white in dark mode, and the
    /// hardcoded white content that used to sit on top vanished into it — a
    /// white card with white text, which is exactly the "no contrast" this was
    /// reported as. So the foreground follows the fill instead of assuming it.
    private var onCard: Color {
        passColor == nil ? ThemeManager.Colors.onBrandPrimary : .white
    }

    var body: some View {
        VStack(spacing: ThemeManager.Spacing.md) {
            // Top: App name + value prop
            VStack(spacing: ThemeManager.Spacing.xs) {
                Text("Add2Wallet")
                    .font(ThemeManager.Typography.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(onCard)

                Text("Convert PDFs and images to Apple Wallet passes")
                    .font(ThemeManager.Typography.body)
                    .foregroundColor(onCard.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
            
            // Middle: Primary button — changes copy when processing
            Button(action: {
                ThemeManager.Haptics.light()
                buttonBounce += 1
                onSelectPDF()
            }) {
                Label(
                    isProcessing ? "File uploaded, processing…" : "Select File",
                    systemImage: isProcessing ? "arrow.trianglehead.2.clockwise" : "doc.text.fill"
                )
                    .font(ThemeManager.Typography.bodySemibold)
                    .foregroundColor(onCard)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ThemeManager.Spacing.md)
                    .background(
                        onCard.opacity(0.2),
                        in: RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.medium)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.medium)
                            .stroke(onCard.opacity(0.3), lineWidth: 1)
                    )
                    .symbolEffect(.bounce, value: buttonBounce)
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
            .accessibilityIdentifier("selectFileButton")

            // Secondary sources — Photos and clipboard, so Files isn't the only way in
            HStack(spacing: ThemeManager.Spacing.sm) {
                Button(action: {
                    ThemeManager.Haptics.light()
                    onSelectPhoto()
                }) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                        .secondarySourceButton(tint: onCard)
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
                .accessibilityIdentifier("selectFromPhotosButton")

                PasteButton(supportedContentTypes: SupportedFile.contentTypes) { providers in
                    ThemeManager.Haptics.light()
                    onPaste(providers)
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.roundedRectangle(radius: ThemeManager.CornerRadius.medium))
                .tint(onCard.opacity(0.2))
                .disabled(isProcessing)
                .accessibilityIdentifier("pasteFileButton")
            }
            .font(ThemeManager.Typography.footnote)

            // Usage counter
            HStack {
                Spacer()
                
                if isLoadingBalance {
                    SwiftUI.ProgressView()
                        .scaleEffect(0.8)
                        .tint(onCard.opacity(0.8))
                } else {
                    Text("\(remainingPasses) credits left")
                        .font(ThemeManager.Typography.footnoteMonospaced)
                        .foregroundColor(onCard.opacity(0.8))
                        .padding(.horizontal, ThemeManager.Spacing.sm)
                        .padding(.vertical, ThemeManager.Spacing.xs)
                        .background(
                            onCard.opacity(0.15),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(onCard.opacity(0.2), lineWidth: 1)
                        )
                }
            }
        }
        .padding(ThemeManager.Spacing.cardPadding)
        // Ink, not a brand gradient. When a pass has been picked its own
        // colour takes over; until then the card stays out of the way.
        .background(
            LinearGradient(
                colors: [
                    passColor?.opacity(0.85) ?? ThemeManager.Colors.brandPrimary,
                    passColor ?? ThemeManager.Colors.brandPrimary.opacity(0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.card))
    }
}

private extension View {
    /// Matches the translucent look of the hero card's primary button, one step
    /// quieter. `tint` is whatever reads on the card underneath — see
    /// `HeroCardStack.onCard`; it is not always white.
    func secondarySourceButton(tint: Color) -> some View {
        self
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, ThemeManager.Spacing.sm)
            .background(
                tint.opacity(0.15),
                in: RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.medium)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.medium)
                    .stroke(tint.opacity(0.25), lineWidth: 1)
            )
    }
}

#Preview {
    VStack(spacing: ThemeManager.Spacing.lg) {
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
            .font(ThemeManager.Typography.title2)
            .foregroundColor(.secondary)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}