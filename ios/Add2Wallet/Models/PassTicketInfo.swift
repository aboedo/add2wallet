import Foundation
import PassKit

/// The detail of a single pass within a saved group.
///
/// A booking can produce several passes — a five-leg itinerary is five (or ten,
/// with two travellers) — and until now the app showed one title for the whole
/// group, so they were indistinguishable. The backend writes each leg's own
/// route, times, seat and reference onto its pass, and PassKit can read those
/// fields back without unzipping anything or going to the network.
struct PassTicketInfo: Identifiable, Equatable {
    let id: Int
    let title: String
    /// "Bergen → Voss" for a journey leg; nil for a single-event ticket.
    let route: String?
    /// Label/value pairs worth showing in a list row, already ordered.
    let details: [Detail]
    let hasBarcode: Bool

    struct Detail: Equatable, Identifiable {
        let label: String
        let value: String
        var id: String { "\(label)-\(value)" }
    }

    /// Field keys the backend writes, in the order they read best.
    private static let detailKeys: [(key: String, label: String)] = [
        ("depart", "Depart"),
        ("arrive", "Arrive"),
        ("date", "Date"),
        ("end_date", "Check-out"),
        ("time", "Time"),
        ("seat", "Seat"),
        ("gate", "Gate"),
        ("carrier", "Operator"),
        ("vehicle", "Service"),
        ("class", "Class"),
        ("confirmation", "Reference"),
        ("venue", "Venue"),
        ("price", "Price"),
    ]

    init?(passData: Data, index: Int) {
        guard let pass = try? PKPass(data: passData) else { return nil }

        let route = Self.string(from: pass, key: "route")
        let title = Self.string(from: pass, key: "title")
            ?? route
            ?? pass.localizedName

        self.id = index
        self.route = route
        self.title = title
        self.hasBarcode = pass.passURL != nil || Self.string(from: pass, key: "confirmation") != nil
        self.details = Self.detailKeys.compactMap { entry in
            guard let value = Self.string(from: pass, key: entry.key) else { return nil }
            return Detail(label: entry.label, value: value)
        }
    }

    private static func string(from pass: PKPass, key: String) -> String? {
        guard let value = pass.localizedValue(forFieldKey: key) else { return nil }
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Build the per-pass detail for a whole saved group.
    static func all(from passDatas: [Data]) -> [PassTicketInfo] {
        passDatas.enumerated().compactMap { PassTicketInfo(passData: $1, index: $0) }
    }
}
