import XCTest
import PassKit
@testable import Add2Wallet

/// Does PassKit actually accept what the backend builds?
///
/// Every check we had ran on our side of the fence: the JSON has the right
/// keys, the manifest hashes match, the signature is present. A `.pkpass` can
/// pass all of that and still be refused at the last step with "the data
/// format is invalid", which is the error Andy hit — and nothing in the suite
/// would have caught it, because nothing asked the framework that decides.
///
/// The fixture is a real pass built from the real Fjord Tours itinerary.
final class PassKitAcceptanceTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: "pkpass"),
            "Missing fixture \(name).pkpass — it must be in Add2WalletTests/Resources"
        )
        return try Data(contentsOf: url)
    }

    func testPassKitAcceptsAGeneratedPass() throws {
        let data = try fixture("nutshell-leg")

        // The exact call the app makes before handing anything to Wallet. It
        // throws rather than returning nil, and the error it throws is the one
        // the user sees.
        let pass = try PKPass(data: data)

        XCTAssertEqual(pass.passTypeIdentifier, "pass.com.andresboedo.add2wallet")
        XCTAssertFalse(pass.serialNumber.isEmpty)
    }

    /// The leg's own detail has to survive into the pass, not just the
    /// document's. A five-leg itinerary whose passes all say the same thing is
    /// the bug this whole area exists to prevent.
    func testAPassCarriesItsOwnLegRatherThanTheWholeDocument() throws {
        let pass = try PKPass(data: try fixture("nutshell-leg"))

        let description = pass.localizedDescription
        XCTAssertTrue(
            description.contains("Bergen"),
            "Expected the leg's own route in the description, got \(description)"
        )
    }

    func testGarbageIsRejectedSoThisTestCanFail() throws {
        // Guards the test itself: if `PKPass(data:)` accepted anything, the
        // assertions above would be worthless.
        XCTAssertThrowsError(try PKPass(data: Data("not a pass".utf8)))
    }
}
