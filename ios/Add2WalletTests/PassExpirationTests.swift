import XCTest
@testable import Add2Wallet

/// When a pass stops being worth keeping in front of you.
///
/// The rule is that a booking runs until it *ends*. Expiring off the start date
/// sent multi-day reservations to the past section on their first morning.
final class PassExpirationTests: XCTestCase {

    // MARK: - Helpers

    private func day(offsetFromToday days: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: days, to: Date())!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func pass(
        date: String? = nil,
        endDate: String? = nil,
        segments: [PassSegment]? = nil
    ) -> SavedPass {
        SavedPass(
            passType: "Reservation",
            title: "Booking",
            eventDate: date,
            metadata: EnhancedPassMetadata(date: date, endDate: endDate, segments: segments)
        )
    }

    private func segment(depart: String?, arrive: String? = nil) -> PassSegment {
        PassSegment(
            page: nil, label: nil, origin: nil, destination: nil,
            departDate: depart, departTime: nil,
            arriveDate: arrive, arriveTime: nil,
            departTimezone: nil, arriveTimezone: nil,
            carrier: nil, vehicleInfo: nil, seatInfo: nil, travelClass: nil,
            confirmationNumber: nil, traveler: nil, notes: nil
        )
    }

    // MARK: - The end date wins

    func testStayInProgressIsNotExpired() {
        // Checked in three days ago, checking out in three days.
        let stay = pass(date: day(offsetFromToday: -3), endDate: day(offsetFromToday: 3))
        XCTAssertFalse(stay.isExpired, "a stay must survive its own check-in")
    }

    func testStayExpiresOnlyAfterCheckout() {
        let finished = pass(date: day(offsetFromToday: -10), endDate: day(offsetFromToday: -1))
        XCTAssertTrue(finished.isExpired)
    }

    func testCheckoutTodayIsStillValid() {
        let leavingToday = pass(date: day(offsetFromToday: -4), endDate: day(offsetFromToday: 0))
        XCTAssertFalse(leavingToday.isExpired, "you still hold the room on check-out day")
    }

    func testWithoutAnEndDateTheStartDateStillDecides() {
        XCTAssertTrue(pass(date: day(offsetFromToday: -1)).isExpired)
        XCTAssertFalse(pass(date: day(offsetFromToday: 1)).isExpired)
    }

    func testPassWithNoReadableDateNeverExpires() {
        XCTAssertFalse(pass().isExpired)
        XCTAssertFalse(pass(date: "sometime next spring").isExpired)
    }

    // MARK: - Several passes: the latest one decides

    func testItineraryLivesUntilItsLastLeg() {
        let trip = pass(date: day(offsetFromToday: -5), segments: [
            segment(depart: day(offsetFromToday: -5), arrive: day(offsetFromToday: -5)),
            segment(depart: day(offsetFromToday: 4), arrive: day(offsetFromToday: 4))
        ])
        XCTAssertFalse(trip.isExpired, "the return leg has not happened yet")
    }

    func testItineraryExpiresOnceEveryLegHasPassed() {
        let trip = pass(date: day(offsetFromToday: -9), segments: [
            segment(depart: day(offsetFromToday: -9), arrive: day(offsetFromToday: -9)),
            segment(depart: day(offsetFromToday: -2), arrive: day(offsetFromToday: -2))
        ])
        XCTAssertTrue(trip.isExpired)
    }

    /// The case a plain `max(endDates)` gets wrong: only the first leg records an
    /// arrival, and that arrival is earlier than the last leg's departure.
    func testPartialArrivalDatesDoNotExpireTheRestOfTheTrip() {
        let trip = pass(date: day(offsetFromToday: -6), segments: [
            segment(depart: day(offsetFromToday: -6), arrive: day(offsetFromToday: -6)),
            segment(depart: day(offsetFromToday: 5))
        ])
        XCTAssertFalse(trip.isExpired, "a leg with no arrival must fall back to its departure")
    }

    func testLatestDateWinsRegardlessOfSegmentOrder() {
        let ascending = pass(date: day(offsetFromToday: -2), segments: [
            segment(depart: day(offsetFromToday: -2)),
            segment(depart: day(offsetFromToday: 6))
        ])
        let descending = pass(date: day(offsetFromToday: -2), segments: [
            segment(depart: day(offsetFromToday: 6)),
            segment(depart: day(offsetFromToday: -2))
        ])
        XCTAssertEqual(ascending.lastRelevantDate, descending.lastRelevantDate)
        XCTAssertFalse(ascending.isExpired)
        XCTAssertFalse(descending.isExpired)
    }

    func testRecordEndDateAndSegmentsAreBothConsidered() {
        let booking = pass(
            date: day(offsetFromToday: -8),
            endDate: day(offsetFromToday: -7),
            segments: [segment(depart: day(offsetFromToday: 2))]
        )
        XCTAssertFalse(booking.isExpired, "the later of the two must win")
    }

    // MARK: - Trips

    func testTripRunsThroughItsClosingStay() {
        let flight = SavedPass(
            passType: "Flight", title: "Outbound",
            eventDate: day(offsetFromToday: -4),
            metadata: EnhancedPassMetadata(date: day(offsetFromToday: -4), groupId: "ABC123")
        )
        let hotel = SavedPass(
            passType: "Hotel", title: "Stay",
            eventDate: day(offsetFromToday: -3),
            metadata: EnhancedPassMetadata(
                date: day(offsetFromToday: -3),
                endDate: day(offsetFromToday: 3),
                groupId: "ABC123"
            )
        )

        let trip = Trip(id: "ABC123", name: "Trip", passes: [flight, hotel])
        XCTAssertFalse(trip.isPast, "the stay is still running")
        XCTAssertEqual(
            Calendar.current.startOfDay(for: trip.endDate),
            Calendar.current.startOfDay(for: hotel.lastRelevantDate!),
            "the trip ends at the check-out, not at the last check-in"
        )
    }

    func testTripIsPastOnlyWhenEveryPassIs() {
        let past = SavedPass(
            passType: "Flight", title: "Outbound",
            eventDate: day(offsetFromToday: -4),
            metadata: EnhancedPassMetadata(date: day(offsetFromToday: -4), groupId: "ABC123")
        )
        let done = SavedPass(
            passType: "Flight", title: "Return",
            eventDate: day(offsetFromToday: -1),
            metadata: EnhancedPassMetadata(date: day(offsetFromToday: -1), groupId: "ABC123")
        )
        XCTAssertTrue(Trip(id: "ABC123", name: "Trip", passes: [past, done]).isPast)
    }

    // MARK: - The user's own call

    func testUndatedPassCanBeMarkedExpiredByHand() {
        let ticket = pass()
        XCTAssertFalse(ticket.isExpired, "nothing to go on, so it stays put")

        ticket.manuallyExpired = true
        XCTAssertTrue(ticket.isExpired, "the person holding it knows it is spent")
    }

    func testAnExpiredPassCanBeBroughtBack() {
        let ticket = pass(date: day(offsetFromToday: -1))
        XCTAssertTrue(ticket.isExpired)

        ticket.manuallyExpired = false
        XCTAssertFalse(ticket.isExpired)
    }

    func testClearingTheOverrideReturnsToTheDates() {
        let ticket = pass(date: day(offsetFromToday: -1))
        ticket.manuallyExpired = false
        XCTAssertFalse(ticket.isExpired)

        ticket.manuallyExpired = nil
        XCTAssertTrue(ticket.isExpired, "back to what the ticket says")
    }

    func testOverrideDoesNotDisturbTheUnderlyingDateReading() {
        let stay = pass(date: day(offsetFromToday: -3), endDate: day(offsetFromToday: 3))
        stay.manuallyExpired = true

        XCTAssertTrue(stay.isExpired)
        XCTAssertFalse(stay.isExpiredByDate, "the dates still say what they said")
    }

    func testAgreeingWithTheDatesIsNotFlaggedAsAnOverride() {
        let ticket = pass(date: day(offsetFromToday: -1))
        ticket.manuallyExpired = true

        XCTAssertTrue(ticket.isExpired)
        XCTAssertFalse(
            ticket.isManuallyOverridden,
            "it agrees with the dates, so there is nothing to explain"
        )
    }

    func testContradictingTheDatesIsFlaggedAsAnOverride() {
        let ticket = pass(date: day(offsetFromToday: -1))
        ticket.manuallyExpired = false
        XCTAssertTrue(ticket.isManuallyOverridden)

        let undated = pass()
        undated.manuallyExpired = true
        XCTAssertTrue(undated.isManuallyOverridden)
    }

    func testNoOverrideIsNeverFlagged() {
        XCTAssertFalse(pass().isManuallyOverridden)
        XCTAssertFalse(pass(date: day(offsetFromToday: -1)).isManuallyOverridden)
    }

    func testAManuallyExpiredPassLeavesTheUpcomingTimeline() {
        let undated = pass()
        undated.manuallyExpired = true

        let timeline = Timeline.build(from: [undated])
        XCTAssertNil(timeline.next)
        XCTAssertEqual(timeline.past.count, 1)
    }

    // MARK: - Decoding

    func testEndDateDecodesFromTheBackendPayload() throws {
        let json = Data(#"{"date":"2026-09-01","end_date":"2026-09-10","end_time":"11:00"}"#.utf8)
        let metadata = try JSONDecoder().decode(EnhancedPassMetadata.self, from: json)

        XCTAssertEqual(metadata.endDate, "2026-09-10")
        XCTAssertEqual(metadata.endTime, "11:00")
    }
}
