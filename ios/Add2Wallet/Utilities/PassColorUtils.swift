import SwiftUI
import Foundation

struct PassColorUtils {
    
    static func parseRGBColor(_ rgbString: String) -> Color? {
        print("🎨 [PassColorUtils] Attempting to parse RGB color: '\(rgbString)'")
        
        // Clean and normalize the input string
        let cleanString = rgbString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try multiple RGB format patterns
        let patterns = [
            #"rgb\((\d+),\s*(\d+),\s*(\d+)\)"#,           // rgb(255, 255, 255)
            #"rgb\((\d+)\s*,\s*(\d+)\s*,\s*(\d+)\)"#,     // rgb(255,255,255) - more flexible spacing
            #"RGB\((\d+),\s*(\d+),\s*(\d+)\)"#,           // RGB(255, 255, 255) - uppercase
            #"rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)"# // rgb( 255 , 255 , 255 ) - extra spaces
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: cleanString, range: NSRange(cleanString.startIndex..., in: cleanString)) {
                
                let rRange = Range(match.range(at: 1), in: cleanString)!
                let gRange = Range(match.range(at: 2), in: cleanString)!
                let bRange = Range(match.range(at: 3), in: cleanString)!
                
                let rString = String(cleanString[rRange])
                let gString = String(cleanString[gRange])
                let bString = String(cleanString[bRange])
                
                guard let r = Double(rString),
                      let g = Double(gString),
                      let b = Double(bString),
                      r >= 0, r <= 255,
                      g >= 0, g <= 255,
                      b >= 0, b <= 255 else {
                    print("🚨 [PassColorUtils] RGB values out of range (0-255): r=\(rString), g=\(gString), b=\(bString)")
                    continue
                }
                
                let color = Color(red: r/255.0, green: g/255.0, blue: b/255.0)
                print("✅ [PassColorUtils] Successfully parsed RGB color: r=\(r), g=\(g), b=\(b) using pattern: \(pattern)")
                return color
            }
        }
        
        print("🚨 [PassColorUtils] Failed to parse RGB color - no pattern matched: '\(cleanString)'")
        return nil
    }
    
    static func fallbackColorFromEventType(_ metadata: EnhancedPassMetadata) -> Color {
        let eventType = (metadata.eventType ?? "").lowercased()
        let eventName = (metadata.eventName ?? "").lowercased()
        let venueType = (metadata.venueType ?? "").lowercased()
        
        print("🔄 [PassColorUtils] Determining fallback color for eventType: '\(eventType)', eventName: '\(eventName)', venueType: '\(venueType)'")
        
        // Match backend's _analyze_pdf_colors_enhanced logic exactly
        if eventType == "flight" || eventName.contains("airline") || venueType.contains("airport") {
            let color = parseRGBColor("rgb(0,122,255)") ?? .blue // Aviation blue
            print("✈️ [PassColorUtils] Using flight/aviation blue color")
            return color
        } else if eventType == "concert" || eventName.contains("music") || venueType.contains("concert") {
            let color = parseRGBColor("rgb(255,45,85)") ?? .red // Concert red
            print("🎵 [PassColorUtils] Using concert red color")
            return color
        } else if eventType == "sports" || venueType.contains("stadium") {
            let color = parseRGBColor("rgb(52,199,89)") ?? .green // Sports green
            print("⚽ [PassColorUtils] Using sports green color")
            return color
        } else if eventType == "train" || eventName.contains("railway") {
            let color = parseRGBColor("rgb(48,176,199)") ?? .cyan // Rail teal
            print("🚂 [PassColorUtils] Using train teal color")
            return color
        } else if eventType == "hotel" || eventName.contains("reservation") {
            let color = parseRGBColor("rgb(142,142,147)") ?? .gray // Hotel gray
            print("🏨 [PassColorUtils] Using hotel gray color")
            return color
        } else if eventType == "movie" || venueType.contains("theater") {
            let color = parseRGBColor("rgb(94,92,230)") ?? .purple // Theater purple
            print("🎬 [PassColorUtils] Using movie/theater purple color")
            return color
        } else if eventType == "conference" || eventName.contains("business") {
            let color = parseRGBColor("rgb(50,173,230)") ?? .blue // Business blue
            print("💼 [PassColorUtils] Using conference/business blue color")
            return color
        } else {
            // For other types, fall back to original color analysis (using backend fallback logic)
            print("❓ [PassColorUtils] Using default analysis for unmatched type")
            return fallbackColorFromContentAnalysis(eventType: eventType, eventName: eventName)
        }
    }
    
    private static func fallbackColorFromContentAnalysis(eventType: String, eventName: String) -> Color {
        // This mirrors the backend's _analyze_pdf_colors method logic
        if eventName.contains("concert") || eventName.contains("music") {
            return parseRGBColor("rgb(138,43,226)") ?? .purple // Concert purple
        } else if eventName.contains("sport") || eventName.contains("game") {
            return parseRGBColor("rgb(34,139,34)") ?? .green // Sports green
        } else if eventName.contains("movie") || eventName.contains("cinema") {
            return parseRGBColor("rgb(220,20,60)") ?? .red // Movie red
        } else if eventName.contains("event") || eventName.contains("festival") {
            return parseRGBColor("rgb(255,140,0)") ?? .orange // Event orange
        } else if eventName.contains("flight") || eventName.contains("airline") {
            return parseRGBColor("rgb(30,144,255)") ?? .blue // Flight blue
        } else {
            return parseRGBColor("rgb(60,60,67)") ?? .gray // Default gray
        }
    }
    
    static func fallbackColorFromPassType(_ passType: String) -> Color {
        print("🔄 [PassColorUtils] Determining fallback color for passType: '\(passType)'")
        
        switch passType.lowercased() {
        case let type where type.contains("evt"):
            let color = parseRGBColor("rgb(255,140,0)") ?? .orange // Event orange
            print("📅 [PassColorUtils] Using event orange color for passType")
            return color
        case let type where type.contains("event"):
            let color = parseRGBColor("rgb(255,140,0)") ?? .orange // Event orange
            print("📅 [PassColorUtils] Using event orange color for passType")
            return color
        case let type where type.contains("concert"):
            let color = parseRGBColor("rgb(255,45,85)") ?? .red // Concert red
            print("🎵 [PassColorUtils] Using concert red color for passType")
            return color
        case let type where type.contains("flight"):
            let color = parseRGBColor("rgb(0,122,255)") ?? .blue // Aviation blue
            print("✈️ [PassColorUtils] Using flight blue color for passType")
            return color
        case let type where type.contains("movie"):
            let color = parseRGBColor("rgb(94,92,230)") ?? .purple // Theater purple
            print("🎬 [PassColorUtils] Using movie purple color for passType")
            return color
        case let type where type.contains("sport"):
            let color = parseRGBColor("rgb(52,199,89)") ?? .green // Sports green
            print("⚽ [PassColorUtils] Using sports green color for passType")
            return color
        case let type where type.contains("transit"):
            let color = parseRGBColor("rgb(48,176,199)") ?? .cyan // Rail teal
            print("🚂 [PassColorUtils] Using transit teal color for passType")
            return color
        default:
            let color = parseRGBColor("rgb(142,142,147)") ?? .gray // Default gray
            print("❓ [PassColorUtils] Using default gray color for passType")
            return color
        }
    }
    
    static func getPassColor(metadata: EnhancedPassMetadata?) -> Color {
        print("🎨 [PassColorUtils] Getting pass color for metadata")
        
        // First try to use actual pass colors from metadata
        if let metadata = metadata {
            print("🔍 [PassColorUtils] Metadata available - eventType: \(metadata.eventType ?? "nil"), backgroundColor: \(metadata.backgroundColor ?? "nil")")
            
            // Check if we have the actual pass colors
            if let backgroundColor = metadata.backgroundColor {
                print("🎯 [PassColorUtils] Found backgroundColor in metadata: '\(backgroundColor)'")
                if let parsedColor = parseRGBColor(backgroundColor) {
                    print("✅ [PassColorUtils] Using parsed background color from metadata")
                    return parsedColor
                } else {
                    print("⚠️ [PassColorUtils] Failed to parse backgroundColor, falling back to event type color")
                    let fallbackColor = fallbackColorFromEventType(metadata)
                    print("🔄 [PassColorUtils] Using event type fallback color for eventType: \(metadata.eventType ?? "unknown")")
                    return fallbackColor
                }
            } else {
                print("⚠️ [PassColorUtils] No backgroundColor in metadata, using event type fallback")
                let fallbackColor = fallbackColorFromEventType(metadata)
                print("🔄 [PassColorUtils] Using event type fallback color for eventType: \(metadata.eventType ?? "unknown")")
                return fallbackColor
            }
        }
        
        print("⚠️ [PassColorUtils] No metadata available, using default blue color")
        // Final fallback to a default color
        return .blue
    }
    
    static func getPassColor(metadata: EnhancedPassMetadata?, passType: String) -> Color {
        print("🎨 [PassColorUtils] Getting pass color for metadata with passType: '\(passType)'")
        
        // First try to use actual pass colors from metadata
        if let metadata = metadata {
            print("🔍 [PassColorUtils] Metadata available - eventType: \(metadata.eventType ?? "nil"), backgroundColor: \(metadata.backgroundColor ?? "nil")")
            
            // Check if we have the actual pass colors
            if let backgroundColor = metadata.backgroundColor {
                print("🎯 [PassColorUtils] Found backgroundColor in metadata: '\(backgroundColor)'")
                if let parsedColor = parseRGBColor(backgroundColor) {
                    print("✅ [PassColorUtils] Using parsed background color from metadata")
                    return parsedColor
                } else {
                    print("⚠️ [PassColorUtils] Failed to parse backgroundColor, falling back to event type color")
                    let fallbackColor = fallbackColorFromEventType(metadata)
                    print("🔄 [PassColorUtils] Using event type fallback color for eventType: \(metadata.eventType ?? "unknown")")
                    return fallbackColor
                }
            } else {
                print("⚠️ [PassColorUtils] No backgroundColor in metadata, using event type fallback")
                let fallbackColor = fallbackColorFromEventType(metadata)
                print("🔄 [PassColorUtils] Using event type fallback color for eventType: \(metadata.eventType ?? "unknown")")
                return fallbackColor
            }
        }
        
        print("⚠️ [PassColorUtils] No metadata available, using passType fallback: '\(passType)'")
        // Final fallback to basic pass type
        let fallbackColor = fallbackColorFromPassType(passType)
        print("🔄 [PassColorUtils] Using passType fallback color for passType: '\(passType)'")
        return fallbackColor
    }
}