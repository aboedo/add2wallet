import SwiftUI
import SwiftData
import RevenueCatUI

/// The app's container.
///
/// One timeline, presented as a stack on iPhone and a split view on iPad.
/// The old `NavigationView` gave iPad a split it never filled — content jammed
/// into a ~480pt column with most of the screen left grey. Same data, right
/// container for the size class.
struct RootView: View {
    @EnvironmentObject var passUsageManager: PassUsageManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext

    @State private var selection: TimelineItem?
    @State private var showingImport = false
    @State private var showingSettings = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    private var isWide: Bool { horizontalSizeClass == .regular }

    var body: some View {
        Group {
            if isWide { splitLayout } else { stackLayout }
        }
        .sheet(isPresented: $showingImport) {
            ImportSheet()
        }
        .sheet(isPresented: $showingSettings) {
            CustomerCenterView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("SharedFileReceived"))) { _ in
            // A file arriving from the share extension is an import, so it
            // opens the same sheet rather than a second parallel flow.
            showingImport = true
        }
    }

    // MARK: - Layouts

    private var stackLayout: some View {
        NavigationStack {
            timeline
                .navigationDestination(item: $selection) { destination(for: $0) }
        }
    }

    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            timeline
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
        } detail: {
            NavigationStack {
                if let selection {
                    destination(for: selection)
                } else {
                    DetailPlaceholder()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var timeline: some View {
        TimelineView(selection: $selection)
            .navigationTitle("Add2Wallet")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: ThemeManager.Spacing.sm) {
                        creditsChip
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                addTicketButton
            }
    }

    /// Glanceable, never dominant. The number only matters at the moment of
    /// spending, and the import sheet says it again there.
    private var creditsChip: some View {
        Group {
            if passUsageManager.isLoadingBalance {
                SwiftUI.ProgressView().scaleEffect(0.7)
            } else {
                Text("\(passUsageManager.remainingPasses)")
                    .font(ThemeManager.Typography.footnoteMonospaced)
                    .foregroundColor(ThemeManager.Colors.textSecondary)
                    .padding(.horizontal, ThemeManager.Spacing.sm)
                    .padding(.vertical, ThemeManager.Spacing.xs)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .accessibilityLabel("\(passUsageManager.remainingPasses) credits left")
    }

    private var addTicketButton: some View {
        Button {
            ThemeManager.Haptics.light()
            showingImport = true
        } label: {
            Label("Add Ticket", systemImage: "plus")
                .font(ThemeManager.Typography.bodySemibold)
                .foregroundColor(.white)
                .padding(.vertical, ThemeManager.Spacing.md)
                .frame(maxWidth: .infinity)
                .background(
                    ThemeManager.Colors.brandPrimary,
                    in: RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.button)
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, ThemeManager.Spacing.md)
        .padding(.bottom, ThemeManager.Spacing.sm)
        .background(.bar)
    }

    @ViewBuilder
    private func destination(for item: TimelineItem) -> some View {
        switch item {
        case .trip(let trip):
            TripDetailView(trip: trip)
        case .pass(let pass):
            SavedPassDetailView(savedPass: pass, isPushed: true)
        }
    }
}

/// The iPad detail column before anything is selected. It answers "what is
/// this app" rather than sitting empty.
struct DetailPlaceholder: View {
    var body: some View {
        VStack(spacing: ThemeManager.Spacing.md) {
            Image(systemName: "ticket")
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(ThemeManager.Colors.textTertiary)
            Text("Select a trip or a pass")
                .font(ThemeManager.Typography.body)
                .foregroundColor(ThemeManager.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
