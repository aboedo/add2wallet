import XCTest
@testable import Add2Wallet

/// What a record is called when it stands for several passes.
///
/// A multi-ticket import stores the first ticket's title — "Coldplay #1", or
/// the opening leg of an itinerary — so every list, card and detail header
/// named the set after one of its members. The backend now sends a name for
/// the booking as a whole.
final class PassGroupTitleTests: XCTestCase {

    private func pass(_ title: String, groupName: String? = nil, tickets: Int) -> SavedPass {
        SavedPass(
            passType: "Event",
            title: title,
            passDatas: Array(repeating: Data("pkpass".utf8), count: tickets),
            metadata: EnhancedPassMetadata(groupName: groupName)
        )
    }

    func testASetIsNamedByTheBookingRatherThanItsFirstTicket() {
        let set = pass("Coldplay #1", groupName: "Coldplay at Wembley", tickets: 4)
        XCTAssertEqual(set.displayGroupTitle, "Coldplay at Wembley")
    }

    func testAnItineraryIsNamedByTheJourneyRatherThanItsFirstLeg() {
        let set = pass("Train Bergen to Voss", groupName: "Norway in a Nutshell", tickets: 5)
        XCTAssertEqual(set.displayGroupTitle, "Norway in a Nutshell")
    }

    func testASetWithNoNameKeepsUsingItsOwnTitle() {
        let set = pass("Coldplay #1", tickets: 4)
        XCTAssertEqual(set.displayGroupTitle, "Coldplay #1")
    }

    func testBlankNamesAreNotTitles() {
        let set = pass("Coldplay #1", groupName: "   ", tickets: 4)
        XCTAssertEqual(set.displayGroupTitle, "Coldplay #1")
    }

    /// On a single pass `groupName` is the *trip's* name — "Summer in Iberia"
    /// — which would be the wrong thing to call one flight inside it.
    func testASinglePassIsStillCalledByItsOwnName() {
        let single = pass("AVLO Málaga → Madrid", groupName: "Summer in Iberia", tickets: 1)
        XCTAssertEqual(single.displayGroupTitle, "AVLO Málaga → Madrid")
    }
}
