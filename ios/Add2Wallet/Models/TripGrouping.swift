import Foundation

/// Decides which passes belong to the same journey.
///
/// This lives on the client on purpose. The backend sees one document at a
/// time and has no idea that your Lisbon hotel and your Madrid flight are the
/// same trip — only the device holds the whole library. The booking reference
/// it does return groups the legs of a single booking, which is a much smaller
/// claim than "this is a trip".
enum TripGrouping {

    /// How far apart two items can sit and still read as one journey.
    /// Three days covers a weekend either side of an event without swallowing
    /// the next month.
    static let maximumGapInDays = 3

    /// Groups passes into clusters. Every pass appears in exactly one cluster;
    /// clusters of one are simply standalone passes.
    static func cluster(_ passes: [SavedPass]) -> [[SavedPass]] {
        // A manual assignment is a statement of fact, not a guess — honour it
        // before any heuristic runs, and never re-cluster those passes.
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

        var clusters: [[SavedPass]] = []
        for pass in dated {
            if let index = clusters.indices.last, belongs(pass, in: clusters[index]) {
                clusters[index].append(pass)
            } else {
                clusters.append([pass])
            }
        }

        return clusters + manual.values.map { $0 } + undated.map { [$0] }
    }

    /// Whether a cluster is a journey rather than a run of unrelated local plans.
    static func isJourney(_ cluster: [SavedPass]) -> Bool {
        guard cluster.count > 1 else { return false }
        guard !allLikelyDuplicates(cluster) else { return false }

        // The user said so. Not a heuristic, and not ours to second-guess.
        if cluster.contains(where: { $0.manualTripId?.isEmpty == false }) { return true }

        // The backend said these are one booking. Also not a heuristic — it
        // read the reference off the document.
        if sharedBookingReference(in: cluster) != nil { return true }

        // Otherwise we are guessing, so we need evidence of *going somewhere*.
        // Two concerts in your own city three days apart are not a trip.
        return cluster.contains(where: \.impliesTravel) || places(in: cluster).count > 1
    }

    /// The trip identifier for a cluster: the shared booking reference when
    /// there is one, otherwise a stable id derived from its members.
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

    // MARK: - Internals

    private static func belongs(_ pass: SavedPass, in cluster: [SavedPass]) -> Bool {
        guard let last = cluster.last else { return false }

        // Same booking always travels together, whatever the calendar says.
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

        // Close in time is not enough — the places have to connect. When
        // neither side names a place we let time alone decide rather than
        // splitting on missing data.
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
}

extension SavedPass {
    /// Every place this pass touches, normalised for comparison.
    var places: Set<String> {
        var result = Set<String>()
        for value in [city, venue, metadata?.stateCountry] {
            if let normalised = TripGrouping.normalise(value) { result.insert(normalised) }
        }
        for segment in segments {
            for value in [segment.origin, segment.destination] {
                if let normalised = TripGrouping.normalise(value) { result.insert(normalised) }
            }
        }
        return result
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

extension TripGrouping {
    /// Lowercased, unaccented, trimmed — so "Málaga" and "malaga" are one place.
    static func normalise(_ value: String?) -> String? {
        guard let value else { return nil }
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return folded.isEmpty ? nil : folded
    }
}
