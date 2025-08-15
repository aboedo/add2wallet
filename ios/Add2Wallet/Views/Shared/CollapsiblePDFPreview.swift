import SwiftUI

struct CollapsiblePDFPreview: View {
    let url: URL
    @State private var isExpanded = false
    @State private var showingFullScreen = false
    
    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                // Expanded view with PDF preview
                VStack(spacing: ThemeManager.Spacing.sm) {
                    // Header with collapse button
                    HStack {
                        Text("Original PDF")
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
                                .font(.caption)
                                .foregroundColor(ThemeManager.Colors.textSecondary)
                        }
                    }
                    
                    // PDF Preview
                    PDFPreviewView(url: url)
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
                .padding(.horizontal, ThemeManager.Spacing.md)
            } else {
                // Collapsed view - compact thumbnail row
                Button {
                    ThemeManager.Haptics.light()
                    withAnimation(ThemeManager.Animations.standard) {
                        isExpanded = true
                    }
                } label: {
                    HStack(spacing: ThemeManager.Spacing.sm) {
                        // PDF thumbnail
                        PDFPreviewView(url: url)
                            .frame(width: 60, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.small))
                            .overlay(
                                RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.small)
                                    .stroke(ThemeManager.Colors.textTertiary.opacity(0.3), lineWidth: 1)
                            )
                        
                        // Content
                        VStack(alignment: .leading, spacing: ThemeManager.Spacing.xs) {
                            Text("View original PDF")
                                .font(ThemeManager.Typography.bodySemibold)
                                .foregroundColor(ThemeManager.Colors.textPrimary)
                            
                            Text("Tap to expand or view full screen")
                                .font(ThemeManager.Typography.caption)
                                .foregroundColor(ThemeManager.Colors.textSecondary)
                        }
                        
                        Spacer()
                        
                        // Expand indicator
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(ThemeManager.Colors.textSecondary)
                    }
                    .padding(ThemeManager.Spacing.md)
                    .background(ThemeManager.Colors.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.medium))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, ThemeManager.Spacing.md)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .fullScreenCover(isPresented: $showingFullScreen) {
            FullScreenPDFView(url: url)
        }
    }
}

#Preview {
    // Create a sample PDF URL for preview
    if let sampleURL = Bundle.main.url(forResource: "sample", withExtension: "pdf") {
        VStack(spacing: 20) {
            CollapsiblePDFPreview(url: sampleURL)
            
            Text("Other content below...")
                .font(.title2)
                .foregroundColor(.secondary)
        }
        .background(Color(.systemGroupedBackground))
    } else {
        Text("No sample PDF found")
    }
}