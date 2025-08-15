import XCTest
import SwiftData
import Foundation
@testable import Add2Wallet

// MARK: - Test Helpers

class TestHelpers {
    
    // MARK: - SwiftData Test Container
    
    static func createTestModelContainer() -> ModelContainer {
        let schema = Schema([SavedPass.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true, // Use in-memory storage for tests
            allowsSave: true
        )
        
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create test model container: \(error)")
        }
    }
    
    // MARK: - Test Data Factories
    
    static func createTestPDFData() -> Data {
        // Create minimal valid PDF data for testing
        let pdfHeader = "%PDF-1.4\n"
        let pdfBody = "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
        let pdfFooter = "xref\n0 3\n0000000000 65535 f \ntrailer\n<< /Size 3 /Root 1 0 R >>\nstartxref\n9\n%%EOF"
        return (pdfHeader + pdfBody + pdfFooter).data(using: .utf8) ?? Data()
    }
    
    static func createTestEnhancedPassMetadata() -> EnhancedPassMetadata {
        return EnhancedPassMetadata(
            eventType: "concert",
            eventName: "Test Concert",
            title: "Amazing Test Concert",
            description: "A test concert for unit testing",
            date: "2024-12-15",
            time: "19:30",
            duration: "3 hours",
            venueName: "Test Venue",
            venueAddress: "123 Test Street",
            city: "Test City",
            stateCountry: "Test State",
            latitude: 37.7749,
            longitude: -122.4194,
            organizer: "Test Organizer",
            performerArtist: "Test Artist",
            seatInfo: "Section A, Row 5, Seat 12",
            barcodeData: "123456789",
            price: "$75.00",
            confirmationNumber: "ABC123",
            gateInfo: "Gate B",
            eventDescription: "An amazing test concert experience",
            venueType: "concert hall",
            capacity: "2000",
            website: "https://testconcert.com",
            phone: "+1-555-0123",
            nearbyLandmarks: ["Test Park", "Test Mall"],
            publicTransport: "Bus line 42, Metro Red Line",
            parkingInfo: "Free parking available",
            ageRestriction: "All ages",
            dressCode: "Casual",
            weatherConsiderations: "Indoor venue",
            amenities: ["Concessions", "Restrooms", "WiFi"],
            accessibility: "Wheelchair accessible",
            aiProcessed: true,
            confidenceScore: 85,
            processingTimestamp: "2024-01-15T10:30:00Z",
            modelUsed: "gpt-4",
            enrichmentCompleted: true,
            backgroundColor: "rgb(255,45,85)",
            foregroundColor: "rgb(255,255,255)",
            labelColor: "rgb(0,0,0)"
        )
    }
    
    static func createTestSavedPass() -> SavedPass {
        let metadata = createTestEnhancedPassMetadata()
        return SavedPass(
            passType: "concert",
            title: "Test Concert Pass",
            eventDate: "2024-12-15",
            venue: "Test Venue",
            city: "Test City",
            passDatas: [createTestPDFData()],
            pdfData: createTestPDFData(),
            metadata: metadata
        )
    }
    
    // MARK: - Bundle Helpers
    
    static func loadTestResource(named name: String, withExtension ext: String) -> Data? {
        guard let url = Bundle(for: TestHelpers.self).url(forResource: name, withExtension: ext) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }
    
    static func loadTestPDF(named name: String) -> Data? {
        return loadTestResource(named: name, withExtension: "pdf")
    }
    
    static func loadTestJSON(named name: String) -> Data? {
        return loadTestResource(named: name, withExtension: "json")
    }
    
    // MARK: - Assertion Helpers
    
    static func assertMetadataEqual(_ metadata1: EnhancedPassMetadata?, _ metadata2: EnhancedPassMetadata?, file: StaticString = #filePath, line: UInt = #line) {
        guard let metadata1 = metadata1, let metadata2 = metadata2 else {
            XCTFail("One or both metadata objects are nil", file: file, line: line)
            return
        }
        
        XCTAssertEqual(metadata1.eventType, metadata2.eventType, file: file, line: line)
        XCTAssertEqual(metadata1.eventName, metadata2.eventName, file: file, line: line)
        XCTAssertEqual(metadata1.title, metadata2.title, file: file, line: line)
        XCTAssertEqual(metadata1.date, metadata2.date, file: file, line: line)
        XCTAssertEqual(metadata1.time, metadata2.time, file: file, line: line)
        XCTAssertEqual(metadata1.venueName, metadata2.venueName, file: file, line: line)
        XCTAssertEqual(metadata1.city, metadata2.city, file: file, line: line)
        XCTAssertEqual(metadata1.barcodeData, metadata2.barcodeData, file: file, line: line)
    }
    
    // MARK: - Async Test Helpers
    
    static func waitForAsync<T>(
        timeout: TimeInterval = 5.0,
        operation: @escaping () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw TestError.timeout
            }
            
            guard let result = try await group.next() else {
                throw TestError.noResult
            }
            
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Test Errors

enum TestError: Error {
    case timeout
    case noResult
    case mockDataNotFound(String)
}

// MARK: - Extensions for Testing

extension XCTestCase {
    
    func loadTestResource(named name: String, withExtension ext: String) -> Data {
        guard let data = TestHelpers.loadTestResource(named: name, withExtension: ext) else {
            XCTFail("Failed to load test resource: \(name).\(ext)")
            return Data()
        }
        return data
    }
    
    func loadTestPDF(named name: String) -> Data {
        guard let data = TestHelpers.loadTestPDF(named: name) else {
            XCTFail("Failed to load test PDF: \(name).pdf")
            return Data()
        }
        return data
    }
    
    func createTestModelContext() -> ModelContext {
        let container = TestHelpers.createTestModelContainer()
        return ModelContext(container)
    }
}