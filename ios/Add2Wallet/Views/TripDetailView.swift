import SwiftUI

/// A journey, day by day.
///
/// On iPhone this is a single column. On iPad the detail column has room the
/// phone does not, so the itinerary keeps the left and a map plus the trip's
/// facts pin to a right rail — the space that used to be empty grey.
struct TripDetailView: View {
    let trip: Trip
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isWide: Bool { horizontalSizeClass == .regular }

    private var legsByDay: [(day: Date, passes: [SavedPass])] {
        let sorted = trip.passes.sorted { $0.eventDateOrFallback < $1.eventDateOrFallback }
        let grouped = Dictionary(grouping: sorted) {
            Calendar.current.startOfDay(for: $0.eventDateOrFallback)
        }
        return grouped.keys.sorted().map { (day: $0, passes: grouped[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            if isWide {
                HStack(alignment: .top, spacing: ThemeManager.Spacing.lg) {
                    itinerary.frame(maxWidth: .infinity, alignment: .leading)
                    rail.frame(width: 300)
                }
                .padding(ThemeManager.Spacing.md)
            } else {
                VStack(alignment: .leading, spacing: ThemeManager.Spacing.lg) {
                    itinerary
                    rail
                }
                .padding(ThemeManager.Spacing.md)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Itinerary

    private var itinerary: some View {
        VStack(alignment: .leading, spacing: ThemeManager.Spacing.lg) {
            ForEach(legsByDay, id: \.day) { day in
                VStack(alignment: .leading, spacing: ThemeManager.Spacing.sm) {
                    Text(dayLabel(for: day.day, passes: day.passes))
                        .font(ThemeManager.Typography.sectionHeader)
                        .foregroundColor(ThemeManager.Colors.textSecondary)

                    ForEach(day.passes) { pass in
                        NavigationLink {
                            SavedPassDetailView(savedPass: pass, isPushed: true)
                        } label: {
                            TripLegCard(pass: pass)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Undated passes are listed rather than hidden, and say so.
    private func dayLabel(for day: Date, passes: [SavedPass]) -> String {
        guard passes.contains(where: \.hasParseableDate) else { return "NO DATE ON TICKET" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            .uppercased()
    }

    // MARK: - Rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: ThemeManager.Spacing.md) {
            TripRouteStrip(trip: trip)

            VStack(spacing: 0) {
                factRow("DATES", value: dateRange)
                Divider()
                factRow("TICKETS", value: "\(trip.passCount)")
                if !trip.itineraryCities.isEmpty {
                    Divider()
                    factRow("PLACES", value: trip.itineraryCities.joined(separator: " → "))
                }
            }
            .background(ThemeManager.Colors.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.card))
        }
    }

    private func factRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(ThemeManager.Typography.caption)
                .foregroundColor(ThemeManager.Colors.textTertiary)
            Spacer(minLength: ThemeManager.Spacing.md)
            Text(value)
                .font(ThemeManager.Typography.footnote)
                .foregroundColor(ThemeManager.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(ThemeManager.Spacing.md)
    }

    private var dateRange: String {
        let dated = trip.passes.filter(\.hasParseableDate)
        guard !dated.isEmpty else { return "Not on tickets" }
        let start = trip.startDate.formatted(.dateTime.month(.abbreviated).day())
        let end = trip.endDate.formatted(.dateTime.month(.abbreviated).day().year())
        return start == end ? end : "\(start) – \(end)"
    }
}

/// One leg: the route and the facts that distinguish it from the next.
struct TripLegCard: View {
    let pass: SavedPass

    var body: some View {
        HStack(spacing: ThemeManager.Spacing.md) {
            PassGlyph(pass: pass, size: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(pass.displayTitle)
                    .font(ThemeManager.Typography.bodySemibold)
                    .foregroundColor(ThemeManager.Colors.textPrimary)
                    .lineLimit(2)

                if let route = pass.routeDescription {
                    Text(route)
                        .font(ThemeManager.Typography.footnote)
                        .foregroundColor(ThemeManager.Colors.textSecondary)
                } else if !pass.displayVenue.isEmpty {
                    Text(pass.displayVenue)
                        .font(ThemeManager.Typography.footnote)
                        .foregroundColor(ThemeManager.Colors.textSecondary)
                        .lineLimit(2)
                }

                if !chips.isEmpty {
                    HStack(spacing: ThemeManager.Spacing.xs) {
                        ForEach(chips, id: \.self) { chip in
                            Text(chip)
                                .font(ThemeManager.Typography.caption)
                                .padding(.horizontal, ThemeManager.Spacing.sm)
                                .padding(.vertical, 2)
                                .background(ThemeManager.Colors.textTertiary.opacity(0.15), in: Capsule())
                                .foregroundColor(ThemeManager.Colors.textSecondary)
                        }
                    }
                }
            }

            Spacer(minLength: ThemeManager.Spacing.sm)

            Text(TimelineFormatter.shortDate(for: pass))
                .font(ThemeManager.Typography.footnote)
                .foregroundColor(ThemeManager.Colors.textSecondary)
        }
        .padding(ThemeManager.Spacing.md)
        .background(ThemeManager.Colors.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.medium))
    }

    /// Only what the ticket actually says.
    private var chips: [String] {
        var result: [String] = []
        if let segment = pass.segments.first {
            if let time = segment.departTime { result.append(time) }
            if let seat = segment.seatInfo { result.append("Seat \(seat)") }
            if let travelClass = segment.travelClass { result.append(travelClass) }
        }
        if pass.passCount > 1 { result.append("\(pass.passCount) tickets") }
        return result
    }
}

/// The route, when we know enough of it to be worth drawing.
///
/// Collapses to nothing below two located places rather than showing a map
/// with one lonely pin — the itinerary is never hostage to missing geo data.
struct TripRouteStrip: View {
    let trip: Trip

    /// One stop per place, not one per pass. Three nights and a museum in
    /// Madrid is one dot on the route, not "Madrid → Madrid → Madrid".
    private var located: [(name: String, pass: SavedPass)] {
        let stops = trip.passes
            .sorted { $0.eventDateOrFallback < $1.eventDateOrFallback }
            .compactMap { pass -> (name: String, pass: SavedPass)? in
                guard pass.metadata?.latitude != nil, pass.metadata?.longitude != nil else { return nil }
                let name = pass.city ?? pass.displayVenue
                return name.isEmpty ? nil : (name: name, pass: pass)
            }

        return stops.reduce(into: [(name: String, pass: SavedPass)]()) { result, stop in
            guard TripGrouping.normalise(result.last?.name) != TripGrouping.normalise(stop.name) else { return }
            result.append(stop)
        }
    }

    /// How many passes we could place, for the honest badge.
    private var locatedPassCount: Int {
        trip.passes.filter { $0.metadata?.latitude != nil && $0.metadata?.longitude != nil }.count
    }

    var body: some View {
        if located.count >= 2 {
            VStack(alignment: .leading, spacing: ThemeManager.Spacing.sm) {
                HStack(spacing: ThemeManager.Spacing.xs) {
                    ForEach(Array(located.enumerated()), id: \.offset) { index, place in
                        if index > 0 {
                            Rectangle()
                                .fill(ThemeManager.Colors.textTertiary.opacity(0.4))
                                .frame(height: 1)
                                .frame(maxWidth: .infinity)
                        }
                        Circle()
                            .fill(PassColorUtils.getPassColor(
                                metadata: place.pass.metadata, passType: place.pass.passType
                            ))
                            .frame(width: 10, height: 10)
                    }
                }
                .padding(.horizontal, ThemeManager.Spacing.xs)

                Text(located.map(\.name).joined(separator: " → "))
                    .font(ThemeManager.Typography.caption)
                    .foregroundColor(ThemeManager.Colors.textSecondary)

                if locatedPassCount < trip.passes.count {
                    Text("\(locatedPassCount) of \(trip.passes.count) places located")
                        .font(ThemeManager.Typography.caption)
                        .foregroundColor(ThemeManager.Colors.textTertiary)
                }
            }
            .padding(ThemeManager.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ThemeManager.Colors.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.card))
        }
    }
}

/// The import flow, presented as what it is: a transaction, not a place.
///
/// The old layout was a tab wearing a sheet: a hero card burning the top third
/// to tell you the app's name and tagline, inside a sheet you opened on purpose
/// and already know the name of. A modal has a job and a way out, so it gets a
/// title, a Cancel, and the three ways in given equal weight — Files was
/// primary only because it shipped first, not because it is the likeliest.
struct ImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentView()
                .navigationTitle("Add Ticket")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    // The balance lives in `ContentView`'s own toolbar, because
                    // it is a button now and the thing it opens — the paywall —
                    // is owned by that view's model.
                }
        }
    }
}

/// Files, Photos, Paste — the same weight, because none of them is the obvious
/// one. Which you reach for depends entirely on where the ticket happens to be.
///
/// Paste does not match the other two, and that is a deliberate trade rather
/// than an oversight. `PasteButton` is system-rendered because it is the only
/// way to read the clipboard *without* iOS showing "…would like to paste from…"
/// on every single tap, and it ignores nearly everything you tell it: it will
/// not stretch to fill a frame, it ignores `buttonStyle`, it ignores the corner
/// radius, and it always draws a white label on whatever `.tint` it is given.
///
/// ⚠️ Do not hide it behind a matching card. It works — an opaque card on top
/// with `allowsHitTesting(false)` does pass the tap through, and it looks
/// exactly right — but the privilege is tied to the control being genuinely
/// visible and untransformed. Cover it or scale it and iOS quietly downgrades
/// it to the consent prompt. Measured, not assumed: tapping the covered card
/// produced "Add2Wallet would like to paste from…", while the bare control
/// pasted the file straight through. If we ever accept that prompt, drop
/// `PasteButton` altogether and read `UIPasteboard` from a card of our own —
/// same cost, none of the fragility.
///
/// So the mismatch stays until someone decides the prompt is worth paying for.
struct ImportSourcePicker: View {
    let onFiles: () -> Void
    let onPhotos: () -> Void
    let onPaste: ([NSItemProvider]) -> Void

    var body: some View {
        HStack(spacing: ThemeManager.Spacing.sm) {
            Button {
                ThemeManager.Haptics.light()
                onFiles()
            } label: {
                card("Files", icon: "folder")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("selectFileButton")

            Button {
                ThemeManager.Haptics.light()
                onPhotos()
            } label: {
                card("Photos", icon: "photo.on.rectangle")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("selectFromPhotosButton")

            // Visible, unobstructed, untransformed — and it has to stay that
            // way. See the note above: hiding it behind a matching card is what
            // costs the prompt-free paste.
            PasteButton(supportedContentTypes: SupportedFile.contentTypes) { providers in
                ThemeManager.Haptics.light()
                onPaste(providers)
            }
            .labelStyle(.titleAndIcon)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: ThemeManager.CornerRadius.card))
            .tint(ThemeManager.Colors.sourceChip)
            .frame(maxWidth: .infinity, minHeight: 84)
            .accessibilityIdentifier("pasteFileButton")
        }
    }

    private func card(_ title: String, icon: String) -> some View {
        VStack(spacing: ThemeManager.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
            Text(title)
                .font(ThemeManager.Typography.footnote)
        }
        .foregroundColor(ThemeManager.Colors.textPrimary)
        .frame(maxWidth: .infinity, minHeight: 84)
        .background(
            ThemeManager.Colors.surfaceCardGrouped,
            in: RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.card)
        )
    }
}
