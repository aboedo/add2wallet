import SwiftUI

// MARK: - WarningsView
struct WarningsView: View {
    let warnings: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: ThemeManager.Spacing.sm) {
            ForEach(warnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: ThemeManager.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(ThemeManager.Colors.warning)
                        .font(ThemeManager.Typography.title2)
                    
                    VStack(alignment: .leading, spacing: ThemeManager.Spacing.xs) {
                        Text("Warning")
                            .font(ThemeManager.Typography.bodySemibold)
                            .foregroundColor(ThemeManager.Colors.warning)
                        
                        Text(warning)
                            .font(ThemeManager.Typography.body)
                            .foregroundColor(ThemeManager.Colors.textPrimary)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer()
                }
                .padding(ThemeManager.Spacing.md)
                .background(
                    ThemeManager.Colors.warning.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.small)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.small)
                        .stroke(ThemeManager.Colors.warning.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
}