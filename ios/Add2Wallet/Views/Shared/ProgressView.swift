import SwiftUI

// Progress view with time-based progress calculation
struct ProgressView: View {
    @ObservedObject var contentViewModel: ContentViewModel
    
    init(contentViewModel: ContentViewModel) {
        self.contentViewModel = contentViewModel
        self.progressViewModel = contentViewModel.progressViewModel
    }
    
    @ObservedObject private var progressViewModel: ProgressViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            // Progress bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(progressViewModel.progressMessage)
                        .font(ThemeManager.Typography.bodySemibold)
                        .foregroundColor(ThemeManager.Colors.textPrimary)
                    
                    Spacer()
                    
                    Text("\(Int(progressViewModel.progress * 100))%")
                        .font(ThemeManager.Typography.footnoteMonospaced)
                        .foregroundColor(ThemeManager.Colors.textSecondary)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.small)
                            .fill(ThemeManager.Colors.surfaceCard)
                            .frame(height: 8)
                        
                        // Progress
                        RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.small)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [ThemeManager.Colors.brandPrimary, ThemeManager.Colors.brandSecondary]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * progressViewModel.progress, height: 8)
                            .animation(ThemeManager.Animations.gentle, value: progressViewModel.progress)
                    }
                }
                .frame(height: 8)
            }
            .padding(.horizontal)
            
            // Funny phrase below progress
            if !progressViewModel.funnyPhrase.isEmpty {
                Text(progressViewModel.funnyPhrase)
                    .font(ThemeManager.Typography.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundColor(ThemeManager.Colors.textSecondary)
                    .italic()
                    .transition(.opacity)
                    .animation(ThemeManager.Animations.standard, value: progressViewModel.funnyPhrase)
            }
        }
        .padding()
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.medium)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}