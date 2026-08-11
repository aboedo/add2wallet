import XCTest
@testable import Add2Wallet

/// The gap between landing and taking off again.
///
/// Nobody prints a layover on a ticket, so it is derived — which makes it the
/// one number on the itinerary that can be silently, confidently wrong. Two
/// flights on the same afternoon are not a connection just because they are
/// adjacent in a list.
final class LayoverTests: XCTestCase {

    private func flight(
        from origin: String?,
        to destination: String?,
        departs: String? = nil,
        arrives: String? = nil
    ) -> SavedPass {
        let segment = PassSegment(
            page: nil,
            label: nil,
            origin: origin,
            destination: destination,
            departDate: nil,
            departTime: departs,
            arriveDate: nil,
            arriveTime: arrives,
            departTimezone: nil,
            arriveTimezone: nil,
            carrier: nil,
            vehicleInfo: nil,
            seatInfo: nil,
            travelClass: nil,
            confirmationNumber: nil,
            traveler: nil,
            notes: nil
        )
        return SavedPass(
            passType: "flight",
            title: "\(origin ?? "?") → \(destination ?? "?")",
            metadata: EnhancedPassMetadata(segment: segment)
        )
    }

    func testConnectingFlightsReportTheGapBetweenThem() {
        let inbound = flight(from: "MVD", to: "GRU", departs: "08:15", arrives: "11:40")
        let outbound = flight(from: "GRU", to: "MAD", departs: "13:35", arrives: "05:50")

        XCTAssertEqual(
            TripDetailView.layover(from: inbound, to: outbound),
            "1 hr 55 min layover in GRU"
        )
    }

    func testWholeHourLayoverDoesNotSayZeroMinutes() {
        let inbound = flight(from: "MVD", to: "GRU", departs: "08:15", arrives: "11:00")
        let outbound = flight(from: "GRU", to: "MAD", departs: "13:00")

        XCTAssertEqual(
            TripDetailView.layover(from: inbound, to: outbound),
            "2 hr layover in GRU"
        )
    }

    func testShortLayoverIsReportedInMinutesAlone() {
        let inbound = flight(from: "MVD", to: "GRU", arrives: "11:00")
        let outbound = flight(from: "GRU", to: "MAD", departs: "11:45")

        XCTAssertEqual(
            TripDetailView.layover(from: inbound, to: outbound),
            "45 min layover in GRU"
        )
    }

    /// The whole point of the destination/origin check. A morning flight home
    /// and an unrelated evening flight out of a different airport share a day,
    /// not a connection.
    func testUnrelatedFlightsOnTheSameDayAreNotALayover() {
        let inbound = flight(from: "MVD", to: "GRU", arrives: "11:40")
        let outbound = flight(from: "MAD", to: "LHR", departs: "13:35")

        XCTAssertNil(TripDetailView.layover(from: inbound, to: outbound))
    }

    func testALegWithNothingAfterItHasNoLayover() {
        let inbound = flight(from: "MVD", to: "GRU", arrives: "11:40")

        XCTAssertNil(TripDetailView.layover(from: inbound, to: nil))
    }

    /// Missing times are the common case for anything that is not a flight, and
    /// a layover of "unknown" is worse than none.
    func testMissingTimesProduceNoLayover() {
        let inbound = flight(from: "MVD", to: "GRU")
        let outbound = flight(from: "GRU", to: "MAD", departs: "13:35")

        XCTAssertNil(TripDetailView.layover(from: inbound, to: outbound))
    }

    /// Guards the arithmetic rather than the intent: a second leg that departs
    /// before the first one lands means the times are not on the same clock, so
    /// the subtraction is meaningless and gets refused instead of shown.
    func testDepartureBeforeArrivalIsRefusedRatherThanShownNegative() {
        let inbound = flight(from: "MVD", to: "GRU", arrives: "23:40")
        let outbound = flight(from: "GRU", to: "MAD", departs: "06:10")

        XCTAssertNil(TripDetailView.layover(from: inbound, to: outbound))
    }
}
