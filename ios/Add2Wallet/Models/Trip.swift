import Foundation

/// A journey: the passes that share one booking, or that the user grouped by hand.
///
/// Trips are derived at read time rather than stored. The booking reference
/// already arrives from the backend, so persisting a second copy of the
/// relationship would only create a way for the two to disagree.
struct Trip: Identifiable, Hashable {
    let id: String
    let name: String
    let passes: [SavedPass]

    static func == (lhs: Trip, rhs: Trip) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Earliest event in the trip — what the timeline sorts on.
    var startDate: Date {
        passes.map(\.eventDateOrFallback).min() ?? Date()
    }

    var endDate: Date {
        passes.map(\.eventDateOrFallback).max() ?? startDate
    }

    /// A trip is past only once every one of its passes is.
    var isPast: Bool {
        passes.allSatisfy(\.isExpired)
    }

    var passCount: Int {
        passes.reduce(0) { $0 + max(1, $1.passCount) }
    }

    /// Cities in itinerary order, de-duplicated: Lisbon → Málaga → Madrid.
    var itineraryCities: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for pass in passes.sorted(by: { $0.eventDateOrFallback < $1.eventDateOrFallback }) {
            for city in [pass.segments.first?.origin, pass.segments.first?.destination, pass.city] {
                guard let city, !city.isEmpty, seen.insert(city).inserted else { continue }
                ordered.append(city)
            }
        }
        return ordered
    }
}

/// Anything that can occupy a row on the timeline.
enum TimelineItem: Identifiable, Hashable {
    case trip(Trip)
    case pass(SavedPass)

    var id: String {
        switch self {
        case .trip(let trip): return "trip-\(trip.id)"
        case .pass(let pass): return "pass-\(pass.id)"
        }
    }

    /// The date this item sorts on.
    var date: Date {
        switch self {
        case .trip(let trip): return trip.startDate
        case .pass(let pass): return pass.eventDateOrFallback
        }
    }

    var isPast: Bool {
        switch self {
        case .trip(let trip): return trip.isPast
        case .pass(let pass): return pass.isExpired
        }
    }

    /// True when no date could be parsed off the ticket, so the UI can say so
    /// instead of showing a misleading import date.
    var hasKnownDate: Bool {
        switch self {
        case .trip(let trip): return trip.passes.contains { $0.hasParseableDate }
        case .pass(let pass): return pass.hasParseableDate
        }
    }
}

/// The chronological spine: what is next, what is coming, what is done.
struct Timeline {
    let next: TimelineItem?
    let upcoming: [TimelineItem]
    let past: [TimelineItem]

    var isEmpty: Bool { next == nil && upcoming.isEmpty && past.isEmpty }

    var pastPassCount: Int {
        past.reduce(0) { total, item in
            switch item {
            case .trip(let trip): return total + trip.passCount
            case .pass(let pass): return total + max(1, pass.passCount)
            }
        }
    }

    /// Groups passes into trips, then splits the result across the spine.
    ///
    /// Grouping is a client-side judgement (see `TripGrouping`): only the
    /// device holds the whole library, so only the device can tell that a
    /// flight and a hotel are one journey.
    static func build(from passes: [SavedPass]) -> Timeline {
        var items: [TimelineItem] = []

        for cluster in TripGrouping.cluster(passes) {
            if TripGrouping.isJourney(cluster) {
                items.append(.trip(Trip(
                    id: TripGrouping.identifier(for: cluster),
                    name: tripName(for: cluster),
                    passes: cluster
                )))
            } else {
                items.append(contentsOf: cluster.map(TimelineItem.pass))
            }
        }

        let past = items.filter(\.isPast).sorted { $0.date > $1.date }
        let future = items
            .filter { !$0.isPast }
            .sorted { lhs, rhs in
                // Undated items sink below dated ones rather than pretending
                // their import date is an event date.
                if lhs.hasKnownDate != rhs.hasKnownDate { return lhs.hasKnownDate }
                return lhs.date < rhs.date
            }

        return Timeline(next: future.first, upcoming: Array(future.dropFirst()), past: past)
    }

    /// The backend's name for the booking, else the city and month it covers.
    private static func tripName(for passes: [SavedPass]) -> String {
        if let name = passes.compactMap(\.groupName).first(where: { !$0.isEmpty }) {
            return name
        }
        let city = passes.compactMap { $0.city?.isEmpty == false ? $0.city : nil }.first
        let date = passes.map(\.eventDateOrFallback).min() ?? Date()
        let month = date.formatted(.dateTime.month(.wide).year())
        return city.map { "\($0), \(month)" } ?? month
    }
}

extension SavedPass {
    /// Whether a real event date could be read off the ticket, as opposed to
    /// falling back to when the pass was imported.
    var hasParseableDate: Bool {
        guard let eventDate, !eventDate.isEmpty else { return false }
        return eventDateOrFallback != createdAt
    }
}
