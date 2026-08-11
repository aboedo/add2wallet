import XCTest
@testable import Add2Wallet

/// Turning a stored zone back into something readable on the itinerary.
///
/// The zone is stored as an IANA name precisely so the offset can be worked out
/// for the day the leg happens. These check that it actually is.
final class SegmentTimezoneTests: XCTestCase {

    func testOffsetIsResolvedForTheDayTheLegHappens() {
        // Madrid is CEST in August and CET in January. Same zone, same code,
        // two different answers — which is the whole reason "+02:00" is not
        // what gets stored.
        XCTAssertEqual(TripLegCard.zoneLabel("Europe/Madrid", on: "2026-08-11"), "GMT+2")
        XCTAssertEqual(TripLegCard.zoneLabel("Europe/Madrid", on: "2026-01-11"), "GMT+1")
    }

    func testWesternOffsetsUseAMinusSign() {
        XCTAssertEqual(TripLegCard.zoneLabel("America/Montevideo", on: "2026-10-10"), "GMT−3")
    }

    func testZeroOffsetIsJustGMT() {
        XCTAssertEqual(TripLegCard.zoneLabel("Europe/London", on: "2026-01-11"), "GMT")
    }

    /// India is +5:30. An integer-only formatter would render that as "GMT+5"
    /// and be half an hour wrong.
    func testHalfHourOffsetKeepsItsHalfHour() {
        XCTAssertEqual(TripLegCard.zoneLabel("Asia/Kolkata", on: "2026-08-11"), "GMT+5.5")
    }

    func testUnknownOrMissingZoneProducesNoLabel() {
        XCTAssertNil(TripLegCard.zoneLabel("Mars/Olympus", on: "2026-08-11"))
        XCTAssertNil(TripLegCard.zoneLabel(nil, on: "2026-08-11"))
    }

    /// Where the offset problem is actually solved, and where it is not.
    ///
    /// `TimeZone` refuses "+02:00" but happily accepts "GMT-3" and pins it to a
    /// fixed offset with no DST rules — so an offset that reached the app would
    /// render, and would be wrong for half of every year. The app cannot tell
    /// the difference after the fact, which is why the rejection lives in the
    /// backend validator instead, on the way in. These assertions record that
    /// boundary rather than pretend the client is defending it.
    func testTheClientCannotBeTheOneRejectingOffsets() {
        XCTAssertNil(TripLegCard.zoneLabel("+02:00", on: "2026-08-11"))
        XCTAssertEqual(TripLegCard.zoneLabel("GMT-3", on: "2026-08-11"), "GMT−3")
    }
}
