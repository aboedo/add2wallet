import SwiftUI
import Foundation

struct PassColorUtils {
    
    static func parseRGBColor(_ rgbString: String) -> Color? {
        // Parse rgb(r,g,b) format
        let pattern = #"rgb\((\d+),\s*(\d+),\s*(\d+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: rgbString, range: NSRange(rgbString.startIndex..., in: rgbString)) else {
            return nil
        }
        
        let rRange = Range(match.range(at: 1), in: rgbString)!
        let gRange = Range(match.range(at: 2), in: rgbString)!
        let bRange = Range(match.range(at: 3), in: rgbString)!
        
        guard let r = Double(String(rgbString[rRange])),
              let g = Double(String(rgbString[gRange])),
              let b = Double(String(rgbString[bRange])) else {
            return nil
        }
        
        return Color(red: r/255.0, green: g/255.0, blue: b/255.0)
    }
    
    static func fallbackColorFromEventType(_ metadata: EnhancedPassMetadata) -> Color {
        let eventType = (metadata.eventType ?? "").lowercased()
        
        switch eventType {
        case let type where type.contains("museum"):
            return .brown
        case let type where type.contains("concert") || type.contains("music"):
            return .purple
        case let type where type.contains("event") || type.contains("festival"):
            return .orange
        case let type where type.contains("flight") || type.contains("airline"):
            return .blue
        case let type where type.contains("movie") || type.contains("cinema"):
            return .red
        case let type where type.contains("sport") || type.contains("game"):
            return .green
        case let type where type.contains("transit") || type.contains("train") || type.contains("bus"):
            return .cyan
        case let type where type.contains("theatre") || type.contains("theater"):
            return .indigo
        default:
            return .blue
        }
    }
    
    static func fallbackColorFromPassType(_ passType: String) -> Color {
        switch passType.lowercased() {
        case let type where type.contains("evt"):
            return .orange
        case let type where type.contains("event"):
            return .orange
        case let type where type.contains("concert"):
            return .purple
        case let type where type.contains("flight"):
            return .blue
        case let type where type.contains("movie"):
            return .red
        case let type where type.contains("sport"):
            return .green
        case let type where type.contains("transit"):
            return .cyan
        default:
            return .gray
        }
    }
    
    static func getPassColor(metadata: EnhancedPassMetadata?) -> Color {
        // First try to use actual pass colors from metadata
        if let metadata = metadata {
            // Check if we have the actual pass colors
            if let backgroundColor = metadata.backgroundColor {
                return parseRGBColor(backgroundColor) ?? fallbackColorFromEventType(metadata)
            }
            return fallbackColorFromEventType(metadata)
        }
        
        // Final fallback to a default color
        return .blue
    }
    
    static func getPassColor(metadata: EnhancedPassMetadata?, passType: String) -> Color {
        // First try to use actual pass colors from metadata
        if let metadata = metadata {
            // Check if we have the actual pass colors
            if let backgroundColor = metadata.backgroundColor {
                return parseRGBColor(backgroundColor) ?? fallbackColorFromEventType(metadata)
            }
            return fallbackColorFromEventType(metadata)
        }
        
        // Final fallback to basic pass type
        return fallbackColorFromPassType(passType)
    }
}