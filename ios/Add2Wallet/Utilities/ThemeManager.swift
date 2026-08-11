import SwiftUI
import Foundation

/// ThemeManager provides a comprehensive design system for Add2Wallet
/// Implements 8pt spacing grid, consistent typography, colors, and elevations
struct ThemeManager {
    
    // MARK: - Spacing System (8pt Grid)
    enum Spacing {
        /// Hairline gap between a label and the value it belongs to. Below the
        /// grid on purpose: at 4pt a caption stops reading as attached to the
        /// line above it and starts looking like its own row.
        static let hairline: CGFloat = 2
        static let xs: CGFloat = 4      // 0.5x
        static let sm: CGFloat = 8      // 1x base
        static let md: CGFloat = 16     // 2x
        static let lg: CGFloat = 24     // 3x
        static let xl: CGFloat = 32     // 4x
        static let xxl: CGFloat = 40    // 5x
        static let xxxl: CGFloat = 48   // 6x
        
        /// Room at the bottom of a scroll view for the floating Add Ticket bar
        /// to hover over without covering the last row. Not a grid step — it is
        /// the measured height of a control plus its margin, and it belongs
        /// here so the two screens that need it cannot drift apart.
        static let floatingBarClearance: CGFloat = 88

        // Semantic spacing
        static let cardPadding = md
        static let sectionSpacing = lg
        static let componentSpacing = sm
        static let contentMargins = md
    }
    
    // MARK: - Corner Radius System (iOS 26 Liquid Glass)
    ///
    /// Three sizes, and a rule for nesting them.
    ///
    /// The rule is Apple's: a shape inside another shape should be
    /// *concentric* — its radius is the parent's radius minus the padding
    /// between them, so the two curves stay parallel instead of drifting. iOS
    /// 26 ships `.rect(cornerRadius: .containerConcentric)` for this, but the
    /// deployment target here is iOS 17, so `concentric(inside:inset:)` does
    /// the same arithmetic by hand.
    ///
    /// Everything that draws a rounded corner should name one of these. Loose
    /// literals had drifted to 10 and 12 in six different files, which is what
    /// made surfaces of the same rank look unrelated: a radius-10 map sitting
    /// inside a radius-20 card reads as square next to it.
    enum CornerRadius {
        /// Small square-ish things: type glyphs, thumbnails.
        static let small: CGFloat = 12
        /// Standard Liquid Glass radius. Cards, rows, buttons.
        static let medium: CGFloat = 16
        /// Sheets and the top-level detail card.
        static let large: CGFloat = 20

        // Semantic aliases. Prefer these at call sites: they say what the
        // shape is, so the scale can move without a find-and-replace.
        static let button = medium
        static let card = medium
        static let sheet = large
        /// Controls sitting *inside* a card — one step down from the card.
        static let control = small
        static let circular: CGFloat = 999

        /// A rounded rect nested inside another, keeping the curves parallel.
        ///
        /// Floors at zero: once the padding exceeds the parent's radius the
        /// concentric answer is a square corner, and forcing a curve there is
        /// what makes nested shapes look like they belong to different apps.
        static func concentric(inside parent: CGFloat, inset: CGFloat) -> CGFloat {
            max(0, parent - inset)
        }

        /// iOS draws app-icon-shaped squircles at roughly 22–23% of their side.
        /// Pass glyphs mimic app icons, so they follow the same ratio rather
        /// than a fixed radius that only looks right at one size.
        static func glyph(for size: CGFloat) -> CGFloat {
            size * 0.28
        }
    }
    
    // MARK: - Typography System
    enum Typography {
        // Screen titles
        static let largeTitle = Font.system(.largeTitle, design: .default, weight: .bold)    // 34/34
        
        // Section titles
        static let title2 = Font.system(.title2, design: .default, weight: .semibold)        // 22/28
        static let title3 = Font.system(.title3, design: .default, weight: .semibold)        // 20/25

        /// Between body and footnote. Reached for constantly in the metadata
        /// rows, which is why it had to be named: ten call sites were writing
        /// `.subheadline` directly because the scale had no word for it.
        static let subheadline = Font.system(.subheadline, design: .default, weight: .regular)

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

    // MARK: - Icon Sizes
    ///
    /// SF Symbols are sized in points, not text styles, so they never went
    /// through `Typography` and nothing kept them honest. The app had grown
    /// thirteen different sizes — 13, 15, 18, 20, 22, 24 for inline glyphs and
    /// 48, 56, 60, 64, 80, 100 for empty-state art — most of them a point or
    /// two from each other and none of them chosen against the rest.
    ///
    /// Symbols that sit next to text scale with it, via `.imageScale`; these
    /// are for the ones that stand alone.
    enum IconSize {
        /// Inline with a line of text — chips, timeline rows.
        static let inline: CGFloat = 15
        /// A symbol acting as a small label's icon.
        static let small: CGFloat = 18
        /// The icon in a tappable card or list glyph.
        static let medium: CGFloat = 22
        /// A feature icon: onboarding rows, section markers.
        static let large: CGFloat = 28
        /// Empty states — the big thin symbol with nothing else on screen.
        static let hero: CGFloat = 64

        /// Pass glyphs draw their symbol at half the tile, the way an app icon
        /// fills its own square.
        static func inTile(_ tile: CGFloat) -> CGFloat { tile * 0.5 }
    }
    
    // MARK: - Color System
    enum Colors {
        // Primary Brand Color (Teal from app icon)
        // The app has no colour of its own. Every pass arrives carrying a
        // brand colour the backend inferred from the document, and a teal app
        // sitting next to a Benfica-crimson card was two brands competing for
        // the same screen with no hierarchy between them. Ink is the absence of
        // a choice, which is exactly what you want when the content brings its
        // own — and nothing clashes with black.
        static let brandPrimary = Color(.label)
        static let brandSecondary = Color(.secondaryLabel)

        // The only correct foreground for anything sitting *on* brandPrimary.
        // Ink inverts with the appearance — black in light mode, white in dark
        // — so every hardcoded white label on an ink surface disappeared the
        // moment the phone went dark. This inverts with it, which is also how
        // iOS draws its own prominent buttons: dark pill/light text in light
        // mode, light pill/dark text in dark mode.
        static let onBrandPrimary = Color(.systemBackground)

        // Fill for a row of equal-weight chips that includes a `PasteButton`.
        // It has to be dark in *both* appearances, which is not a style choice:
        // `PasteButton` and `.borderedProminent` both draw a **white** label no
        // matter what the tint is, so a light fill (`surfaceCard`) makes the
        // label disappear in light mode. Dark in light mode, one step up from
        // the sheet in dark mode, white label legible on both.
        static let sourceChip = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? .secondarySystemBackground : .label
        })

        // Surface Colors
        static let surfaceDefault = Color(.systemBackground)
        static let surfaceCard = Color(.secondarySystemBackground)
        // For a card sitting on a *grouped* background. `surfaceCard` and
        // `systemGroupedBackground` resolve to the same #F2F2F7 in light mode,
        // so a `surfaceCard` card on a grouped screen is invisible until the
        // phone goes dark. This is the pairing UIKit intends for that case.
        static let surfaceCardGrouped = Color(.secondarySystemGroupedBackground)
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
        
        // Card elevation (iOS 26 Glass)
        static func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
            content()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.card))
        }
        
        // Sheet elevation (iOS 26 Glass)
        static func sheet<Content: View>(@ViewBuilder content: () -> Content) -> some View {
            content()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.sheet))
        }
        
        // Button elevation (iOS 26 Glass)
        static func button<Content: View>(@ViewBuilder content: () -> Content) -> some View {
            content()
                .background(Colors.brandPrimary, in: RoundedRectangle(cornerRadius: CornerRadius.button))
        }
    }
    
    // MARK: - Glass Effects (iOS 26 Liquid Glass)
    ///
    /// Apple's rules, and where we stand against them:
    /// 1. Glass is for the navigation layer floating above content — never for
    ///    the content itself. Content cards are opaque (see `sectionCard`).
    /// 2. Never stack glass on glass, so nothing inside a sheet gets it.
    /// 3. Tint only primary actions.
    /// 4. Accessibility (Reduce Transparency) is handled by the system; do not
    ///    hand-roll fallbacks.
    ///
    /// The deployment target is iOS 17, so the real `glassEffect` API is used
    /// where it exists and a material stands in below that.
    enum GlassEffect {
        // Glass effect view modifier helper
        static func regular<Content: View>(@ViewBuilder content: () -> Content) -> some View {
            content()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
        }
        
        static func interactive<Content: View>(@ViewBuilder content: () -> Content) -> some View {
            content()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
        }
        
        static func floating<Content: View>(@ViewBuilder content: () -> Content) -> some View {
            content()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
    }
    
    // MARK: - Component Styles
    enum ComponentStyle {
        // Primary CTA Button (iOS 26 Glass)
        static func primaryButton<Content: View>(@ViewBuilder label: () -> Content) -> some View {
            label()
                .font(Typography.bodySemibold)
                .foregroundColor(Colors.onBrandPrimary)
                .padding(.vertical, Spacing.md)
                .padding(.horizontal, Spacing.lg)
                .frame(maxWidth: .infinity)
                .background(Colors.brandPrimary, in: RoundedRectangle(cornerRadius: CornerRadius.button))
                .contentShape(RoundedRectangle(cornerRadius: CornerRadius.button))
        }
        
        // Secondary Button (iOS 26 Glass)
        static func secondaryButton<Content: View>(@ViewBuilder label: () -> Content) -> some View {
            label()
                .font(Typography.body)
                .foregroundColor(Colors.brandPrimary)
                .padding(.vertical, Spacing.sm)
                .padding(.horizontal, Spacing.md)
                .frame(maxWidth: .infinity)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.button))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.button)
                        .stroke(Colors.brandPrimary, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: CornerRadius.button))
        }
        
        // Usage Pill (iOS 26 Circular)
        static func usagePill<Content: View>(@ViewBuilder content: () -> Content) -> some View {
            content()
                .font(Typography.footnoteMonospaced)
                .foregroundColor(Colors.textSecondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(.ultraThinMaterial, in: Capsule())
        }
        
        // Section Card (iOS 26 Glass)
        /// A content card. Deliberately **opaque**: Apple's guidance is that
        /// Liquid Glass belongs to the navigation layer that floats above the
        /// content, never to the content itself. Glass here also meant glass on
        /// glass once a card sat inside a sheet, which is the other rule it
        /// breaks. Solid keeps the hierarchy legible: content is the substrate,
        /// controls float over it.
        static func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
            content()
                .padding(Spacing.cardPadding)
                .background(Colors.surfaceCard, in: RoundedRectangle(cornerRadius: CornerRadius.card))
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

// MARK: - Button Styles (iOS 26 Liquid Glass)
struct ThemedPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ThemeManager.Typography.bodySemibold)
            .foregroundColor(ThemeManager.Colors.onBrandPrimary)
            .padding(.vertical, ThemeManager.Spacing.md)
            .padding(.horizontal, ThemeManager.Spacing.lg)
            .frame(maxWidth: .infinity)
            // Pressed used to drop to `brandSecondary`, a 60%-alpha ink that
            // let the background bleed through and pulled the label down to
            // ~2.7:1. Dimming the solid ink keeps the fill opaque, so the
            // contrast ratio survives the press in both appearances.
            .background(
                ThemeManager.Colors.brandPrimary
                    .opacity(configuration.isPressed ? 0.82 : 1.0),
                in: RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.button)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(ThemeManager.Animations.quick, value: configuration.isPressed)
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
                    ? .regularMaterial 
                    : .thinMaterial,
                in: RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.button)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.button)
                    .stroke(ThemeManager.Colors.brandPrimary, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(ThemeManager.Animations.quick, value: configuration.isPressed)
    }
}