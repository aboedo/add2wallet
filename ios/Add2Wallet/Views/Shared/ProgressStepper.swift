import SwiftUI

struct ProgressStepper: View {
    let progress: Double
    let progressMessage: String
    
    private let steps = [
        ("Detect", "doc.text.viewfinder", "Analyzing PDF..."),
        ("Extract", "qrcode.viewfinder", "Extracting barcodes..."),
        ("Process", "brain.head.profile", "Processing metadata..."),
        ("Review", "checkmark.seal", "Generating pass..."),
        ("Add", "wallet.pass", "Signing certificate...")
    ]
    
    private var currentStepIndex: Int {
        switch progress {
        case 0.0..<0.15:
            return 0
        case 0.15..<0.40:
            return 1
        case 0.40..<0.65:
            return 2
        case 0.65..<0.85:
            return 3
        default:
            return 4
        }
    }
    
    var body: some View {
        VStack(spacing: ThemeManager.Spacing.md) {
            // Step indicators
            HStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 0) {
                        // Step circle
                        stepCircle(for: index, step: step)
                        
                        // Connector line (except for last step)
                        if index < steps.count - 1 {
                            connectorLine(for: index)
                        }
                    }
                }
            }
            
            // Current step message
            Text(progressMessage)
                .font(ThemeManager.Typography.body)
                .foregroundColor(ThemeManager.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .animation(ThemeManager.Animations.gentle, value: progressMessage)
        }
        .themedCard()
    }
    
    @ViewBuilder
    private func stepCircle(for index: Int, step: (String, String, String)) -> some View {
        VStack(spacing: ThemeManager.Spacing.xs) {
            ZStack {
                Circle()
                    .fill(stepBackgroundColor(for: index))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .stroke(stepBorderColor(for: index), lineWidth: 2)
                    )
                
                if index < currentStepIndex {
                    // Completed step - checkmark
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .symbolEffect(.bounce, value: index < currentStepIndex)
                } else if index == currentStepIndex {
                    // Current step - animated icon
                    Image(systemName: step.1)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .symbolEffect(.pulse.wholeSymbol, options: .repeating)
                } else {
                    // Future step - static icon
                    Image(systemName: step.1)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(ThemeManager.Colors.textTertiary)
                }
            }
            
            // Step label
            Text(step.0)
                .font(ThemeManager.Typography.caption)
                .foregroundColor(stepLabelColor(for: index))
                .fontWeight(index <= currentStepIndex ? .medium : .regular)
        }
    }
    
    @ViewBuilder
    private func connectorLine(for index: Int) -> some View {
        Rectangle()
            .fill(index < currentStepIndex ? ThemeManager.Colors.brandPrimary : ThemeManager.Colors.textTertiary.opacity(0.3))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .animation(ThemeManager.Animations.standard, value: currentStepIndex)
    }
    
    private func stepBackgroundColor(for index: Int) -> Color {
        if index < currentStepIndex {
            return ThemeManager.Colors.brandPrimary
        } else if index == currentStepIndex {
            return ThemeManager.Colors.brandPrimary
        } else {
            return ThemeManager.Colors.surfaceCard
        }
    }
    
    private func stepBorderColor(for index: Int) -> Color {
        if index <= currentStepIndex {
            return ThemeManager.Colors.brandPrimary
        } else {
            return ThemeManager.Colors.textTertiary.opacity(0.3)
        }
    }
    
    private func stepLabelColor(for index: Int) -> Color {
        if index <= currentStepIndex {
            return ThemeManager.Colors.brandPrimary
        } else {
            return ThemeManager.Colors.textSecondary
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        Text("Progress Stepper Examples")
            .font(.title2)
            .fontWeight(.semibold)
        
        // Step 1
        ProgressStepper(
            progress: 0.1,
            progressMessage: "Analyzing PDF..."
        )
        
        // Step 3
        ProgressStepper(
            progress: 0.5,
            progressMessage: "Processing metadata..."
        )
        
        // Completed
        ProgressStepper(
            progress: 1.0,
            progressMessage: "Complete!"
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}