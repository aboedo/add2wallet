import XCTest
import Combine
import UniformTypeIdentifiers
@testable import Add2Wallet

final class FileUploadTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        cancellables.removeAll()
        super.tearDown()
    }

    func testSupportedFileMIMETypes() {
        XCTAssertEqual(SupportedFile.mimeType(for: "ticket.pdf"), "application/pdf")
        XCTAssertEqual(SupportedFile.mimeType(for: "ticket.jpg"), "image/jpeg")
        XCTAssertEqual(SupportedFile.mimeType(for: "ticket.JPEG"), "image/jpeg")
        XCTAssertEqual(SupportedFile.mimeType(for: "ticket.png"), "image/png")
        XCTAssertEqual(SupportedFile.mimeType(for: "ticket.heic"), "image/heic")
        XCTAssertEqual(SupportedFile.mimeType(for: "ticket.heif"), "image/heif")
    }

    func testSupportedFileTypeDetectionAcceptsUppercaseImageExtensions() {
        XCTAssertEqual(SupportedFile.contentType(for: "Boarding Pass.HEIC")?.identifier, UTType.heic.identifier)
        XCTAssertEqual(SupportedFile.contentType(for: "Boarding Pass.PNG")?.identifier, UTType.png.identifier)
        XCTAssertTrue(SupportedFile.isImage(URL(fileURLWithPath: "/tmp/Boarding Pass.JPEG")))
        XCTAssertFalse(SupportedFile.isImage(URL(fileURLWithPath: "/tmp/Boarding Pass.pdf")))
    }

    func testImageUploadsUseConversionsEndpointAndActualMIMEType() {
        let cases = [
            ("ticket.jpg", "image/jpeg"),
            ("ticket.png", "image/png"),
            ("ticket.heic", "image/heic"),
            ("ticket.heif", "image/heif")
        ]

        for (filename, expectedMIMEType) in cases {
            let expectation = expectation(description: filename)
            let session = makeStubSession()
            let service = NetworkService(
                baseURL: URL(string: "https://example.com")!,
                session: session,
                appUserIDProvider: { "test-user" }
            )

            URLProtocolStub.requestHandler = { request in
                XCTAssertEqual(request.url?.path, "/api/v1/conversions")
                XCTAssertEqual(request.httpMethod, "POST")

                let body = String(data: Self.bodyData(from: request), encoding: .utf8) ?? ""
                XCTAssertTrue(body.contains("filename=\"\(filename)\""))
                XCTAssertTrue(body.contains("Content-Type: \(expectedMIMEType)"))
                XCTAssertTrue(body.contains("name=\"user_id\""))
                XCTAssertTrue(body.contains("test-user"))
                XCTAssertTrue(body.contains("name=\"session_token\""))
                XCTAssertTrue(body.contains("name=\"is_retry\""))
                XCTAssertTrue(body.contains("name=\"is_demo\""))

                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let json = Data("{\"job_id\":\"job-1\",\"status\":\"queued\",\"remaining_passes\":4}".utf8)
                return (response, json)
            }

            service.uploadFile(data: Data([0x01, 0x02]), filename: filename)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            XCTFail("Upload failed: \(error)")
                        }
                    },
                    receiveValue: { response in
                        XCTAssertEqual(response.jobId, "job-1")
                        XCTAssertEqual(response.status, "queued")
                        XCTAssertEqual(response.remainingPasses, 4)
                        expectation.fulfill()
                    }
                )
                .store(in: &cancellables)

            wait(for: [expectation], timeout: 2)
            session.invalidateAndCancel()
            cancellables.removeAll()
        }
    }

    func testUploadResponseDecodesExistingContractWithoutRemainingPasses() throws {
        let json = Data("{\"job_id\":\"legacy\",\"status\":\"completed\",\"pass_url\":\"/pass/legacy\",\"ticket_count\":1}".utf8)
        let response = try JSONDecoder().decode(UploadResponse.self, from: json)

        XCTAssertEqual(response.jobId, "legacy")
        XCTAssertEqual(response.passUrl, "/pass/legacy")
        XCTAssertEqual(response.ticketCount, 1)
        XCTAssertNil(response.remainingPasses)
    }

    func testTokenHandoffPreservesImageFilenameDataAndContentType() throws {
        _ = URLHandler.dequeuePendingFile()

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let token = "handoff-token"
        let tokenDirectory = root
            .appendingPathComponent("shared", isDirectory: true)
            .appendingPathComponent(token, isDirectory: true)
        try FileManager.default.createDirectory(at: tokenDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            _ = URLHandler.dequeuePendingFile()
        }

        let filename = "Boarding Pass.HEIC"
        let data = Data([0x00, 0x01, 0x02, 0x03])
        try data.write(to: tokenDirectory.appendingPathComponent(filename))
        let metadata: [String: String] = [
            "filename": filename,
            "storedFilename": filename,
            "contentType": UTType.heic.identifier
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        try metadataData.write(to: tokenDirectory.appendingPathComponent("metadata.json"))

        URLHandler.handleSharedFile(withToken: token, sharedContainer: root)

        let pending = URLHandler.dequeuePendingFile()
        XCTAssertEqual(pending?.filename, filename)
        XCTAssertEqual(pending?.data, data)
        XCTAssertEqual(pending?.contentTypeIdentifier, UTType.heic.identifier)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tokenDirectory.path))
    }

    func testLegacySharedFileHandoffPreservesImageFilename() throws {
        _ = URLHandler.dequeuePendingFile()

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            _ = URLHandler.dequeuePendingFile()
        }

        let filename = "ticket-scan.png"
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        try data.write(to: root.appendingPathComponent(filename))
        let metadata: [String: String] = [
            "filename": filename,
            "storedFilename": filename,
            "contentType": UTType.png.identifier
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        try metadataData.write(to: root.appendingPathComponent("shared_pdf.json"))

        URLHandler.checkForSharedFile(in: root)

        let pending = URLHandler.dequeuePendingFile()
        XCTAssertEqual(pending?.filename, filename)
        XCTAssertEqual(pending?.data, data)
        XCTAssertEqual(pending?.contentTypeIdentifier, UTType.png.identifier)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("shared_pdf.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(filename).path))
    }

    func testSavedPassUsesStoredSourceContentTypeForSupportAttachments() {
        let savedPass = SavedPass(
            passType: "concert",
            title: "Test",
            passDatas: [],
            pdfData: Data([0x00]),
            sourceFilename: "camera-upload",
            sourceContentTypeIdentifier: UTType.heic.identifier
        )

        XCTAssertEqual(savedPass.sourceMIMEType, "image/heic")
        XCTAssertEqual(savedPass.effectiveSourceFilename, "camera-upload")
    }

    private func makeStubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private static func bodyData(from request: URLRequest) -> Data {
        if let httpBody = request.httpBody {
            return httpBody
        }

        guard let stream = request.httpBodyStream else {
            return Data()
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: bufferSize)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class URLProtocolStub: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.requestHandler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
