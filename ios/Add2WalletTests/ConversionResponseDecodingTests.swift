import XCTest
@testable import Add2Wallet

/// Can the app read what the server actually sends?
///
/// "The data couldn't be read because it is missing" is a `DecodingError`, not
/// a PassKit error — it means a key the model requires was absent from the
/// response. Nothing in the suite decoded a *real* server payload, so a field
/// added on one side and required on the other could not be caught until
/// someone hit it on a device.
///
/// The fixture is the verbatim production response for the Fjord Tours
/// itinerary, captured from `POST /api/v1/conversions`.
final class ConversionResponseDecodingTests: XCTestCase {

    private func fixture() throws -> Data {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "fjord-conversion-response", withExtension: "json"),
            "Missing fixture fjord-conversion-response.json"
        )
        return try Data(contentsOf: url)
    }

    func testTheRealProductionResponseDecodes() throws {
        let response = try JSONDecoder().decode(UploadResponse.self, from: try fixture())

        XCTAssertEqual(response.status, "completed")
        XCTAssertFalse(response.jobId.isEmpty)
    }

    /// The count drives how many passes the app downloads, so a wrong or
    /// missing one is the difference between ten passes and a crash.
    func testItCarriesEveryTicketTheDocumentIsWorth() throws {
        let response = try JSONDecoder().decode(UploadResponse.self, from: try fixture())

        XCTAssertEqual(response.ticketCount, 10, "Five legs, two travellers each")
    }

    func testTheLegDetailSurvivesTheRoundTrip() throws {
        let response = try JSONDecoder().decode(UploadResponse.self, from: try fixture())
        let segment = try XCTUnwrap(response.aiMetadata?.segment)

        XCTAssertEqual(segment.origin, "Bergen")
        XCTAssertEqual(segment.destination, "Voss")
    }

    /// Guards the test itself: if the decoder tolerated anything, the
    /// assertions above would prove nothing.
    func testAResponseMissingARequiredKeyIsRejected() throws {
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try fixture()) as? [String: Any]
        )
        payload.removeValue(forKey: "job_id")
        let data = try JSONSerialization.data(withJSONObject: payload)

        XCTAssertThrowsError(try JSONDecoder().decode(UploadResponse.self, from: data))
    }
}
