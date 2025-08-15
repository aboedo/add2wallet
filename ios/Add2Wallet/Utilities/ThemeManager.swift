import SwiftUI
import Foundation

/// ThemeManager provides a comprehensive design system for Add2Wallet
/// Implements 8pt spacing grid, consistent typography, colors, and elevations
struct ThemeManager {
    
    // MARK: - Spacing System (8pt Grid)
    enum Spacing {
        static let xs: CGFloat = 4      // 0.5x
        static let sm: CGFloat = 8      // 1x base
        static let md: CGFloat = 16     // 2x
        static let lg: CGFloat = 24     // 3x
        static let xl: CGFloat = 32     // 4x
        static let xxl: CGFloat = 40    // 5x
        static let xxxl: CGFloat = 48   // 6x
        
        // Semantic spacing
        static let cardPadding = md
        static let sectionSpacing = lg
        static let componentSpacing = sm
        static let contentMargins = md
    }
    
    // MARK: - Corner Radius System
    enum CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        
        // Semantic corner radii
        static let button = small
        static let card = medium
        static let sheet = large
    }
    
    // MARK: - Typography System
    enum Typography {
        // Screen titles
        static let largeTitle = Font.system(.largeTitle, design: .default, weight: .bold)    // 34/34
        
        // Section titles
        static let title2 = Font.system(.title2, design: .default, weight: .semibold)        // 22/28
        
        // Body text and rows
        static let body = Font.system(.body, design: .default, weight: .regular)             // 17/22
        static let bodySemibold = Font.system(.body, design: .default, weight: .semibold)    // 17/22
        
        // Metadata and captions
        static let footnote = Font.system(.footnote, design: .default, weight: .regular)     // 13/18
        static let caption = Font.system(.caption, design: .default, weight: .regular)       // 12/16
        
        // Monospaced variants for dates, times, barcodes, counters
        static let bodyMonospaced = Font.system(.body, design: .monospaced, weight: .regular)
        static let footnoteMonospaced = Font.system(.footnote, design: .monospaced, weight: .regular)
        static let captionMonospaced = Font.system(.caption, design: .monospaced, weight: .regular)
        
        // Section headers
        static let sectionHeader = Font.system(.caption, design: .default, weight: .medium)
            .smallCaps()
    }
    
    // MARK: - Color System
    enum Colors {
        // Primary Brand Color (Teal from app icon)
        static let brandPrimary = Color(red: 0.125, green: 0.698, blue: 0.667) // #20B2AA equivalent
        static let brandSecondary = Color(red: 0.098, green: 0.549, blue: 0.525) // Darker teal
        
        // Surface Colors
        static let surfaceDefault = Color(.systemBackground)
        static let surfaceCard = Color(.secondarySystemBackground)
        static let surfaceCardElevated = Color(.tertiarySystemBackground)
        
        // Semantic Colors
        static let textPrimary = Color(.label)
        static let textSecondary = Color(.secondaryLabel)
        static let textTertiary = Color(.tertiaryLabel)
        
        // Interactive Colors
        static let interactive = brandPrimary
        static let interactivePressed = brandSecondary
        
        // Status Colors
        static let success = Color(.systemGreen)
        static let warning = Color(.systemOrange)
        static let error = Color(.systemRed)
        
        // Dynamic Pass Colors (fallbacks)
        static let passEventFallback = Color(.systemOrange)
        static let passConcertFallback = Color(.systemRed)
        static let passSportsFallback = Color(.systemGreen)
        static let passFlightFallback = Color(.systemBlue)
        static let passTransitFallback = Color(.systemTeal)
        static let passDefaultFallback = Color(.systemGray)
    }
    
    // MARK: - Elevation System
    enum Elevation {
        // Flat surfaces
        static let flat: some View = EmptyView()
        
        // Card elevation
        static func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
            content()
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card))
        }
        
        // Sheet elevation
        static func sheet<Content: View>(@ViewBuilder content: () -> Content) -> some View {
            content()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sheet))
        }
        
        // Button elevation
        static func button<Content: View>(@ViewBuilder content: () -> Content) -> some View {
            content()
                .background(Colors.brandPrimary)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.button))
        }
    }
    
    // MARK: - Component Styles
    enum ComponentStyle {
        // Primary CTA Button
        static func primaryButton<Content: View>(@ViewBuilder label: () -> Content) -> some View {
            label()
                .font(Typography.bodySemibold)
                .foregroundColor(.white)
                .padding(.vertical, Spacing.md)
                .padding(.horizontal, Spacing.lg)
                .frame(maxWidth: .infinity)
                .background(Colors.brandPrimary)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.button))
                .contentShape(Rectangle())
        }
        
        // Secondary Button
        static func secondaryButton<Content: View>(@ViewBuilder label: () -> Content) -> some View {
            label()
                .font(Typography.body)
                .foregroundColor(Colors.brandPrimary)
                .padding(.vertical, Spacing.sm)
                .padding(.horizontal, Spacing.md)
                .frame(maxWidth: .infinity)
                .background(Colors.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.button)
                        .stroke(Colors.brandPrimary, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        
        // Usage Pill
        static func usagePill<Content: View>(@ViewBuilder content: () -> Content) -> some View {
            content()
                .font(Typography.footnoteMonospaced)
                .foregroundColor(Colors.textSecondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Colors.surfaceCard)
                .clipShape(Capsule())
        }
        
        // Section Card
        static func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
            content()
                .padding(Spacing.cardPadding)
                .background(Colors.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card))
        }
        
        // List Row with Color Stripe
        static func listRowWithStripe<Content: View>(
            accentColor: Color,
            @ViewBuilder content: () -> Content
        ) -> some View {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(accentColor)
                    .frame(width: 4)
                
                content()
                    .padding(.leading, Spacing.sm)
            }
        }
    }
    
    // MARK: - Haptic Feedback
    enum Haptics {
        static func light() {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }
        
        static func medium() {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        }
        
        static func success() {
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.success)
        }
        
        static func selection() {
            let selectionFeedback = UISelectionFeedbackGenerator()
            selectionFeedback.selectionChanged()
        }
    }
    
    // MARK: - Animation Presets
    enum Animations {
        static let quick = Animation.easeInOut(duration: 0.2)
        static let standard = Animation.easeInOut(duration: 0.3)
        static let gentle = Animation.easeInOut(duration: 0.5)
        
        // Bounce for success states
        static let bounce = Animation.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0)
    }
}

// MARK: - View Extensions for Theme
extension View {
    func themed<Content: View>(
        @ViewBuilder content: (ThemeManager.Type) -> Content
    ) -> some View {
        content(ThemeManager.self)
    }
    
    func themedCard() -> some View {
        ThemeManager.ComponentStyle.sectionCard {
            self
        }
    }
    
    func themedPrimaryButton() -> some View {
        self
            .buttonStyle(ThemedPrimaryButtonStyle())
    }
    
    func themedSecondaryButton() -> some View {
        self
            .buttonStyle(ThemedSecondaryButtonStyle())
    }
    
    func themedUsagePill() -> some View {
        ThemeManager.ComponentStyle.usagePill {
            self
        }
    }
}

// MARK: - Button Styles
struct ThemedPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ThemeManager.Typography.bodySemibold)
            .foregroundColor(.white)
            .padding(.vertical, ThemeManager.Spacing.md)
            .padding(.horizontal, ThemeManager.Spacing.lg)
            .frame(maxWidth: .infinity)
            .background(
                configuration.isPressed 
                    ? ThemeManager.Colors.brandSecondary 
                    : ThemeManager.Colors.brandPrimary
            )
            .clipShape(RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.button))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ThemedSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ThemeManager.Typography.body)
            .foregroundColor(ThemeManager.Colors.brandPrimary)
            .padding(.vertical, ThemeManager.Spacing.sm)
            .padding(.horizontal, ThemeManager.Spacing.md)
            .frame(maxWidth: .infinity)
            .background(
                configuration.isPressed 
                    ? ThemeManager.Colors.surfaceCardElevated 
                    : ThemeManager.Colors.surfaceCard
            )
            .overlay(
                RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.button)
                    .stroke(ThemeManager.Colors.brandPrimary, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.button))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}