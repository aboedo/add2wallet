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
