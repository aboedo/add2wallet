import Foundation

/// Decides which passes belong to the same journey.
///
/// This lives on the client on purpose. The backend sees one document at a
/// time and has no idea that your Lisbon hotel and your Madrid flight are the
/// same trip — only the device holds the whole library.
///
/// The model is the one a traveller actually uses: **a trip is leaving home and
/// coming back**. Montevideo → Madrid opens a trip; Madrid → Montevideo closes
/// it; everything dated in between belongs to it, wherever it happens. Hops in
/// the middle — Madrid → London, London → Norway — are legs of that one trip,
/// not trips of their own. Proximity in time is only the fallback for a library
/// with no recognisable home.
enum TripGrouping {

    /// Fallback only: how far apart two items can sit and still read as one
    /// journey when we cannot tell where home is.
    static let maximumGapInDays = 3

    /// A place has to be seen leaving *and* returning this many times before we
    /// will call it home. One round trip is enough; a single one-way is not.
    static let minimumHomeEvidence = 2

    // MARK: - Home

    /// Where the library says this person departs from and returns to.
    ///
    /// Over a library of trips home appears twice per journey — once as the
    /// origin going out, once as the destination coming back — while anywhere
    /// else appears once or twice in total. So we count places that play both
    /// roles and take the most frequent.
    static func inferHome(from passes: [SavedPass]) -> String? {
        var departures: [String: Int] = [:]
        var arrivals: [String: Int] = [:]

        let travel = passes
            .filter { !$0.segments.isEmpty }
            .sorted { $0.eventDateOrFallback < $1.eventDateOrFallback }

        for pass in travel {
            for segment in pass.segments {
                if let origin = normalise(segment.origin) { departures[origin, default: 0] += 1 }
                if let destination = normalise(segment.destination) { arrivals[destination, default: 0] += 1 }
            }
        }

        // A hub you connect through counts exactly like home: on a
        // Montevideo → Madrid → London → Madrid → Montevideo trip, Madrid and
        // Montevideo are each departed twice and arrived at twice. What
        // separates them is the order — **you leave home before you arrive
        // there**, while anywhere else is arrived at first.
        var firstEventIsDeparture: [String: Bool] = [:]
        for pass in travel {
            for segment in pass.segments {
                if let origin = normalise(segment.origin), firstEventIsDeparture[origin] == nil {
                    firstEventIsDeparture[origin] = true
                }
                if let destination = normalise(segment.destination), firstEventIsDeparture[destination] == nil {
                    firstEventIsDeparture[destination] = false
                }
            }
        }

        var scored: [(place: String, score: Int)] = []
        for place in departures.keys where arrivals[place] != nil {
            guard firstEventIsDeparture[place] == true else { continue }
            let score = departures[place, default: 0] + arrivals[place, default: 0]
            guard score >= minimumHomeEvidence else { continue }
            scored.append((place: place, score: score))
        }
        guard !scored.isEmpty else { return nil }

        // Ties break on the name so the answer is stable across launches.
        let best = scored.max { lhs, rhs in
            lhs.score == rhs.score ? lhs.place > rhs.place : lhs.score < rhs.score
        }
        return best?.place
    }

    // MARK: - Clustering

    /// Groups passes into clusters. Every pass appears in exactly one cluster;
    /// clusters of one are simply standalone passes.
    static func cluster(_ passes: [SavedPass]) -> [[SavedPass]] {
        // A manual assignment is a statement of fact, not a guess.
        var manual: [String: [SavedPass]] = [:]
        var candidates: [SavedPass] = []
        for pass in passes {
            if let manualTripId = pass.manualTripId, !manualTripId.isEmpty {
                manual[manualTripId, default: []].append(pass)
            } else {
                candidates.append(pass)
            }
        }

        // Undated passes carry no evidence of belonging anywhere.
        let dated = candidates.filter(\.hasParseableDate).sorted {
            $0.eventDateOrFallback < $1.eventDateOrFallback
        }
        let undated = candidates.filter { !$0.hasParseableDate }

        let clusters = inferHome(from: candidates).map { home in
            clusterByRoundTrip(dated, home: home)
        } ?? clusterByAdjacency(dated)

        return clusters + manual.values.map { $0 } + undated.map { [$0] }
    }

    /// Andy's model: a journey runs from the moment you leave home until the
    /// moment you get back.
    private static func clusterByRoundTrip(_ dated: [SavedPass], home: String) -> [[SavedPass]] {
        var clusters: [[SavedPass]] = []
        var open: [SavedPass] = []
        var awayFromHome = false

        for pass in dated {
            guard awayFromHome else {
                if pass.departs(from: home) {
                    open = [pass]
                    awayFromHome = true
                } else {
                    // Still at home: a local plan, on its own.
                    clusters.append([pass])
                }
                continue
            }

            // Away: everything belongs to the open journey, including onward
            // hops between two foreign places.
            open.append(pass)
            if pass.arrives(at: home) {
                clusters.append(open)
                open = []
                awayFromHome = false
            }
        }

        // A journey with no return yet is still a journey — the flight home
        // may not be booked, or may never have been a ticket at all.
        if !open.isEmpty { clusters.append(open) }
        return clusters
    }

    /// Used when no home can be inferred — a library too small to show a
    /// pattern. Joins passes that are close in time and share a place.
    private static func clusterByAdjacency(_ dated: [SavedPass]) -> [[SavedPass]] {
        var clusters: [[SavedPass]] = []
        for pass in dated {
            if let index = clusters.indices.last, belongs(pass, in: clusters[index]) {
                clusters[index].append(pass)
            } else {
                clusters.append([pass])
            }
        }
        return clusters
    }

    // MARK: - Promotion

    /// Whether a cluster is a journey rather than a run of unrelated local plans.
    static func isJourney(_ cluster: [SavedPass]) -> Bool {
        guard cluster.count > 1 else { return false }
        guard !allLikelyDuplicates(cluster) else { return false }

        // The user said so. Not a heuristic, and not ours to second-guess.
        if cluster.contains(where: { $0.manualTripId?.isEmpty == false }) { return true }

        // The backend read one booking reference off one document.
        if sharedBookingReference(in: cluster) != nil { return true }

        // Otherwise we need evidence of going somewhere. Two concerts in your
        // own city three days apart are a busy week, not a journey.
        return cluster.contains(where: \.impliesTravel) || places(in: cluster).count > 1
    }

    /// The trip identifier: the shared booking reference when there is one,
    /// otherwise a stable id derived from its members.
    static func identifier(for cluster: [SavedPass]) -> String {
        if let manual = cluster.compactMap(\.manualTripId).first(where: { !$0.isEmpty }) {
            return manual
        }
        if let booking = sharedBookingReference(in: cluster) {
            return booking
        }
        return "auto-" + cluster.map(\.id).sorted().joined(separator: "-")
    }

    /// A booking reference only counts when every member agrees on it.
    static func sharedBookingReference(in cluster: [SavedPass]) -> String? {
        guard cluster.count > 1 else { return nil }
        let references = cluster.map { $0.groupId ?? "" }
        guard let first = references.first, !first.isEmpty,
              references.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    /// "Spain, UK and Norway" — the places visited, home excluded, in the order
    /// they were reached. Falls back to cities when no country is known.
    static func destinationSummary(for cluster: [SavedPass], home: String?) -> String? {
        var seen = Set<String>()
        var ordered: [String] = []

        for pass in cluster.sorted(by: { $0.eventDateOrFallback < $1.eventDateOrFallback }) {
            // The flight home says nothing about where you went, and its
            // country field names home rather than a destination.
            if let home, pass.arrives(at: home) { continue }

            let candidates = [pass.metadata?.stateCountry, pass.city]
                + pass.segments.map(\.destination)
            for candidate in candidates {
                guard let label = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !label.isEmpty,
                      let key = normalise(label), key != home,
                      seen.insert(key).inserted else { continue }
                ordered.append(label)
                break
            }
        }

        switch ordered.count {
        case 0: return nil
        case 1: return ordered[0]
        default:
            return ordered.dropLast().joined(separator: ", ") + " and " + ordered[ordered.count - 1]
        }
    }

    // MARK: - Internals

    private static func belongs(_ pass: SavedPass, in cluster: [SavedPass]) -> Bool {
        guard let last = cluster.last else { return false }

        if let reference = pass.groupId, !reference.isEmpty,
           cluster.contains(where: { $0.groupId == reference }) {
            return true
        }

        let gap = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: last.eventDateOrFallback),
            to: Calendar.current.startOfDay(for: pass.eventDateOrFallback)
        ).day ?? Int.max
        guard gap <= maximumGapInDays else { return false }

        let clusterPlaces = places(in: cluster)
        let passPlaces = pass.places
        if clusterPlaces.isEmpty || passPlaces.isEmpty { return true }
        return !clusterPlaces.isDisjoint(with: passPlaces)
    }

    private static func places(in cluster: [SavedPass]) -> Set<String> {
        cluster.reduce(into: Set<String>()) { $0.formUnion($1.places) }
    }

    /// Guards the `confirmation_number` fallback: re-importing the same PDF
    /// produces two rows sharing a reference, and two copies of one ticket are
    /// not a journey.
    private static func allLikelyDuplicates(_ cluster: [SavedPass]) -> Bool {
        guard let first = cluster.first else { return false }
        return cluster.dropFirst().allSatisfy { $0.isLikelyDuplicate(of: first) }
    }

    /// Lowercased, unaccented, trimmed — so "Málaga" and "malaga" are one place.
    static func normalise(_ value: String?) -> String? {
        guard let value else { return nil }
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return folded.isEmpty ? nil : folded
    }
}

extension SavedPass {
    /// Every place this pass touches, normalised for comparison.
    ///
    /// A venue is a building, not a place you travel between: counting it here
    /// made two museums in the same city look like two places and promoted an
    /// afternoon in Paris into a "trip".
    var places: Set<String> {
        var result = Set<String>()
        for value in [city, metadata?.stateCountry] {
            if let normalised = TripGrouping.normalise(value) { result.insert(normalised) }
        }
        for segment in segments {
            for value in [segment.origin, segment.destination] {
                if let normalised = TripGrouping.normalise(value) { result.insert(normalised) }
            }
        }
        return result
    }

    func departs(from home: String) -> Bool {
        segments.contains { TripGrouping.normalise($0.origin) == home }
    }

    func arrives(at home: String) -> Bool {
        segments.contains { TripGrouping.normalise($0.destination) == home }
    }

    /// Whether this pass is about going somewhere rather than attending
    /// something — the signal that separates a trip from a busy week at home.
    var impliesTravel: Bool {
        if let segment = segments.first,
           let origin = TripGrouping.normalise(segment.origin),
           let destination = TripGrouping.normalise(segment.destination),
           origin != destination {
            return true
        }
        let type = (metadata?.eventType ?? passType).lowercased()
        return ["flight", "boarding", "airline", "transit", "train", "rail",
                "bus", "ferry", "hotel", "accommodation"].contains { type.contains($0) }
    }

    /// Same ticket imported twice — same name, same day, same booking code.
    func isLikelyDuplicate(of other: SavedPass) -> Bool {
        guard displayTitle == other.displayTitle else { return false }
        guard Calendar.current.isDate(
            eventDateOrFallback, inSameDayAs: other.eventDateOrFallback
        ) else { return false }
        let mine = metadata?.confirmationNumber
        let theirs = other.metadata?.confirmationNumber
        if let mine, let theirs { return mine == theirs }
        return true
    }
}
