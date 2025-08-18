import SwiftUI

// Progress view with non-linear animation
struct ProgressView: View {
    @ObservedObject var viewModel: ContentViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            // Progress bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(viewModel.progressMessage)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("\(Int(viewModel.progress * 100))%")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)
                        
                        // Progress
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [ThemeManager.Colors.brandPrimary, ThemeManager.Colors.brandSecondary]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * viewModel.progress, height: 8)
                            .animation(.easeInOut(duration: 0.15), value: viewModel.progress)
                    }
                }
                .frame(height: 8)
            }
            .padding(.horizontal)
            
            // Funny phrase below progress
            if !viewModel.funnyPhrase.isEmpty {
                Text(viewModel.funnyPhrase)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .italic()
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.15), value: viewModel.funnyPhrase)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
        .padding(.horizontal)
    }
}