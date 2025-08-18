import XCTest
import SwiftUI
import UIKit
@testable import Add2Wallet

class PassColorUtilsTests: XCTestCase {
    
    // MARK: - RGB Color Parsing Tests
    
    func testParseRGBColorValidFormats() {
        // Test standard format
        let color1 = PassColorUtils.parseRGBColor("rgb(255, 0, 0)")
        XCTAssertNotNil(color1, "Should parse standard RGB format")
        
        // Test format without spaces
        let color2 = PassColorUtils.parseRGBColor("rgb(0,255,0)")
        XCTAssertNotNil(color2, "Should parse RGB without spaces")
        
        // Test uppercase
        let color3 = PassColorUtils.parseRGBColor("RGB(0, 0, 255)")
        XCTAssertNotNil(color3, "Should parse uppercase RGB")
        
        // Test with extra spaces
        let color4 = PassColorUtils.parseRGBColor("rgb( 128 , 128 , 128 )")
        XCTAssertNotNil(color4, "Should parse RGB with extra spaces")
    }
    
    func testParseRGBColorInvalidFormats() {
        // Test invalid formats
        let invalidFormats = [
            "rgb(256, 0, 0)",          // Out of range
            "rgb(-1, 0, 0)",           // Negative value
            "rgb(255, 0)",             // Missing component
            "rgb(255, 0, 0, 0)",       // Extra component
            "rgba(255, 0, 0, 1.0)",    // RGBA format
            "not-a-color",             // Complete invalid
            "",                        // Empty string
            "rgb()",                   // Empty RGB
            "rgb(abc, def, ghi)"       // Non-numeric values
        ]
        
        for format in invalidFormats {
            let result = PassColorUtils.parseRGBColor(format)
            XCTAssertNil(result, "Should return nil for invalid format: \(format)")
        }
    }
    
    func testParseRGBColorBoundaryValues() {
        // Test boundary values
        let color1 = PassColorUtils.parseRGBColor("rgb(0, 0, 0)")
        XCTAssertNotNil(color1, "Should parse black (0,0,0)")
        
        let color2 = PassColorUtils.parseRGBColor("rgb(255, 255, 255)")
        XCTAssertNotNil(color2, "Should parse white (255,255,255)")
        
        let color3 = PassColorUtils.parseRGBColor("rgb(128, 128, 128)")
        XCTAssertNotNil(color3, "Should parse gray (128,128,128)")
    }
    
    // MARK: - Event Type Color Mapping Tests
    
    func testFallbackColorFromEventType() {
        // Create test metadata for different event types
        let flightMetadata = EnhancedPassMetadata(
            eventType: "flight",
            eventName: "Test Flight",
            title: nil, description: nil, date: nil, time: nil, duration: nil,
            venueName: nil, venueAddress: nil, city: nil, stateCountry: nil,
            latitude: nil, longitude: nil, organizer: nil, performerArtist: nil,
            seatInfo: nil, barcodeData: nil, price: nil, confirmationNumber: nil,
            gateInfo: nil, eventDescription: nil, venueType: nil, capacity: nil,
            website: nil, phone: nil, nearbyLandmarks: nil, publicTransport: nil,
            parkingInfo: nil, ageRestriction: nil, dressCode: nil,
            weatherConsiderations: nil, amenities: nil, accessibility: nil,
            aiProcessed: nil, confidenceScore: nil, processingTimestamp: nil,
            modelUsed: nil, enrichmentCompleted: nil, backgroundColor: nil,
            foregroundColor: nil, labelColor: nil
        )
        
        let flightColor = PassColorUtils.fallbackColorFromEventType(flightMetadata)
        XCTAssertNotNil(flightColor, "Should return a color for flight event")
        
        let concertMetadata = EnhancedPassMetadata(
            eventType: "concert",
            eventName: "Test Concert",
            title: nil, description: nil, date: nil, time: nil, duration: nil,
            venueName: nil, venueAddress: nil, city: nil, stateCountry: nil,
            latitude: nil, longitude: nil, organizer: nil, performerArtist: nil,
            seatInfo: nil, barcodeData: nil, price: nil, confirmationNumber: nil,
            gateInfo: nil, eventDescription: nil, venueType: nil, capacity: nil,
            website: nil, phone: nil, nearbyLandmarks: nil, publicTransport: nil,
            parkingInfo: nil, ageRestriction: nil, dressCode: nil,
            weatherConsiderations: nil, amenities: nil, accessibility: nil,
            aiProcessed: nil, confidenceScore: nil, processingTimestamp: nil,
            modelUsed: nil, enrichmentCompleted: nil, backgroundColor: nil,
            foregroundColor: nil, labelColor: nil
        )
        
        let concertColor = PassColorUtils.fallbackColorFromEventType(concertMetadata)
        XCTAssertNotNil(concertColor, "Should return a color for concert event")
        
        let sportsMetadata = EnhancedPassMetadata(
            eventType: "sports",
            eventName: "Test Game",
            title: nil, description: nil, date: nil, time: nil, duration: nil,
            venueName: nil, venueAddress: nil, city: nil, stateCountry: nil,
            latitude: nil, longitude: nil, organizer: nil, performerArtist: nil,
            seatInfo: nil, barcodeData: nil, price: nil, confirmationNumber: nil,
            gateInfo: nil, eventDescription: nil, venueType: "stadium", capacity: nil,
            website: nil, phone: nil, nearbyLandmarks: nil, publicTransport: nil,
            parkingInfo: nil, ageRestriction: nil, dressCode: nil,
            weatherConsiderations: nil, amenities: nil, accessibility: nil,
            aiProcessed: nil, confidenceScore: nil, processingTimestamp: nil,
            modelUsed: nil, enrichmentCompleted: nil, backgroundColor: nil,
            foregroundColor: nil, labelColor: nil
        )
        
        let sportsColor = PassColorUtils.fallbackColorFromEventType(sportsMetadata)
        XCTAssertNotNil(sportsColor, "Should return a color for sports event")
    }
    
    func testFallbackColorFromPassType() {
        let eventColor = PassColorUtils.fallbackColorFromPassType("event")
        XCTAssertNotNil(eventColor, "Should return a color for event pass type")
        
        let concertColor = PassColorUtils.fallbackColorFromPassType("concert")
        XCTAssertNotNil(concertColor, "Should return a color for concert pass type")
        
        let flightColor = PassColorUtils.fallbackColorFromPassType("flight")
        XCTAssertNotNil(flightColor, "Should return a color for flight pass type")
        
        let unknownColor = PassColorUtils.fallbackColorFromPassType("unknown")
        XCTAssertNotNil(unknownColor, "Should return a fallback color for unknown pass type")
    }
    
    // MARK: - Pass Color Extraction Tests
    
    func testGetPassColorWithMetadata() {
        // Test with metadata containing background color
        let metadataWithColor = EnhancedPassMetadata(
            eventType: "concert",
            eventName: "Test Concert",
            title: nil, description: nil, date: nil, time: nil, duration: nil,
            venueName: nil, venueAddress: nil, city: nil, stateCountry: nil,
            latitude: nil, longitude: nil, organizer: nil, performerArtist: nil,
            seatInfo: nil, barcodeData: nil, price: nil, confirmationNumber: nil,
            gateInfo: nil, eventDescription: nil, venueType: nil, capacity: nil,
            website: nil, phone: nil, nearbyLandmarks: nil, publicTransport: nil,
            parkingInfo: nil, ageRestriction: nil, dressCode: nil,
            weatherConsiderations: nil, amenities: nil, accessibility: nil,
            aiProcessed: nil, confidenceScore: nil, processingTimestamp: nil,
            modelUsed: nil, enrichmentCompleted: nil, backgroundColor: "rgb(255,45,85)",
            foregroundColor: nil, labelColor: nil
        )
        
        let color = PassColorUtils.getPassColor(metadata: metadataWithColor)
        XCTAssertNotNil(color, "Should return a color from metadata background color")
        
        // Test with metadata without background color
        let metadataWithoutColor = EnhancedPassMetadata(
            eventType: "sports",
            eventName: "Test Game",
            title: nil, description: nil, date: nil, time: nil, duration: nil,
            venueName: nil, venueAddress: nil, city: nil, stateCountry: nil,
            latitude: nil, longitude: nil, organizer: nil, performerArtist: nil,
            seatInfo: nil, barcodeData: nil, price: nil, confirmationNumber: nil,
            gateInfo: nil, eventDescription: nil, venueType: nil, capacity: nil,
            website: nil, phone: nil, nearbyLandmarks: nil, publicTransport: nil,
            parkingInfo: nil, ageRestriction: nil, dressCode: nil,
            weatherConsiderations: nil, amenities: nil, accessibility: nil,
            aiProcessed: nil, confidenceScore: nil, processingTimestamp: nil,
            modelUsed: nil, enrichmentCompleted: nil, backgroundColor: nil,
            foregroundColor: nil, labelColor: nil
        )
        
        let fallbackColor = PassColorUtils.getPassColor(metadata: metadataWithoutColor)
        XCTAssertNotNil(fallbackColor, "Should return a fallback color when no background color")
        
        // Test with nil metadata
        let nilMetadataColor = PassColorUtils.getPassColor(metadata: nil)
        XCTAssertNotNil(nilMetadataColor, "Should return brand teal for nil metadata")
    }
    
    func testGetPassColorWithPassType() {
        let metadata = TestHelpers.createTestEnhancedPassMetadata()
        let color = PassColorUtils.getPassColor(metadata: metadata, passType: "concert")
        XCTAssertNotNil(color, "Should return a color with pass type fallback")
        
        let nilMetadataColor = PassColorUtils.getPassColor(metadata: nil, passType: "event")
        XCTAssertNotNil(nilMetadataColor, "Should return a color using pass type when metadata is nil")
    }
    
    // MARK: - Color Manipulation Tests
    
    func testDarkenColor() {
        let originalColor = Color.red
        let darkenedColor = PassColorUtils.darkenColor(originalColor, by: 0.3)
        
        XCTAssertNotNil(darkenedColor, "Should return a darkened color")
        // Note: Color comparison is difficult, but we can test it doesn't crash
    }
    
    func testDarkenColorBoundaryValues() {
        let color = Color.blue
        
        // Test 0% darkening (no change)
        let unchanged = PassColorUtils.darkenColor(color, by: 0.0)
        XCTAssertNotNil(unchanged, "Should handle 0% darkening")
        
        // Test 100% darkening (black)
        let black = PassColorUtils.darkenColor(color, by: 1.0)
        XCTAssertNotNil(black, "Should handle 100% darkening")
        
        // Test beyond 100% (should be clamped)
        let overDarkened = PassColorUtils.darkenColor(color, by: 1.5)
        XCTAssertNotNil(overDarkened, "Should handle over-darkening gracefully")
    }
    
    func testGetDarkenedPassColor() {
        let metadata = TestHelpers.createTestEnhancedPassMetadata()
        let darkenedColor = PassColorUtils.getDarkenedPassColor(metadata: metadata)
        XCTAssertNotNil(darkenedColor, "Should return a darkened pass color")
        
        let darkenedWithPassType = PassColorUtils.getDarkenedPassColor(metadata: metadata, passType: "concert")
        XCTAssertNotNil(darkenedWithPassType, "Should return a darkened pass color with pass type")
    }
    
    
    // MARK: - UIImage Extension Tests
    
    func testDominantColorExtraction() {
        // Test with nil image (edge case)
        let nilImage: UIImage? = nil
        let nilColor = nilImage?.dominantColor()
        XCTAssertNil(nilColor, "Should return nil for nil image")
        
        // Test with valid image
        let size = CGSize(width: 50, height: 50)
        let renderer = UIGraphicsImageRenderer(size: size)
        let redImage = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        
        let dominantColor = redImage.dominantColor()
        XCTAssertNotNil(dominantColor, "Should extract dominant color from solid color image")
        
        // Test with multi-color image
        let gradientImage = renderer.image { context in
            let colors = [UIColor.red.cgColor, UIColor.blue.cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 50, y: 50), options: [])
        }
        
        let gradientDominantColor = gradientImage.dominantColor()
        XCTAssertNotNil(gradientDominantColor, "Should extract dominant color from gradient image")
    }
    
    // MARK: - UIColor Extension Tests
    
    func testColorLuminance() {
        let whiteColor = UIColor.white
        let whiteLuminance = whiteColor.luminance
        XCTAssertGreaterThan(whiteLuminance, 0.9, "White should have high luminance")
        
        let blackColor = UIColor.black
        let blackLuminance = blackColor.luminance
        XCTAssertLessThan(blackLuminance, 0.1, "Black should have low luminance")
        
        let grayColor = UIColor.gray
        let grayLuminance = grayColor.luminance
        XCTAssertGreaterThan(grayLuminance, blackLuminance, "Gray should be brighter than black")
        XCTAssertLessThan(grayLuminance, whiteLuminance, "Gray should be darker than white")
    }
    
    func testContrastRatio() {
        let whiteColor = UIColor.white
        let blackColor = UIColor.black
        
        let contrastRatio = whiteColor.contrastRatio(with: blackColor)
        XCTAssertGreaterThan(contrastRatio, 20.0, "White vs black should have high contrast ratio")
        
        let sameColorContrast = whiteColor.contrastRatio(with: whiteColor)
        XCTAssertEqual(sameColorContrast, 1.0, accuracy: 0.01, "Same color should have contrast ratio of 1")
        
        let redColor = UIColor.red
        let blueColor = UIColor.blue
        let colorContrast = redColor.contrastRatio(with: blueColor)
        XCTAssertGreaterThan(colorContrast, 1.0, "Different colors should have contrast > 1")
    }
    
    // MARK: - Performance Tests
    
    func testColorParsingPerformance() {
        let testColors = [
            "rgb(255, 0, 0)",
            "rgb(0, 255, 0)",
            "rgb(0, 0, 255)",
            "rgb(128, 128, 128)",
            "rgb(255, 255, 255)"
        ]
        
        measure {
            for _ in 0..<1000 {
                for colorString in testColors {
                    _ = PassColorUtils.parseRGBColor(colorString)
                }
            }
        }
    }
    
    func testFallbackColorPerformance() {
        let testMetadata = TestHelpers.createTestEnhancedPassMetadata()
        
        measure {
            for _ in 0..<1000 {
                _ = PassColorUtils.fallbackColorFromEventType(testMetadata)
            }
        }
    }
    
    // MARK: - Edge Cases
    
    func testColorUtilsWithCorruptedData() {
        // Test with malformed RGB strings
        let malformedColors = [
            "rgb(255.5, 0, 0)",     // Decimal values
            "rgb(255, 0, 0, extra)", // Extra data
            "rgb(255 0 0)",         // Missing commas
            "rgb[255, 0, 0]",       // Wrong brackets
            "hsl(0, 100%, 50%)"     // Different format
        ]
        
        for colorString in malformedColors {
            let result = PassColorUtils.parseRGBColor(colorString)
            // Main requirement is no crashes
            XCTAssertNil(result, "Should handle malformed color string: \(colorString)")
        }
    }
    
    func testEventTypeColorMappingCoverage() {
        let eventTypes = ["flight", "concert", "sports", "train", "hotel", "movie", "conference", "unknown"]
        
        for eventType in eventTypes {
            let metadata = EnhancedPassMetadata(
                eventType: eventType,
                eventName: nil, title: nil, description: nil, date: nil, time: nil,
                duration: nil, venueName: nil, venueAddress: nil, city: nil,
                stateCountry: nil, latitude: nil, longitude: nil, organizer: nil,
                performerArtist: nil, seatInfo: nil, barcodeData: nil, price: nil,
                confirmationNumber: nil, gateInfo: nil, eventDescription: nil,
                venueType: nil, capacity: nil, website: nil, phone: nil,
                nearbyLandmarks: nil, publicTransport: nil, parkingInfo: nil,
                ageRestriction: nil, dressCode: nil, weatherConsiderations: nil,
                amenities: nil, accessibility: nil, aiProcessed: nil,
                confidenceScore: nil, processingTimestamp: nil, modelUsed: nil,
                enrichmentCompleted: nil, backgroundColor: nil, foregroundColor: nil,
                labelColor: nil
            )
            
            let color = PassColorUtils.fallbackColorFromEventType(metadata)
            XCTAssertNotNil(color, "Should return a color for event type: \(eventType)")
        }
    }
}