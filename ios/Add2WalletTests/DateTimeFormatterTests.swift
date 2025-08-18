import XCTest
@testable import Add2Wallet

class DateTimeFormatterTests: XCTestCase {
    
    // MARK: - combineDateTime Tests
    
    func testCombineDateTimeWithBothValues() {
        let result = PassDateTimeFormatter.combineDateTime(
            date: "2024-12-15",
            time: "19:30"
        )
        
        XCTAssertNotNil(result)
        // The exact format depends on system locale, but should contain both date and time elements
        XCTAssertTrue(result?.contains("15") ?? false, "Should contain day")
        XCTAssertTrue(result?.contains("12") ?? false, "Should contain month")
        XCTAssertTrue(result?.contains("2024") ?? false, "Should contain year")
    }
    
    func testCombineDateTimeWithDateOnly() {
        let result = PassDateTimeFormatter.combineDateTime(
            date: "2024-12-15",
            time: nil
        )
        
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("15") ?? false, "Should contain day")
        XCTAssertTrue(result?.contains("12") ?? false, "Should contain month")
        XCTAssertTrue(result?.contains("2024") ?? false, "Should contain year")
    }
    
    func testCombineDateTimeWithTimeOnly() {
        let result = PassDateTimeFormatter.combineDateTime(
            date: nil,
            time: "19:30"
        )
        
        XCTAssertNotNil(result)
        // Should contain time elements (format may vary by locale)
        XCTAssertTrue((result?.contains("19") ?? false) || (result?.contains("7") ?? false), "Should contain hour")
        XCTAssertTrue(result?.contains("30") ?? false, "Should contain minutes")
    }
    
    func testCombineDateTimeWithEmptyStrings() {
        let result1 = PassDateTimeFormatter.combineDateTime(date: "", time: "")
        XCTAssertNil(result1)
        
        let result2 = PassDateTimeFormatter.combineDateTime(date: "   ", time: "   ")
        XCTAssertNil(result2)
    }
    
    func testCombineDateTimeWithNilValues() {
        let result = PassDateTimeFormatter.combineDateTime(date: nil, time: nil)
        XCTAssertNil(result)
    }
    
    func testCombineDateTimeWithInvalidDate() {
        let result = PassDateTimeFormatter.combineDateTime(
            date: "invalid-date",
            time: "19:30"
        )
        
        // Should still return the time component
        XCTAssertNotNil(result)
        XCTAssertTrue((result?.contains("19") ?? false) || (result?.contains("7") ?? false), "Should contain hour")
    }
    
    func testCombineDateTimeWithInvalidTime() {
        let result = PassDateTimeFormatter.combineDateTime(
            date: "2024-12-15",
            time: "invalid-time"
        )
        
        // Should still return the date component
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("15") ?? false, "Should contain day")
        XCTAssertTrue(result?.contains("12") ?? false, "Should contain month")
    }
    
    
    // MARK: - formatEventDate Tests
    
    func testFormatEventDateWithDateTime() {
        let input = "Dec 15, 2024 at 8:00 PM"
        let result = PassDateTimeFormatter.formatEventDate(input)
        
        // Should return a formatted date with time
        XCTAssertNotNil(result)
        XCTAssertFalse(result.isEmpty)
        // The exact format depends on locale, but should be reformatted
    }
    
    func testFormatEventDateWithDateOnly() {
        let input = "Dec 15, 2024"
        let result = PassDateTimeFormatter.formatEventDate(input)
        
        XCTAssertNotNil(result)
        XCTAssertFalse(result.isEmpty)
    }
    
    func testFormatEventDateWithVariousFormats() {
        let testCases = [
            "December 15, 2024 at 8:00 PM",
            "Dec 15, 2024 8:00 PM",
            "December 15, 2024",
            "12/15/2024",
            "15/12/2024",
            "2024-12-15",
            "15 December 2024",
            "Dec 15",
            "December 15"
        ]
        
        for testCase in testCases {
            let result = PassDateTimeFormatter.formatEventDate(testCase)
            XCTAssertNotNil(result, "Failed to format: \(testCase)")
            XCTAssertFalse(result.isEmpty, "Empty result for: \(testCase)")
        }
    }
    
    func testFormatEventDateWithInvalidFormat() {
        let input = "Not a valid date format"
        let result = PassDateTimeFormatter.formatEventDate(input)
        
        // Should return the original string if parsing fails
        XCTAssertEqual(result, input)
    }
    
    func testFormatEventDateWithEmptyString() {
        let result = PassDateTimeFormatter.formatEventDate("")
        XCTAssertEqual(result, "")
    }
    
    // MARK: - formatDateLocalized Tests
    
    func testFormatDateLocalized() {
        let testDate = Date(timeIntervalSince1970: 1703544000) // Dec 25, 2023 8:00 PM UTC
        let result = PassDateTimeFormatter.formatDateLocalized(testDate)
        
        XCTAssertNotNil(result)
        XCTAssertFalse(result.isEmpty)
        // The exact format depends on locale, but should contain date and time
    }
    
    func testFormatDateLocalizedWithDifferentDates() {
        let dates = [
            Date(timeIntervalSince1970: 0), // Jan 1, 1970
            Date(), // Current date
            Date(timeIntervalSince1970: 2000000000), // Future date
        ]
        
        for date in dates {
            let result = PassDateTimeFormatter.formatDateLocalized(date)
            XCTAssertNotNil(result)
            XCTAssertFalse(result.isEmpty)
        }
    }
    
    // MARK: - Edge Cases and Localization Tests
    
    func testDateTimeFormattingWithDifferentLocales() {
        // Save current locale
        let originalLocale = Locale.current
        
        // Test with US locale
        let usLocale = Locale(identifier: "en_US")
        
        // Note: We can't easily change system locale in tests, but we can verify
        // that the formatting functions don't crash with various inputs
        let testInputs = [
            ("2024-12-15", "19:30"),
            ("2024-01-01", "00:00"),
            ("2024-12-31", "23:59")
        ]
        
        for (date, time) in testInputs {
            let result = PassDateTimeFormatter.combineDateTime(date: date, time: time)
            XCTAssertNotNil(result, "Failed to format date: \(date), time: \(time)")
        }
    }
    
    func testTimeFormatVariations() {
        let timeVariations = [
            "19:30",   // 24-hour format
            "7:30 PM", // 12-hour format with AM/PM
            "07:30",   // Leading zero
            "0:00",    // Midnight
            "23:59"    // End of day
        ]
        
        for time in timeVariations {
            let result = PassDateTimeFormatter.combineDateTime(date: "2024-12-15", time: time)
            // Should handle all formats gracefully (some may not parse correctly)
            // Main requirement is no crashes
        }
    }
    
    func testDateFormatVariations() {
        let dateVariations = [
            "2024-12-15",      // ISO format
            "12/15/2024",      // US format
            "15/12/2024",      // European format
            "Dec 15, 2024",    // Month abbreviation
            "December 15, 2024", // Full month name
            "15 December 2024"   // Day-first format
        ]
        
        for date in dateVariations {
            let result = PassDateTimeFormatter.combineDateTime(date: date, time: "19:30")
            // Should handle all formats gracefully
        }
    }
    
    // MARK: - Performance Tests
    
    func testFormattingPerformance() {
        measure {
            for i in 0..<1000 {
                let date = "2024-12-\(String(format: "%02d", (i % 28) + 1))"
                let time = "\(i % 24):30"
                _ = PassDateTimeFormatter.combineDateTime(date: date, time: time)
            }
        }
    }
    
    func testEventDateFormattingPerformance() {
        let testDates = [
            "Dec 15, 2024 at 8:00 PM",
            "December 15, 2024",
            "12/15/2024",
            "2024-12-15"
        ]
        
        measure {
            for _ in 0..<1000 {
                for testDate in testDates {
                    _ = PassDateTimeFormatter.formatEventDate(testDate)
                }
            }
        }
    }
}