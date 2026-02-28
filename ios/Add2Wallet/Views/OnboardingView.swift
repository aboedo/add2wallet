import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var currentPage = 0

    var body: some View {
        VStack(spacing: 0) {
            if currentPage == 0 {
                welcomePage
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            } else {
                howToUsePage
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            }
        }
        .background(ThemeManager.Colors.surfaceDefault)
        .interactiveDismissDisabled()
    }

    // MARK: - Screen 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: ThemeManager.Spacing.lg) {
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [ThemeManager.Colors.brandPrimary, ThemeManager.Colors.brandSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(spacing: ThemeManager.Spacing.sm) {
                    Text("Turn tickets into\nWallet passes")
                        .font(ThemeManager.Typography.largeTitle)
                        .foregroundColor(ThemeManager.Colors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Add2Wallet converts your PDF tickets, event passes, and boarding passes into Apple Wallet passes — so they're always one tap away.")
                        .font(ThemeManager.Typography.body)
                        .foregroundColor(ThemeManager.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, ThemeManager.Spacing.lg)
                }
            }

            Spacer()

            Button {
                ThemeManager.Haptics.light()
                withAnimation(ThemeManager.Animations.standard) {
                    currentPage = 1
                }
            } label: {
                Text("Next")
            }
            .themedPrimaryButton()
            .padding(.horizontal, ThemeManager.Spacing.lg)
            .padding(.bottom, ThemeManager.Spacing.xxl)
        }
        .padding(.horizontal, ThemeManager.Spacing.md)
    }

    // MARK: - Screen 2: How to Use

    private var howToUsePage: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: ThemeManager.Spacing.xl) {
                // Method 1 — Share
                methodCard(
                    icon: "square.and.arrow.up",
                    title: "Share",
                    description: "From any app, tap Share \u{2192} Add2Wallet",
                    detail: "Mail, Safari, Files"
                )

                // Method 2 — Upload
                methodCard(
                    icon: "arrow.up.doc.fill",
                    title: "Upload",
                    description: "Tap + in the app and pick a PDF from Files",
                    detail: nil
                )

                // Result
                HStack(spacing: ThemeManager.Spacing.sm) {
                    Image(systemName: "wallet.pass")
                        .font(.system(size: 20))
                        .foregroundColor(ThemeManager.Colors.brandPrimary)
                        .frame(width: 36, height: 36)

                    Text("Your passes are saved in the My Passes tab and added directly to Apple Wallet")
                        .font(ThemeManager.Typography.footnote)
                        .foregroundColor(ThemeManager.Colors.textSecondary)
                }
                .padding(.horizontal, ThemeManager.Spacing.md)
            }

            Spacer()

            Button {
                ThemeManager.Haptics.success()
                onComplete()
            } label: {
                Text("Get Started")
            }
            .themedPrimaryButton()
            .padding(.horizontal, ThemeManager.Spacing.lg)
            .padding(.bottom, ThemeManager.Spacing.xxl)
        }
        .padding(.horizontal, ThemeManager.Spacing.md)
    }

    // MARK: - Method Card

    private func methodCard(icon: String, title: String, description: String, detail: String?) -> some View {
        HStack(spacing: ThemeManager.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(
                    ThemeManager.Colors.brandPrimary,
                    in: RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.small)
                )

            VStack(alignment: .leading, spacing: ThemeManager.Spacing.xs) {
                Text(title)
                    .font(ThemeManager.Typography.bodySemibold)
                    .foregroundColor(ThemeManager.Colors.textPrimary)

                Text(description)
                    .font(ThemeManager.Typography.footnote)
                    .foregroundColor(ThemeManager.Colors.textSecondary)

                if let detail {
                    Text(detail)
                        .font(ThemeManager.Typography.caption)
                        .foregroundColor(ThemeManager.Colors.textTertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(ThemeManager.Spacing.cardPadding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.card))
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
