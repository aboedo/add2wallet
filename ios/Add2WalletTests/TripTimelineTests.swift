import XCTest
@testable import Add2Wallet

/// The chronological spine and the grouping rules behind it.
final class TripTimelineTests: XCTestCase {

    // MARK: - Helpers

    private func metadata(
        groupId: String? = nil,
        groupName: String? = nil,
        city: String? = nil,
        segment: PassSegment? = nil
    ) -> EnhancedPassMetadata {
        EnhancedPassMetadata(city: city, groupId: groupId, groupName: groupName, segment: segment)
    }

    private func pass(
        _ title: String,
        date: String? = nil,
        city: String? = nil,
        groupId: String? = nil,
        groupName: String? = nil,
        manualTripId: String? = nil,
        segment: PassSegment? = nil
    ) -> SavedPass {
        SavedPass(
            passType: "Event",
            title: title,
            eventDate: date,
            city: city,
            metadata: metadata(groupId: groupId, groupName: groupName, city: city, segment: segment),
            manualTripId: manualTripId
        )
    }

    private let future = "Dec 15, 2027"
    private let nearFuture = "Sep 8, 2026"
    private let past = "Dec 15, 2024"

    // MARK: - Grouping

    func testPassesSharingABookingReferenceBecomeATrip() {
        let timeline = Timeline.build(from: [
            pass("AVLO Málaga → Madrid", date: nearFuture, groupId: "QX7RM2", groupName: "Summer in Iberia"),
            pass("Air Europa MAD → MDE", date: future, groupId: "QX7RM2", groupName: "Summer in Iberia")
        ])

        guard case .trip(let trip)? = timeline.next else {
            return XCTFail("expected the two passes to collapse into one trip")
        }
        XCTAssertEqual(trip.name, "Summer in Iberia")
        XCTAssertEqual(trip.passes.count, 2)
        XCTAssertTrue(timeline.upcoming.isEmpty)
    }

    func testASinglePassWithABookingReferenceStaysStandalone() {
        // A one-item trip would add a tap without adding information.
        let timeline = Timeline.build(from: [pass("Musée d'Orsay", date: nearFuture, groupId: "SOLO1")])

        guard case .pass? = timeline.next else {
            return XCTFail("a lone pass must not be wrapped in a trip")
        }
    }

    func testPassesWithoutAGroupStayStandalone() {
        let timeline = Timeline.build(from: [
            pass("Musée d'Orsay", date: nearFuture),
            pass("Hamilton", date: future)
        ])

        XCTAssertEqual(timeline.upcoming.count, 1)
        if case .trip = timeline.next { XCTFail("unrelated passes must not be grouped") }
    }

    func testManualAssignmentOverridesTheBookingReference() {
        let moved = pass("Hotel Lisboa", date: nearFuture, groupId: "FROM-BACKEND", manualTripId: "MY-TRIP")
        XCTAssertEqual(moved.tripId, "MY-TRIP")

        let timeline = Timeline.build(from: [
            moved,
            pass("Benfica", date: nearFuture, manualTripId: "MY-TRIP")
        ])
        guard case .trip(let trip)? = timeline.next else {
            return XCTFail("manually grouped passes must form a trip")
        }
        XCTAssertEqual(trip.id, "MY-TRIP")
    }

    // MARK: - Trip naming

    func testTripIsNamedAfterWhereItWentNotWhenItHappened() {
        let timeline = Timeline.build(from: [
            pass("Leg 1", date: nearFuture, city: "Lisbon", groupId: "NONAME"),
            pass("Leg 2", date: nearFuture, city: "Lisbon", groupId: "NONAME")
        ])
        guard case .trip(let trip)? = timeline.next else { return XCTFail("expected a trip") }
        XCTAssertEqual(trip.name, "Lisbon")
    }

    func testTripFallsBackToTheMonthWhenNowhereIsNamed() {
        let timeline = Timeline.build(from: [
            pass("Leg 1", date: nearFuture, groupId: "NONAME"),
            pass("Leg 2", date: nearFuture, groupId: "NONAME")
        ])
        guard case .trip(let trip)? = timeline.next else { return XCTFail("expected a trip") }
        XCTAssertFalse(trip.name.isEmpty)
    }

    // MARK: - The spine

    func testNextIsTheNearestUpcomingItem() {
        let timeline = Timeline.build(from: [
            pass("Later", date: future),
            pass("Sooner", date: nearFuture)
        ])

        guard case .pass(let next)? = timeline.next else { return XCTFail("expected a next item") }
        XCTAssertEqual(next.title, "Sooner")
    }

    func testPastItemsAreSeparatedAndMostRecentFirst() {
        let timeline = Timeline.build(from: [
            pass("Old", date: "Jan 5, 2023"),
            pass("Recent", date: past),
            pass("Upcoming", date: future)
        ])

        XCTAssertEqual(timeline.past.count, 2)
        guard case .pass(let first) = timeline.past[0] else { return XCTFail("expected a pass") }
        XCTAssertEqual(first.title, "Recent", "the archive reads newest first")
    }

    func testUndatedItemsSinkBelowDatedOnesButAreNeverHidden() {
        let timeline = Timeline.build(from: [
            pass("No date on ticket"),
            pass("Dated", date: future)
        ])

        guard case .pass(let next)? = timeline.next else { return XCTFail("expected a next item") }
        XCTAssertEqual(next.title, "Dated")
        XCTAssertEqual(timeline.upcoming.count, 1, "the undated pass must still be listed")
        XCTAssertFalse(timeline.upcoming[0].hasKnownDate)
    }

    func testATripIsPastOnlyWhenEveryPassIs() {
        let timeline = Timeline.build(from: [
            pass("Outbound", date: past, groupId: "T1", groupName: "Trip"),
            pass("Return", date: future, groupId: "T1", groupName: "Trip")
        ])

        XCTAssertTrue(timeline.past.isEmpty, "a trip with a future leg is not over")
        guard case .trip(let trip)? = timeline.next else { return XCTFail("expected a trip") }
        XCTAssertFalse(trip.isPast)
    }

    func testEmptyLibraryProducesAnEmptyTimeline() {
        let timeline = Timeline.build(from: [])
        XCTAssertTrue(timeline.isEmpty)
        XCTAssertNil(timeline.next)
    }

    func testPastPassCountAddsUpTicketsNotRows() {
        let multi = SavedPass(
            passType: "Event", title: "Family entry", eventDate: past,
            passDatas: [Data("a".utf8), Data("b".utf8), Data("c".utf8)]
        )
        let timeline = Timeline.build(from: [multi])
        XCTAssertEqual(timeline.pastPassCount, 3)
    }

    // MARK: - Segments

    func testSegmentSuppliesTheRouteDescription() {
        let leg = PassSegment(
            page: nil, label: nil, origin: "Málaga", destination: "Madrid",
            departDate: nil, departTime: "07:20", arriveDate: nil, arriveTime: "09:50",
            carrier: "AVLO", vehicleInfo: nil, seatInfo: "7A", travelClass: "Básico",
            confirmationNumber: nil, traveler: nil, notes: nil
        )
        let travelPass = pass("AVLO 02272", date: nearFuture, segment: leg)

        XCTAssertEqual(travelPass.segments.count, 1)
        XCTAssertEqual(travelPass.routeDescription, "Málaga → Madrid")
        XCTAssertEqual(travelPass.segments.first?.seatInfo, "7A")
    }

    func testRouteDegradesWhenOnlyOneEndIsKnown() {
        let leg = PassSegment(
            page: nil, label: nil, origin: "Málaga", destination: nil,
            departDate: nil, departTime: nil, arriveDate: nil, arriveTime: nil,
            carrier: nil, vehicleInfo: nil, seatInfo: nil, travelClass: nil,
            confirmationNumber: nil, traveler: nil, notes: nil
        )
        XCTAssertEqual(leg.routeDescription, "Málaga")
    }

    func testAPassWithoutSegmentsHasNoRoute() {
        XCTAssertNil(pass("Musée d'Orsay", date: nearFuture).routeDescription)
    }

    func testTripItineraryListsCitiesInOrderWithoutRepeats() {
        let lisbonToMalaga = PassSegment(
            page: nil, label: nil, origin: "Lisbon", destination: "Málaga",
            departDate: nil, departTime: nil, arriveDate: nil, arriveTime: nil,
            carrier: nil, vehicleInfo: nil, seatInfo: nil, travelClass: nil,
            confirmationNumber: nil, traveler: nil, notes: nil
        )
        let malagaToMadrid = PassSegment(
            page: nil, label: nil, origin: "Málaga", destination: "Madrid",
            departDate: nil, departTime: nil, arriveDate: nil, arriveTime: nil,
            carrier: nil, vehicleInfo: nil, seatInfo: nil, travelClass: nil,
            confirmationNumber: nil, traveler: nil, notes: nil
        )
        let timeline = Timeline.build(from: [
            pass("Leg 1", date: "Aug 14, 2027", groupId: "IB", groupName: "Iberia", segment: lisbonToMalaga),
            pass("Leg 2", date: "Aug 19, 2027", groupId: "IB", groupName: "Iberia", segment: malagaToMadrid)
        ])

        guard case .trip(let trip)? = timeline.next else { return XCTFail("expected a trip") }
        XCTAssertEqual(trip.itineraryCities, ["Lisbon", "Málaga", "Madrid"])
    }

    // MARK: - Decoding

    func testTripFieldsDecodeFromTheBackendPayload() throws {
        let json = """
        {
          "title": "AVLO 02272",
          "group_id": "QX7RM2",
          "group_name": "Summer in Iberia",
          "route": "Málaga → Madrid",
          "segment": {"origin": "Málaga", "destination": "Madrid", "depart_time": "07:20", "seat_info": "7A"}
        }
        """
        let decoded = try JSONDecoder().decode(EnhancedPassMetadata.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.groupId, "QX7RM2")
        XCTAssertEqual(decoded.groupName, "Summer in Iberia")
        XCTAssertEqual(decoded.route, "Málaga → Madrid")
        XCTAssertEqual(decoded.segment?.departTime, "07:20")
        XCTAssertEqual(decoded.segment?.seatInfo, "7A")
    }

    func testGroupIdentityIsDenormalisedOntoTheSavedPass() {
        // So passes can be grouped without decoding every metadata blob.
        let saved = pass("Leg", date: nearFuture, groupId: "QX7RM2", groupName: "Summer in Iberia")
        XCTAssertEqual(saved.groupId, "QX7RM2")
        XCTAssertEqual(saved.groupName, "Summer in Iberia")
    }

    /// The build that shipped as 45 was killed by the launch watchdog: the
    /// timeline rebuilt seventeen DateFormatters and re-decoded the whole
    /// metadata blob on every comparison, so a real library took the app past
    /// the 10-second scene-create budget. This is the guard.
    func testBuildingATimelineForAFullLibraryIsFast() {
        var passes: [SavedPass] = []
        for index in 0..<200 {
            passes.append(pass(
                "Pass \(index)",
                date: "2027-0\((index % 9) + 1)-1\(index % 9)",
                city: ["Madrid", "Lisbon", "Montevideo", "Paris"][index % 4],
                groupId: index % 3 == 0 ? "G\(index / 3)" : nil
            ))
        }

        let started = Date()
        let timeline = Timeline.build(from: passes)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertFalse(timeline.isEmpty)
        XCTAssertLessThan(elapsed, 1.0, "200 passes took \(elapsed)s — the launch watchdog allows 10s for everything")
    }

    func testAPassImportedBeforeTripsShippedHasNoTrip() {
        // Existing rows migrate with nil group fields and must stay standalone.
        let legacy = SavedPass(passType: "Event", title: "Old pass", eventDate: nearFuture)
        XCTAssertNil(legacy.tripId)
        XCTAssertTrue(legacy.segments.isEmpty)
    }
}
