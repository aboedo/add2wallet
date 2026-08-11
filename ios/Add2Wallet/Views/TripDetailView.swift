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

                    ForEach(Array(day.passes.enumerated()), id: \.element.id) { index, pass in
                        NavigationLink {
                            SavedPassDetailView(savedPass: pass, isPushed: true)
                        } label: {
                            TripLegCard(pass: pass)
                        }
                        .buttonStyle(.plain)

                        // The gap between landing and taking off again. Nobody
                        // prints it on a ticket, but it is the number you
                        // actually want when you are deciding whether to leave
                        // the terminal — and both halves of it are already
                        // sitting in the two legs either side.
                        let next = index + 1 < day.passes.count ? day.passes[index + 1] : nil
                        if let layover = Self.layover(from: pass, to: next) {
                            LayoverRow(text: layover)
                        }
                    }
                }
            }
        }
    }

    /// "1 hr 55 min layover in GRU", when two legs genuinely connect.
    ///
    /// Deliberately strict about what counts as a connection: the first leg has
    /// to land where the second one leaves from. Two unrelated flights on the
    /// same day are not a layover, and calling them one would be worse than
    /// staying quiet.
    ///
    /// Only within a single day. A connection that crosses midnight puts its
    /// two legs in different day groups, and the honest fix for that is to walk
    /// the whole itinerary rather than each day in isolation — worth doing when
    /// something needs it, not worth guessing at now.
    ///
    /// The subtraction ignores timezones on purpose, and is safe for exactly
    /// one reason: a layover happens at a single airport, so the arrival and
    /// the next departure are read off the same clock by construction. That is
    /// what `outbound.origin == airport` guarantees.
    static func layover(from arriving: SavedPass, to departing: SavedPass?) -> String? {
        guard let departing,
              let inbound = arriving.segments.first,
              let outbound = departing.segments.first,
              let airport = inbound.destination,
              outbound.origin == airport,
              let landed = minutes(from: inbound.arriveTime),
              let leaves = minutes(from: outbound.departTime),
              leaves > landed else { return nil }

        let gap = leaves - landed
        let hours = gap / 60
        let mins = gap % 60
        let duration = [
            hours > 0 ? "\(hours) hr" : nil,
            mins > 0 ? "\(mins) min" : nil
        ].compactMap { $0 }.joined(separator: " ")
        return "\(duration) layover in \(airport)"
    }

    /// "13:35" as minutes past midnight. The backend writes 24-hour times.
    private static func minutes(from time: String?) -> Int? {
        guard let time else { return nil }
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let hours = Int(parts[0]),
              let mins = Int(parts[1]) else { return nil }
        return hours * 60 + mins
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

/// One leg, with what the ticket actually said on it.
///
/// The row used to show a title, a route and the departure time, and drop
/// everything else on the floor — the flight number, the operator, the arrival
/// time, the reference. All of it was already extracted and stored; none of it
/// was ever displayed anywhere but the individual pass detail. This is the
/// screen where you check whether you are in the right place at the right time,
/// so it is the screen that should carry them.
struct TripLegCard: View {
    let pass: SavedPass

    private var segment: PassSegment? { pass.segments.first }

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeManager.Spacing.sm) {
            HStack(alignment: .top, spacing: ThemeManager.Spacing.md) {
                PassGlyph(pass: pass, size: Self.glyphSize)

                VStack(alignment: .leading, spacing: ThemeManager.Spacing.xs) {
                    Text(pass.routeDescription ?? pass.displayGroupTitle)
                        .font(ThemeManager.Typography.bodySemibold)
                        .foregroundColor(ThemeManager.Colors.textPrimary)
                        .lineLimit(2)

                    // The service, the way a boarding pass says it: "IB 6825 ·
                    // Iberia". Falls back to the venue for anything that is not
                    // a journey, and to the street for what you have to find.
                    if let service = segment?.serviceLine {
                        Text(service)
                            .font(ThemeManager.Typography.footnote)
                            .foregroundColor(ThemeManager.Colors.textSecondary)
                    } else if !pass.displayVenue.isEmpty {
                        Text(pass.displayVenue)
                            .font(ThemeManager.Typography.footnote)
                            .foregroundColor(ThemeManager.Colors.textSecondary)
                            .lineLimit(2)
                    }

                    if let address = streetAddress {
                        Text(address)
                            .font(ThemeManager.Typography.caption)
                            .foregroundColor(ThemeManager.Colors.textTertiary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: ThemeManager.Spacing.sm)

                // The clock wins any fight for width. Sharing a row with the
                // chips, "13:35" started breaking across two lines, and a time
                // is the one thing here that must never be ambiguous.
                times
                    .fixedSize()
                    .layoutPriority(1)
            }

            // Full card width, not the leftover beside the clock. Squeezed into
            // the text column these truncated to "Seat 1…" and "QJ7T2…", which
            // is worse than not showing them: a half-shown seat number is not a
            // seat number. Indented to line up under the title.
            if !chips.isEmpty {
                HStack(spacing: ThemeManager.Spacing.xs) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip)
                            .font(ThemeManager.Typography.caption)
                            .lineLimit(1)
                            .padding(.horizontal, ThemeManager.Spacing.sm)
                            .padding(.vertical, ThemeManager.Spacing.hairline)
                            .background(ThemeManager.Colors.textTertiary.opacity(0.15), in: Capsule())
                            .foregroundColor(ThemeManager.Colors.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, Self.glyphSize + ThemeManager.Spacing.md)
            }
        }
        .padding(ThemeManager.Spacing.md)
        .background(ThemeManager.Colors.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.medium))
    }

    private static let glyphSize: CGFloat = 36

    /// Departure over arrival, monospaced so the digits line up down the
    /// itinerary. A leg that lands on another day says so rather than showing a
    /// time that appears to precede its own departure.
    @ViewBuilder
    private var times: some View {
        if let depart = segment?.departTime {
            VStack(alignment: .trailing, spacing: ThemeManager.Spacing.hairline) {
                HStack(spacing: ThemeManager.Spacing.xs) {
                    Text(depart)
                        .font(ThemeManager.Typography.bodyMonospaced)
                        .foregroundColor(ThemeManager.Colors.textPrimary)
                    if let zone = segment?.departZoneLabel {
                        Text(zone)
                            .font(ThemeManager.Typography.caption)
                            .foregroundColor(ThemeManager.Colors.textTertiary)
                    }
                }

                if let arrive = segment?.arriveTime {
                    HStack(spacing: ThemeManager.Spacing.xs) {
                        HStack(spacing: ThemeManager.Spacing.hairline) {
                            Text("→ \(arrive)")
                            if let overnight = segment?.overnightSuffix {
                                Text(overnight)
                                    .foregroundColor(ThemeManager.Colors.textTertiary)
                            }
                        }
                        .font(ThemeManager.Typography.footnoteMonospaced)
                        .foregroundColor(ThemeManager.Colors.textSecondary)

                        if let zone = segment?.arriveZoneLabel {
                            Text(zone)
                                .font(ThemeManager.Typography.caption)
                                .foregroundColor(ThemeManager.Colors.textTertiary)
                        }
                    }
                }
            }
        } else {
            Text(TimelineFormatter.shortDate(for: pass))
                .font(ThemeManager.Typography.footnote)
                .foregroundColor(ThemeManager.Colors.textSecondary)
        }
    }

    /// The street, but only when it says something the venue line did not.
    /// A hotel whose venue is "Gran Vía 84" does not need "Gran Vía 84, 28013
    /// Madrid" underneath it.
    private var streetAddress: String? {
        guard segment == nil,
              let address = pass.metadata?.venueAddress,
              !address.isEmpty else { return nil }
        let venue = pass.displayVenue
        guard !venue.isEmpty, address.hasPrefix(venue) else { return address }
        let remainder = address.dropFirst(venue.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        return remainder.isEmpty ? nil : remainder
    }

    /// Only what the ticket actually says, ordered by how much it matters when
    /// you are standing there holding it, and capped so they stay on one line.
    private var chips: [String] {
        var result: [String] = []
        if let seat = segment?.seatInfo { result.append("Seat \(seat)") }
        if let gate = pass.metadata?.gateInfo, !gate.isEmpty { result.append(gate) }
        if let reference = segment?.confirmationNumber ?? pass.metadata?.confirmationNumber,
           !reference.isEmpty {
            result.append(reference)
        }
        if let travelClass = segment?.travelClass { result.append(travelClass) }
        if pass.passCount > 1 { result.append("\(pass.passCount) tickets") }
        return Array(result.prefix(3))
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
/// All three are ours to draw, which is a decision with a price attached.
///
/// `PasteButton` is the only way to read the clipboard *without* iOS showing
/// "…would like to paste from…" on every tap, but it is system-rendered and
/// ignores nearly everything you tell it — it will not fill a frame, it ignores
/// `buttonStyle` and the corner radius, and it always draws a white label on
/// whatever `.tint` it is given. It cannot be made to match a card.
///
/// ⚠️ Hiding it behind a matching card does not get you both. It looks right and
/// the tap does fall through, but the prompt-free privilege is tied to the
/// control being genuinely visible and untransformed; cover it or scale it and
/// iOS silently downgrades it to the consent prompt anyway. Measured, not
/// assumed: the covered card produced the prompt, the bare control did not.
///
/// So the choice was consistency or a silent tap, and consistency won on the
/// grounds that the prompt is self-explanatory here — a person who just tapped
/// "Paste" is not surprised to be asked about pasting. Given we are paying the
/// prompt regardless, we read `UIPasteboard` ourselves rather than keep a
/// system control hidden under a card: same cost to the user, none of the
/// fragility, and the row finally matches.
struct ImportSourcePicker: View {
    let onFiles: () -> Void
    let onPhotos: () -> Void
    let onScan: () -> Void
    let onPaste: ([NSItemProvider]) -> Void

    @State private var clipboardHasTicket = false

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

            // Dimmed rather than hidden where there is no scanner — which in
            // practice means the simulator, so the row we develop against is
            // the row people get.
            Button {
                ThemeManager.Haptics.light()
                onScan()
            } label: {
                card("Scan", icon: "doc.viewfinder", dimmed: !DocumentScanner.isAvailable)
            }
            .buttonStyle(.plain)
            .disabled(!DocumentScanner.isAvailable)
            .accessibilityIdentifier("scanDocumentButton")

            Button {
                ThemeManager.Haptics.light()
                // Reading `itemProviders` is what triggers the consent prompt.
                // Everything downstream already copes with an empty or
                // unsupported clipboard, so there is nothing to pre-validate.
                onPaste(UIPasteboard.general.itemProviders)
            } label: {
                card("Paste", icon: "doc.on.clipboard", dimmed: !clipboardHasTicket)
            }
            .buttonStyle(.plain)
            .disabled(!clipboardHasTicket)
            .accessibilityIdentifier("pasteFileButton")
        }
        .onAppear { refreshClipboard() }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
        ) { _ in refreshClipboard() }
    }

    /// Asking the pasteboard *which types it holds* is free and prompts nobody —
    /// it is how `PasteButton` decided whether to enable itself, and it is how
    /// we decide now. Only asking for the contents costs the prompt.
    private func refreshClipboard() {
        clipboardHasTicket = UIPasteboard.general.contains(
            pasteboardTypes: SupportedFile.contentTypes.map(\.identifier)
        )
    }

    /// `dimmed` matches what the old system control did for free: go quiet when
    /// there is nothing on the clipboard worth pasting.
    private func card(_ title: String, icon: String, dimmed: Bool = false) -> some View {
        VStack(spacing: ThemeManager.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: ThemeManager.IconSize.medium, weight: .regular))
            Text(title)
                .font(ThemeManager.Typography.footnote)
        }
        .foregroundColor(dimmed ? ThemeManager.Colors.textTertiary : ThemeManager.Colors.textPrimary)
        .frame(maxWidth: .infinity, minHeight: 84)
        .background(
            ThemeManager.Colors.surfaceCardGrouped,
            in: RoundedRectangle(cornerRadius: ThemeManager.CornerRadius.card)
        )
    }
}

/// The wait between two connecting legs. Quiet on purpose — it is not a thing
/// you own, it is the space between two things you own.
struct LayoverRow: View {
    let text: String

    var body: some View {
        HStack(spacing: ThemeManager.Spacing.sm) {
            Image(systemName: "clock")
                .font(.system(size: ThemeManager.IconSize.inline))
                .frame(width: 36)
            Text(text)
                .italic()
            Spacer(minLength: 0)
        }
        .font(ThemeManager.Typography.footnote)
        .foregroundColor(ThemeManager.Colors.textTertiary)
        .padding(.leading, ThemeManager.Spacing.md)
    }
}
