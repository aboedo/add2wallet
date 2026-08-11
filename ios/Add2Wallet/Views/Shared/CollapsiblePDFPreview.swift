import SwiftUI

struct CollapsibleFilePreview: View {
    let url: URL
    @State private var isExpanded = false
    @State private var showingFullScreen = false

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                VStack(spacing: ThemeManager.Spacing.sm) {
                    HStack {
                        Text("Original file")
                            .font(ThemeManager.Typography.bodySemibold)
                            .foregroundColor(ThemeManager.Colors.textPrimary)

                        Spacer()

                        Button {
                            ThemeManager.Haptics.selection()
                            withAnimation(ThemeManager.Animations.standard) {
                                isExpanded = false
                            }
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(ThemeManager.Typography.caption)
                                .foregroundColor(ThemeManager.Colors.textSecondary)
                        }
                    }

                    FilePreviewView(url: url)
                        .frame(height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.medium))
                        .onTapGesture {
                            ThemeManager.Haptics.light()
                            showingFullScreen = true
                        }
                        .overlay(
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Label("Tap to view full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                                        .font(ThemeManager.Typography.caption)
                                        .padding(ThemeManager.Spacing.sm)
                                        .background(.ultraThinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.small))
                                        .padding(ThemeManager.Spacing.sm)
                                }
                            }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                .themedCard()
            } else {
                Button {
                    ThemeManager.Haptics.light()
                    withAnimation(ThemeManager.Animations.standard) {
                        isExpanded = true
                    }
                } label: {
                    HStack(spacing: ThemeManager.Spacing.sm) {
                        FilePreviewView(url: url)
                            .frame(width: 60, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.small))
                            .overlay(
                                RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.small)
                                    .stroke(ThemeManager.Colors.textTertiary.opacity(0.3), lineWidth: 1)
                            )

                        VStack(alignment: .leading, spacing: ThemeManager.Spacing.xs) {
                            Text("View original file")
                                .font(ThemeManager.Typography.bodySemibold)
                                .foregroundColor(ThemeManager.Colors.textPrimary)

                            Text(url.lastPathComponent)
                                .font(ThemeManager.Typography.caption)
                                .foregroundColor(ThemeManager.Colors.textSecondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(ThemeManager.Typography.caption)
                            .foregroundColor(ThemeManager.Colors.textSecondary)
                    }
                    .padding(ThemeManager.Spacing.md)
                    .background(ThemeManager.Colors.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.medium))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .fullScreenCover(isPresented: $showingFullScreen) {
            FullScreenFileView(url: url)
        }
    }
}

// Compatibility wrapper for existing source references.
typealias CollapsiblePDFPreview = CollapsibleFilePreview

#Preview {
    if let sampleURL = Bundle.main.url(forResource: "sample", withExtension: "pdf") {
        CollapsibleFilePreview(url: sampleURL)
    } else {
        Text("No sample file found")
    }
}
