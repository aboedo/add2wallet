import XCTest
@testable import Add2Wallet

/// The client-side grouping heuristic.
///
/// The backend sees one document at a time, so it cannot know that a flight
/// and a hotel are the same journey. These tests are the specification for
/// what the device infers from the whole library — and, just as importantly,
/// what it refuses to infer.
final class TripGroupingTests: XCTestCase {

    // MARK: - Helpers

    private func leg(_ origin: String?, _ destination: String?) -> PassSegment {
        PassSegment(
            page: nil, label: nil, origin: origin, destination: destination,
            departDate: nil, departTime: nil, arriveDate: nil, arriveTime: nil,
            carrier: nil, vehicleInfo: nil, seatInfo: nil, travelClass: nil,
            confirmationNumber: nil, traveler: nil, notes: nil
        )
    }

    private func pass(
        _ title: String,
        date: String?,
        city: String? = nil,
        type: String = "event_ticket",
        segment: PassSegment? = nil,
        groupId: String? = nil,
        confirmation: String? = nil,
        manualTripId: String? = nil
    ) -> SavedPass {
        SavedPass(
            passType: type,
            title: title,
            eventDate: date,
            city: city,
            metadata: EnhancedPassMetadata(
                eventType: type,
                city: city,
                confirmationNumber: confirmation,
                groupId: groupId,
                segment: segment
            ),
            manualTripId: manualTripId
        )
    }

    private func trips(_ passes: [SavedPass]) -> [Trip] {
        let timeline = Timeline.build(from: passes)
        return ([timeline.next].compactMap { $0 } + timeline.upcoming + timeline.past)
            .compactMap { if case .trip(let trip) = $0 { return trip } else { return nil } }
    }

    private func flight(_ from: String, _ to: String, _ date: String, confirmation: String) -> SavedPass {
        pass("\(from) → \(to)", date: date, type: "flight",
             segment: leg(from, to), confirmation: confirmation)
    }

    // MARK: - Home, and the round trip that defines a journey

    func testHomeIsThePlaceYouLeaveFromAndReturnTo() {
        let home = TripGrouping.inferHome(from: [
            flight("Montevideo", "Madrid", "Aug 14, 2027", confirmation: "1"),
            flight("Madrid", "Montevideo", "Aug 28, 2027", confirmation: "2"),
            flight("Montevideo", "Buenos Aires", "Nov 1, 2027", confirmation: "3"),
            flight("Buenos Aires", "Montevideo", "Nov 5, 2027", confirmation: "4")
        ])
        XCTAssertEqual(home, "montevideo")
    }

    func testASingleOneWayIsNotEnoughToCallSomewhereHome() {
        XCTAssertNil(TripGrouping.inferHome(from: [
            flight("Montevideo", "Madrid", "Aug 14, 2027", confirmation: "1")
        ]))
    }

    func testEverythingBetweenLeavingAndReturningIsOneTrip() {
        // The owner's model: out on the 14th, back on the 28th — the hotel and
        // the match in between belong to that journey even though they are not
        // travel themselves.
        let journey = trips([
            flight("Montevideo", "Madrid", "Aug 14, 2027", confirmation: "F1"),
            pass("Hotel Madrid", date: "Aug 15, 2027", city: "Madrid", type: "hotel", confirmation: "H"),
            pass("Museo Reina Sofía", date: "Aug 20, 2027", city: "Madrid", confirmation: "M"),
            flight("Madrid", "Montevideo", "Aug 28, 2027", confirmation: "F2"),
            pass("Local concert back home", date: "Sep 20, 2027", city: "Montevideo", confirmation: "L")
        ])

        XCTAssertEqual(journey.count, 1, "one journey; the concert after coming home is not part of it")
        XCTAssertEqual(journey.first?.passes.count, 4)
    }

    func testIntermediateHopsStayInsideTheSameTrip() {
        // MVD → MAD → LON, LON → Norway, Norway → MAD, MAD → MVD is one trip,
        // not four. Only the return home closes it.
        let journey = trips([
            flight("Montevideo", "Madrid", "Aug 14, 2027", confirmation: "1"),
            flight("Madrid", "London", "Aug 18, 2027", confirmation: "2"),
            flight("London", "Oslo", "Aug 22, 2027", confirmation: "3"),
            flight("Oslo", "Madrid", "Aug 26, 2027", confirmation: "4"),
            flight("Madrid", "Montevideo", "Aug 30, 2027", confirmation: "5"),
            // A second, separate journey later in the year proves home works.
            flight("Montevideo", "Buenos Aires", "Dec 1, 2027", confirmation: "6"),
            flight("Buenos Aires", "Montevideo", "Dec 4, 2027", confirmation: "7")
        ])

        XCTAssertEqual(journey.count, 2)
        XCTAssertEqual(journey.first?.passes.count, 5, "five legs, one journey")
    }

    func testAGapOfWeeksAbroadDoesNotSplitTheTrip() {
        // Time-based clustering broke exactly here: a month in Europe with a
        // quiet fortnight in the middle is still one trip.
        let journey = trips([
            flight("Montevideo", "Madrid", "Aug 1, 2027", confirmation: "1"),
            pass("Concert", date: "Aug 25, 2027", city: "Madrid", confirmation: "C"),
            flight("Madrid", "Montevideo", "Aug 30, 2027", confirmation: "2"),
            flight("Montevideo", "Madrid", "Dec 1, 2027", confirmation: "3"),
            flight("Madrid", "Montevideo", "Dec 9, 2027", confirmation: "4")
        ])

        XCTAssertEqual(journey.count, 2)
        XCTAssertEqual(journey.first?.passes.count, 3, "24 days apart, still one journey")
    }

    func testAJourneyWithNoReturnBookedStaysOpen() {
        let journey = trips([
            flight("Montevideo", "Madrid", "Aug 14, 2027", confirmation: "1"),
            flight("Madrid", "Montevideo", "Aug 20, 2027", confirmation: "2"),
            flight("Montevideo", "Lisbon", "Dec 1, 2027", confirmation: "3"),
            pass("Hotel Lisboa", date: "Dec 2, 2027", city: "Lisbon", type: "hotel", confirmation: "H")
        ])

        XCTAssertEqual(journey.count, 2)
        XCTAssertEqual(journey.last?.passes.count, 2, "the return may simply not be booked yet")
    }

    func testTripIsNamedAfterWhereYouWentNotWhenYouFiledIt() {
        let journey = trips([
            pass("MVD → MAD", date: "Aug 14, 2027", city: "Spain", type: "flight",
                 segment: leg("Montevideo", "Madrid"), confirmation: "1"),
            pass("MAD → LON", date: "Aug 18, 2027", city: "United Kingdom", type: "flight",
                 segment: leg("Madrid", "London"), confirmation: "2"),
            pass("MAD → MVD", date: "Aug 30, 2027", city: "Uruguay", type: "flight",
                 segment: leg("Madrid", "Montevideo"), confirmation: "3"),
            flight("Montevideo", "Madrid", "Dec 1, 2027", confirmation: "4"),
            flight("Madrid", "Montevideo", "Dec 9, 2027", confirmation: "5")
        ])

        let name = journey.first?.name ?? ""
        XCTAssertTrue(name.contains("Spain"), "got \(name)")
        XCTAssertTrue(name.contains("United Kingdom"), "got \(name)")
        XCTAssertFalse(name.contains("Uruguay"), "home is not a destination: \(name)")
    }

    func testLocalPlansBetweenTripsStayStandalone() {
        let timeline = Timeline.build(from: [
            flight("Montevideo", "Madrid", "Aug 14, 2027", confirmation: "1"),
            flight("Madrid", "Montevideo", "Aug 20, 2027", confirmation: "2"),
            pass("Local match", date: "Sep 5, 2027", city: "Montevideo", confirmation: "L1"),
            pass("Local theatre", date: "Sep 7, 2027", city: "Montevideo", confirmation: "L2")
        ])

        let loose = ([timeline.next].compactMap { $0 } + timeline.upcoming + timeline.past)
            .filter { if case .pass = $0 { return true } else { return false } }
        XCTAssertEqual(loose.count, 2, "life at home is not a trip")
    }

    // MARK: - The case the whole redesign is for

    func testAFlightHotelAndMatchInOneCityBecomeOneTrip() {
        // Four separate uploads, four different bookings. Only the device can
        // see that they are one journey.
        let journey = trips([
            pass("Air Europa MAD → LIS", date: "Aug 14, 2027", city: "Lisbon",
                 type: "flight", segment: leg("Madrid", "Lisbon"), confirmation: "AE-1"),
            pass("Hotel Lisboa Plaza", date: "Aug 14, 2027", city: "Lisbon",
                 type: "hotel", confirmation: "HTL-2"),
            pass("SL Benfica × FC Porto", date: "Aug 15, 2027", city: "Lisbon",
                 confirmation: "SLB-3")
        ])

        XCTAssertEqual(journey.count, 1, "one journey, not three loose passes")
        XCTAssertEqual(journey.first?.passes.count, 3)
    }

    func testAChainOfLegsLinksThroughSharedPlaces() {
        // Lisbon → Málaga, then Málaga → Madrid: adjacent in time, connected
        // by a city that appears on both.
        let journey = trips([
            pass("Flight", date: "Aug 14, 2027", type: "flight",
                 segment: leg("Lisbon", "Málaga"), confirmation: "F1"),
            pass("AVLO", date: "Aug 16, 2027", type: "transit",
                 segment: leg("Málaga", "Madrid"), confirmation: "T1")
        ])

        XCTAssertEqual(journey.count, 1)
        XCTAssertEqual(journey.first?.itineraryCities, ["Lisbon", "Málaga", "Madrid"])
    }

    // MARK: - What it must refuse to infer

    func testTwoLocalEventsInTheSameCityAreNotATrip() {
        // A busy week at home is not a journey. Without a travel signal or a
        // second place, we have no evidence of going anywhere.
        let journey = trips([
            pass("Coldplay", date: "Aug 14, 2027", city: "Montevideo", confirmation: "C1"),
            pass("Hamilton", date: "Aug 16, 2027", city: "Montevideo", confirmation: "H1")
        ])

        XCTAssertTrue(journey.isEmpty, "same city, no travel — these stay separate passes")
    }

    func testItemsFurtherApartThanTheGapAreNotClustered() {
        let journey = trips([
            pass("Flight out", date: "Aug 1, 2027", city: "Lisbon",
                 type: "flight", segment: leg("Madrid", "Lisbon"), confirmation: "A"),
            pass("Concert", date: "Aug 20, 2027", city: "Lisbon", confirmation: "B")
        ])

        XCTAssertTrue(journey.isEmpty, "nineteen days apart is not one journey")
    }

    func testReimportingTheSameTicketDoesNotInventATrip() {
        // The backend falls back to the confirmation number for group_id, so
        // a retry produces two rows sharing a reference.
        let duplicate = { self.pass("Air Europa MAD → LIS", date: "Aug 14, 2027", city: "Lisbon",
                                    type: "flight", groupId: "AE-1", confirmation: "AE-1") }
        XCTAssertTrue(trips([duplicate(), duplicate()]).isEmpty)
    }

    func testUndatedPassesNeverJoinAJourney() {
        let journey = trips([
            pass("Flight", date: "Aug 14, 2027", city: "Lisbon",
                 type: "flight", segment: leg("Madrid", "Lisbon"), confirmation: "F"),
            pass("Ticket with no date", date: nil, city: "Lisbon", confirmation: "N")
        ])

        XCTAssertTrue(journey.isEmpty, "no date means no evidence of belonging anywhere")
    }

    // MARK: - Signals that are data, not guesses

    func testAManualAssignmentIsHonouredEvenWithoutAnyTravelSignal() {
        let journey = trips([
            pass("Coldplay", date: "Aug 14, 2027", city: "Montevideo", manualTripId: "MINE"),
            pass("Hamilton", date: "Nov 2, 2027", city: "Montevideo", manualTripId: "MINE")
        ])

        XCTAssertEqual(journey.count, 1, "the user said so — dates and places do not get a vote")
        XCTAssertEqual(journey.first?.id, "MINE")
    }

    func testASharedBookingReferenceGroupsAcrossAnyGap() {
        // Outbound and return of one reservation, uploaded separately.
        let journey = trips([
            pass("Outbound", date: "Aug 14, 2027", city: "Lisbon", type: "flight", groupId: "QX7RM2"),
            pass("Return", date: "Sep 30, 2027", city: "Madrid", type: "flight", groupId: "QX7RM2")
        ])

        XCTAssertEqual(journey.count, 1)
        XCTAssertEqual(journey.first?.id, "QX7RM2")
    }

    func testABookingReferenceOnlyCountsWhenEveryMemberAgrees() {
        let mixed = [
            pass("A", date: "Aug 14, 2027", city: "Lisbon", groupId: "REF-1"),
            pass("B", date: "Aug 15, 2027", city: "Lisbon", groupId: "REF-2")
        ]
        XCTAssertNil(TripGrouping.sharedBookingReference(in: mixed))
    }

    func testTwoVenuesInTheSameCityAreNotTwoPlaces() {
        // A venue is a building, not a place you travel between. Counting them
        // promoted an afternoon of museums in Paris into a "trip".
        let journey = trips([
            pass("Eiffel Tower", date: "Sep 14, 2027", city: "Paris", confirmation: "E"),
            pass("Musée d'Orsay", date: "Sep 15, 2027", city: "Paris", confirmation: "O")
        ])
        XCTAssertTrue(journey.isEmpty, "same city, different venues — still not a journey")
    }

    // MARK: - Normalisation

    func testPlacesMatchAcrossAccentsAndCasing() {
        let journey = trips([
            pass("Train", date: "Aug 14, 2027", type: "transit",
                 segment: leg("Madrid", "MÁLAGA"), confirmation: "T"),
            pass("Museum", date: "Aug 15, 2027", city: "malaga", confirmation: "M")
        ])

        XCTAssertEqual(journey.count, 1, "\"MÁLAGA\" and \"malaga\" are one place")
    }

    // MARK: - Travel signal

    func testTransportAndAccommodationCountAsTravel() {
        for type in ["flight", "boarding_pass", "transit", "train", "bus", "ferry", "hotel"] {
            XCTAssertTrue(
                pass("P", date: "Aug 14, 2027", type: type).impliesTravel,
                "\(type) should read as travel"
            )
        }
    }

    func testAnEventTicketAloneIsNotTravel() {
        XCTAssertFalse(pass("Concert", date: "Aug 14, 2027", type: "event_ticket").impliesTravel)
    }

    func testARoundTripLegIsNotTravelBetweenPlaces() {
        // Origin equal to destination tells us nothing about going anywhere.
        let circular = pass("Tour", date: "Aug 14, 2027", type: "event_ticket",
                            segment: leg("Lisbon", "Lisbon"))
        XCTAssertFalse(circular.impliesTravel)
    }

    // MARK: - Everything lands somewhere

    func testEveryPassAppearsExactlyOnceAcrossAllClusters() {
        let passes = [
            pass("Flight", date: "Aug 14, 2027", city: "Lisbon", type: "flight",
                 segment: leg("Madrid", "Lisbon"), confirmation: "1"),
            pass("Hotel", date: "Aug 14, 2027", city: "Lisbon", type: "hotel", confirmation: "2"),
            pass("Loose concert", date: "Dec 1, 2027", city: "Montevideo", confirmation: "3"),
            pass("Undated", date: nil, confirmation: "4"),
            pass("Old", date: "Jan 1, 2024", city: "Paris", confirmation: "5")
        ]

        let clustered = TripGrouping.cluster(passes).flatMap { $0 }
        XCTAssertEqual(Set(clustered.map(\.id)).count, passes.count, "no pass lost, none duplicated")
    }
}
