import SwiftUI
import SwiftData

/// The whole app, on one screen.
///
/// There used to be two tabs: a "Generate Pass" transaction that ended by
/// ejecting you into a "My Passes" library — via a NotificationCenter
/// broadcast, which was the tell that the split was never real. Importing is a
/// modal act, not a place, so it became a sheet and the library became home.
struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedPass.createdAt, order: .reverse) private var savedPasses: [SavedPass]
    @Binding var selection: TimelineItem?
    @State private var showingPast = false
    /// Deleting a trip removes several passes at once, so it asks first.
    @State private var pendingTripDeletion: Trip?

    private var timeline: Timeline { Timeline.build(from: savedPasses) }

    var body: some View {
        Group {
            if timeline.isEmpty {
                TimelineEmptyState()
            } else {
                content
            }
        }
        .background(Color(.systemGroupedBackground))
        .confirmationDialog(
            "Delete this trip?",
            isPresented: Binding(
                get: { pendingTripDeletion != nil },
                set: { if !$0 { pendingTripDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let trip = pendingTripDeletion {
                Button("Delete \(trip.passCount) passes", role: .destructive) {
                    delete(trip.passes)
                    pendingTripDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingTripDeletion = nil }
        } message: {
            Text("The passes already in Apple Wallet stay there. This only removes them from Add2Wallet.")
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ThemeManager.Spacing.lg) {
                if let next = timeline.next {
                    section("NEXT UP") {
                        TimelineFeatureCard(item: next)
                            .onTapGesture { select(next) }
                            .deletable(item: next, onDelete: requestDeletion)
                    }
                }

                if !timeline.upcoming.isEmpty {
                    section("COMING UP") {
                        VStack(spacing: ThemeManager.Spacing.sm) {
                            ForEach(timeline.upcoming) { item in
                                TimelineRow(item: item)
                                    .onTapGesture { select(item) }
                                    .deletable(item: item, onDelete: requestDeletion)
                            }
                        }
                    }
                }

                if !timeline.past.isEmpty { pastSection }
            }
            .padding(ThemeManager.Spacing.md)
            // Room for the Add Ticket button, so the last row is never hidden
            // behind it the way the old floating tab bar hid the last pass.
            .padding(.bottom, 88)
        }
    }

    private var pastSection: some View {
        DisclosureGroup(isExpanded: $showingPast) {
            VStack(spacing: ThemeManager.Spacing.sm) {
                ForEach(timeline.past) { item in
                    TimelineRow(item: item)
                        .onTapGesture { select(item) }
                        .deletable(item: item, onDelete: requestDeletion)
                }
            }
            .padding(.top, ThemeManager.Spacing.sm)
        } label: {
            HStack(spacing: ThemeManager.Spacing.sm) {
                Image(systemName: "clock.arrow.circlepath")
                Text("Past")
                    .font(ThemeManager.Typography.bodySemibold)
                Spacer()
                Text("\(timeline.pastPassCount) passes")
                    .font(ThemeManager.Typography.footnote)
                    .foregroundColor(ThemeManager.Colors.textTertiary)
            }
            .foregroundColor(ThemeManager.Colors.textSecondary)
        }
        .tint(ThemeManager.Colors.textSecondary)
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ThemeManager.Spacing.sm) {
            Text(title)
                .font(ThemeManager.Typography.sectionHeader)
                .foregroundColor(ThemeManager.Colors.textSecondary)
            content()
        }
    }

    /// A single pass goes straight away; a trip asks first, because one tap
    /// would otherwise take several passes with it.
    private func requestDeletion(of item: TimelineItem) {
        switch item {
        case .pass(let pass):
            delete([pass])
        case .trip(let trip):
            pendingTripDeletion = trip
        }
    }

    private func delete(_ passes: [SavedPass]) {
        ThemeManager.Haptics.medium()
        withAnimation(ThemeManager.Animations.standard) {
            for pass in passes {
                if selection?.id.contains(pass.id) == true { selection = nil }
                modelContext.delete(pass)
            }
        }
        try? modelContext.save()
    }

    private func select(_ item: TimelineItem) {
        ThemeManager.Haptics.selection()
        selection = item
    }
}

/// The one oversized element on the screen: whatever comes next in your life.
struct TimelineFeatureCard: View {
    let item: TimelineItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(Array(members.prefix(4).enumerated()), id: \.offset) { _, pass in
                Divider().padding(.leading, ThemeManager.Spacing.md)
                TimelineLegRow(pass: pass)
            }
            if members.count > 4 {
                Divider().padding(.leading, ThemeManager.Spacing.md)
                Text("+\(members.count - 4) more")
                    .font(ThemeManager.Typography.footnote)
                    .foregroundColor(ThemeManager.Colors.textSecondary)
                    .padding(ThemeManager.Spacing.md)
            }
        }
        .background(ThemeManager.Colors.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.card))
        .contentShape(RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.card))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ThemeManager.Spacing.xs) {
            HStack(alignment: .top) {
                Text(kicker)
                    .font(ThemeManager.Typography.caption)
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                if let countdown = TimelineFormatter.countdown(to: item) {
                    Text(countdown)
                        .font(ThemeManager.Typography.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, ThemeManager.Spacing.sm)
                        .padding(.vertical, ThemeManager.Spacing.xs)
                        .background(.white.opacity(0.2), in: Capsule())
                }
            }

            Text(title)
                .font(ThemeManager.Typography.title2)
                .foregroundColor(.white)
                .lineLimit(2)

            if let subtitle {
                Text(subtitle)
                    .font(ThemeManager.Typography.footnote)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
            }
        }
        .padding(ThemeManager.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent)
    }

    private var members: [SavedPass] {
        switch item {
        case .trip(let trip): return trip.passes.sorted { $0.eventDateOrFallback < $1.eventDateOrFallback }
        case .pass: return []
        }
    }

    private var kicker: String {
        switch item {
        case .trip: return "TRIP"
        case .pass(let pass): return pass.passType.uppercased()
        }
    }

    private var title: String {
        switch item {
        case .trip(let trip): return trip.name
        case .pass(let pass): return pass.displayTitle
        }
    }

    private var subtitle: String? {
        switch item {
        case .trip(let trip):
            let route = trip.itineraryCities.joined(separator: " → ")
            return route.isEmpty ? TimelineFormatter.dateLabel(for: item) : route
        case .pass(let pass):
            let venue = pass.displayVenue
            return venue.isEmpty ? TimelineFormatter.dateLabel(for: item) : venue
        }
    }

    /// The per-pass brand colour, promoted from a 3pt stripe to the identity of
    /// the card. The backend guarantees it clears AA against white text.
    private var accent: Color {
        switch item {
        case .trip(let trip):
            let first = trip.passes.min { $0.eventDateOrFallback < $1.eventDateOrFallback }
            return PassColorUtils.getPassColor(metadata: first?.metadata, passType: first?.passType ?? "")
        case .pass(let pass):
            return PassColorUtils.getPassColor(metadata: pass.metadata, passType: pass.passType)
        }
    }
}

/// One leg inside the feature card.
struct TimelineLegRow: View {
    let pass: SavedPass

    var body: some View {
        HStack(spacing: ThemeManager.Spacing.sm) {
            PassGlyph(pass: pass, size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(pass.displayTitle)
                    .font(ThemeManager.Typography.footnote)
                    .foregroundColor(ThemeManager.Colors.textPrimary)
                    .lineLimit(1)
                if let detail = TimelineFormatter.legDetail(for: pass) {
                    Text(detail)
                        .font(ThemeManager.Typography.caption)
                        .foregroundColor(ThemeManager.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: ThemeManager.Spacing.sm)

            Text(TimelineFormatter.shortDate(for: pass))
                .font(ThemeManager.Typography.caption)
                .foregroundColor(ThemeManager.Colors.textSecondary)
        }
        .padding(ThemeManager.Spacing.md)
    }
}

/// A compact row for everything that is not the next thing.
struct TimelineRow: View {
    let item: TimelineItem

    var body: some View {
        HStack(spacing: ThemeManager.Spacing.md) {
            switch item {
            case .trip(let trip):
                Image(systemName: "suitcase.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(accent, in: RoundedRectangle(cornerRadius: 10))
            case .pass(let pass):
                PassGlyph(pass: pass, size: 36)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ThemeManager.Typography.bodySemibold)
                    .foregroundColor(ThemeManager.Colors.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(ThemeManager.Typography.footnote)
                        .foregroundColor(ThemeManager.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: ThemeManager.Spacing.sm)

            VStack(alignment: .trailing, spacing: 2) {
                Text(TimelineFormatter.dateLabel(for: item))
                    .font(ThemeManager.Typography.footnote)
                    .foregroundColor(
                        item.hasKnownDate
                            ? ThemeManager.Colors.textSecondary
                            : ThemeManager.Colors.textTertiary
                    )
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(ThemeManager.Spacing.md)
        .background(ThemeManager.Colors.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.medium))
        .contentShape(RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.medium))
        .opacity(item.isPast ? 0.85 : 1)
    }

    private var title: String {
        switch item {
        case .trip(let trip): return trip.name
        case .pass(let pass): return pass.displayTitle
        }
    }

    private var subtitle: String? {
        switch item {
        case .trip(let trip):
            let cities = trip.itineraryCities.joined(separator: " → ")
            return cities.isEmpty ? "\(trip.passes.count) passes" : cities
        case .pass(let pass):
            let venue = pass.displayVenue
            return venue.isEmpty ? nil : venue
        }
    }

    private var accent: Color {
        switch item {
        case .trip(let trip):
            let first = trip.passes.min { $0.eventDateOrFallback < $1.eventDateOrFallback }
            return PassColorUtils.getPassColor(metadata: first?.metadata, passType: first?.passType ?? "")
        case .pass(let pass):
            return PassColorUtils.getPassColor(metadata: pass.metadata, passType: pass.passType)
        }
    }
}

/// With one screen and one labelled verb, the empty state is the onboarding.
struct TimelineEmptyState: View {
    var body: some View {
        VStack(spacing: ThemeManager.Spacing.md) {
            Image(systemName: "suitcase")
                .font(.system(size: 56, weight: .thin))
                .foregroundColor(ThemeManager.Colors.textTertiary)

            Text("Your trips live here")
                .font(ThemeManager.Typography.title2)
                .foregroundColor(ThemeManager.Colors.textPrimary)

            Text("Add a ticket and it turns into an Apple Wallet pass. Tickets from the same journey group into a trip on their own.")
                .font(ThemeManager.Typography.body)
                .foregroundColor(ThemeManager.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ThemeManager.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 88)
    }
}

/// The coloured glyph tile, shared by every row.
struct PassGlyph: View {
    let pass: SavedPass
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: PassColorUtils.iconName(for: pass.metadata, passType: pass.passType))
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(
                PassColorUtils.getPassColor(metadata: pass.metadata, passType: pass.passType),
                in: RoundedRectangle(cornerRadius: size * 0.28)
            )
    }
}

enum TimelineFormatter {
    /// "in 4 days", "Today", "Tomorrow" — nil when the date is unknown or past.
    static func countdown(to item: TimelineItem) -> String? {
        guard item.hasKnownDate, !item.isPast else { return nil }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: item.date)
        ).day ?? 0

        switch days {
        case ..<0: return nil
        case 0: return "Today"
        case 1: return "Tomorrow"
        default: return "in \(days) days"
        }
    }

    /// Never invents a date it does not have.
    static func dateLabel(for item: TimelineItem) -> String {
        guard item.hasKnownDate else { return "Date not\non ticket" }
        return item.date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func shortDate(for pass: SavedPass) -> String {
        guard pass.hasParseableDate else { return "—" }
        return pass.eventDateOrFallback.formatted(.dateTime.weekday(.abbreviated).day())
    }

    /// "07:20 · Seat 7A" — whatever of the leg we actually know.
    static func legDetail(for pass: SavedPass) -> String? {
        var parts: [String] = []
        if let route = pass.routeDescription { parts.append(route) }
        if let segment = pass.segments.first {
            if let time = segment.departTime { parts.append(time) }
            if let seat = segment.seatInfo { parts.append("Seat \(seat)") }
        } else if !pass.displayVenue.isEmpty {
            parts.append(pass.displayVenue)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}


private extension View {
    /// Long press to delete. `swipeActions` only works inside a `List`, and the
    /// timeline is a LazyVStack, so a swipe here would be a no-op that looks
    /// like a feature. A visible affordance in the detail screen is still owed.
    func deletable(item: TimelineItem, onDelete: @escaping (TimelineItem) -> Void) -> some View {
        contextMenu {
            Button(role: .destructive) { onDelete(item) } label: {
                Label("Delete", systemImage: "trash")
            }
        }

    }
}
