import SwiftUI

/// The import, reduced to something you can ignore.
///
/// Converting a ticket takes the better part of a minute, and the progress bar
/// used to hold the whole screen for all of it: the sheet could not be
/// dismissed, so the app was unusable until the server answered. That is a
/// modal wait for work that has nothing modal about it — nothing you do
/// elsewhere in the app affects it, and nothing about it needs your attention
/// until it finishes.
///
/// So it moves out of the way and becomes a line you can leave alone. It rides
/// above the Add Ticket bar on every screen, keeps counting, and when the pass
/// is ready it says so and waits to be tapped.
struct ImportStatusPill: View {
    let state: ImportStatus
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: ThemeManager.Spacing.sm) {
                icon

                Text(state.label)
                    .font(ThemeManager.Typography.footnote.weight(.medium))
                    .foregroundColor(ThemeManager.Colors.onBrandPrimary)
                    .lineLimit(1)

                Spacer(minLength: ThemeManager.Spacing.xs)

                // Only the finished state invites a tap, so only it advertises
                // one. A chevron next to a progress spinner would be promising
                // something that is not there yet.
                if state.isReady {
                    Image(systemName: "chevron.right")
                        .font(.system(size: ThemeManager.IconSize.inline, weight: .semibold))
                        .foregroundColor(ThemeManager.Colors.onBrandPrimary.opacity(0.7))
                }
            }
            .padding(.horizontal, ThemeManager.Spacing.md)
            .padding(.vertical, ThemeManager.Spacing.sm)
            .background(ThemeManager.Colors.brandPrimary, in: Capsule())
        }
        .buttonStyle(.plain)
        // `.disabled` would be the obvious way to say "not tappable yet", but
        // it dims the whole button — background included — and the in-flight
        // pill came out grey text on a grey capsule. Refusing the touch keeps
        // the contrast; the pill still has to be readable while it works.
        .allowsHitTesting(state.isReady)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityIdentifier("importStatusPill")
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .idle:
            EmptyView()
        case .processing:
            SwiftUI.ProgressView()
                .controlSize(.small)
                .tint(ThemeManager.Colors.onBrandPrimary)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: ThemeManager.IconSize.inline, weight: .semibold))
                .foregroundColor(ThemeManager.Colors.onBrandPrimary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: ThemeManager.IconSize.inline, weight: .semibold))
                .foregroundColor(ThemeManager.Colors.onBrandPrimary)
        }
    }
}

/// What the pill can be saying. Derived from the import model rather than
/// stored, so the two cannot disagree about what is happening.
enum ImportStatus: Equatable {
    case idle
    case processing(percent: Int)
    case ready
    case failed

    var label: String {
        switch self {
        case .idle: return ""
        case .processing(let percent): return "Creating your pass… \(percent)%"
        case .ready: return "Ready — tap to add"
        case .failed: return "Something went wrong — tap to see"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .idle: return ""
        case .processing(let percent): return "Creating your pass, \(percent) percent"
        case .ready: return "Your pass is ready. Tap to add it."
        case .failed: return "The import failed. Tap for details."
        }
    }

    /// Tappable only once there is something on the other side of the tap.
    var isReady: Bool {
        switch self {
        case .ready, .failed: return true
        case .idle, .processing: return false
        }
    }

    var isVisible: Bool { self != .idle }
}

#Preview {
    VStack(spacing: ThemeManager.Spacing.md) {
        ImportStatusPill(state: .processing(percent: 42), onTap: {})
        ImportStatusPill(state: .ready, onTap: {})
        ImportStatusPill(state: .failed, onTap: {})
    }
    .padding()
}
