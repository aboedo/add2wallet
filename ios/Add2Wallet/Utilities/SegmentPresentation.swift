import Foundation

/// How a leg reads once it has to be shown to somebody.
///
/// This lived inside the itinerary row until the same facts were needed on the
/// pass detail. Two copies of "when do we show a timezone" is how the two
/// screens start disagreeing about the same flight, so it moved here instead.
extension PassSegment {

    /// The backend sends segment dates as ISO days and nothing else, so this
    /// only needs to read that one shape. Built once — `DateFormatter` is
    /// expensive and this runs per row.
    static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// "IB 6825 · Iberia", or whichever half the ticket gave us.
    var serviceLine: String? {
        let parts = [vehicleInfo, carrier].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "+1" when the arrival lands on a later day than the departure, so a
    /// red-eye does not read as arriving before it left.
    var overnightSuffix: String? {
        guard let departDate,
              let arriveDate,
              let depart = Self.isoDay.date(from: departDate),
              let arrive = Self.isoDay.date(from: arriveDate) else { return nil }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: depart),
            to: Calendar.current.startOfDay(for: arrive)
        ).day ?? 0
        return days > 0 ? "+\(days)" : nil
    }

    /// Whether the two ends of this leg are on clocks that disagree.
    ///
    /// Compares the *offsets*, not the zone names. Montevideo and São Paulo are
    /// two different zones that both read GMT−3 in October, and labelling that
    /// leg "GMT−3 → GMT−3" is noise dressed up as information. What matters is
    /// whether the two clocks disagree on the day of the flight.
    var crossesTimezones: Bool {
        guard let depart = TimeZone(identifier: departTimezone ?? ""),
              let arrive = TimeZone(identifier: arriveTimezone ?? "") else { return false }
        let departOn = departDate.flatMap { Self.isoDay.date(from: $0) } ?? Date()
        let arriveOn = arriveDate.flatMap { Self.isoDay.date(from: $0) } ?? departOn
        return depart.secondsFromGMT(for: departOn) != arrive.secondsFromGMT(for: arriveOn)
    }

    var departZoneLabel: String? {
        crossesTimezones ? Self.zoneLabel(departTimezone, on: departDate) : nil
    }

    var arriveZoneLabel: String? {
        crossesTimezones ? Self.zoneLabel(arriveTimezone, on: arriveDate) : nil
    }

    /// "GMT-3" for the day the leg actually happens.
    ///
    /// Resolved against the date rather than today, because that is the whole
    /// reason the zone is stored as `Europe/Madrid` instead of `+02:00`: the
    /// offset moves twice a year and a pass bought in winter may fly in summer.
    static func zoneLabel(_ identifier: String?, on date: String?) -> String? {
        guard let identifier, let zone = TimeZone(identifier: identifier) else { return nil }
        let when = date.flatMap { isoDay.date(from: $0) } ?? Date()
        let hours = Double(zone.secondsFromGMT(for: when)) / 3600
        if hours == 0 { return "GMT" }
        let sign = hours > 0 ? "+" : "−"
        let magnitude = abs(hours)
        let rendered = magnitude == magnitude.rounded()
            ? String(Int(magnitude))
            : String(format: "%.1f", magnitude)
        return "GMT\(sign)\(rendered)"
    }

    /// "Sat 10 Oct" — the day this end of the leg happens, when we know it.
    static func dayLabel(_ date: String?) -> String? {
        guard let date, let parsed = isoDay.date(from: date) else { return nil }
        return parsed.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}
