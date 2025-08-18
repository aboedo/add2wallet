import SwiftUI
import Foundation

struct PassColorUtils {
    
    // MARK: - Brand Colors (matching app icon teal palette)
    private static let brandTeal = Color(red: 0.125, green: 0.698, blue: 0.667) // #20B2AA
    private static let brandTealSecondary = Color(red: 0.098, green: 0.549, blue: 0.525) // Darker teal
    
    static func parseRGBColor(_ rgbString: String) -> Color? {
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
                    continue
                }
                
                let color = Color(red: r/255.0, green: g/255.0, blue: b/255.0)
                return color
            }
        }
        
        return nil
    }
    
    static func fallbackColorFromEventType(_ metadata: EnhancedPassMetadata) -> Color {
        let eventType = (metadata.eventType ?? "").lowercased()
        let eventName = (metadata.eventName ?? "").lowercased()
        let venueType = (metadata.venueType ?? "").lowercased()
        
        // Match backend's _analyze_pdf_colors_enhanced logic exactly
        if eventType == "flight" || eventName.contains("airline") || venueType.contains("airport") {
            return parseRGBColor("rgb(0,122,255)") ?? .blue // Aviation blue
        } else if eventType == "concert" || eventName.contains("music") || venueType.contains("concert") {
            return parseRGBColor("rgb(255,45,85)") ?? .red // Concert red
        } else if eventType == "sports" || venueType.contains("stadium") {
            return parseRGBColor("rgb(52,199,89)") ?? .green // Sports green
        } else if eventType == "train" || eventName.contains("railway") {
            return parseRGBColor("rgb(48,176,199)") ?? brandTeal // Rail teal (use brand teal)
        } else if eventType == "hotel" || eventName.contains("reservation") {
            return parseRGBColor("rgb(142,142,147)") ?? .gray // Hotel gray
        } else if eventType == "movie" || venueType.contains("theater") {
            return parseRGBColor("rgb(94,92,230)") ?? .purple // Theater purple
        } else if eventType == "conference" || eventName.contains("business") {
            return parseRGBColor("rgb(50,173,230)") ?? brandTeal // Business teal (use brand teal)
        } else {
            // For other types, fall back to original color analysis (using backend fallback logic)
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
            return brandTeal // Default to brand teal instead of gray
        }
    }
    
    static func fallbackColorFromPassType(_ passType: String) -> Color {
        switch passType.lowercased() {
        case let type where type.contains("evt"):
            return parseRGBColor("rgb(255,140,0)") ?? .orange // Event orange
        case let type where type.contains("event"):
            return parseRGBColor("rgb(255,140,0)") ?? .orange // Event orange
        case let type where type.contains("concert"):
            return parseRGBColor("rgb(255,45,85)") ?? .red // Concert red
        case let type where type.contains("flight"):
            return parseRGBColor("rgb(0,122,255)") ?? .blue // Aviation blue
        case let type where type.contains("movie"):
            return parseRGBColor("rgb(94,92,230)") ?? .purple // Theater purple
        case let type where type.contains("sport"):
            return parseRGBColor("rgb(52,199,89)") ?? .green // Sports green
        case let type where type.contains("transit"):
            return parseRGBColor("rgb(48,176,199)") ?? brandTeal // Rail teal (use brand teal)
        default:
            return brandTeal // Default to brand teal instead of gray
        }
    }
    
    static func getPassColor(metadata: EnhancedPassMetadata?) -> Color {
        
        // First try to use actual pass colors from metadata
        if let metadata = metadata {
            
            // Check if we have the actual pass colors
            if let backgroundColor = metadata.backgroundColor {
                if let parsedColor = parseRGBColor(backgroundColor) {
                    return parsedColor
                } else {
                    let fallbackColor = fallbackColorFromEventType(metadata)
                    return fallbackColor
                }
            } else {
                let fallbackColor = fallbackColorFromEventType(metadata)
                return fallbackColor
            }
        }
        
        // Final fallback to brand teal
        return brandTeal
    }
    
    static func getPassColor(metadata: EnhancedPassMetadata?, passType: String) -> Color {
        
        // First try to use actual pass colors from metadata
        if let metadata = metadata {
            
            // Check if we have the actual pass colors
            if let backgroundColor = metadata.backgroundColor {
                if let parsedColor = parseRGBColor(backgroundColor) {
                    return parsedColor
                } else {
                    let fallbackColor = fallbackColorFromEventType(metadata)
                    return fallbackColor
                }
            } else {
                let fallbackColor = fallbackColorFromEventType(metadata)
                return fallbackColor
            }
        }
        
        // Final fallback to basic pass type
        let fallbackColor = fallbackColorFromPassType(passType)
        return fallbackColor
    }
    
    
    /// Darkens a color by the specified percentage (0.0 to 1.0)
    static func darkenColor(_ color: Color, by percentage: Double) -> Color {
        let uiColor = UIColor(color)
        
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        let factor = CGFloat(1.0 - percentage)
        let darkenedRed = red * factor
        let darkenedGreen = green * factor
        let darkenedBlue = blue * factor
        
        return Color(red: darkenedRed, green: darkenedGreen, blue: darkenedBlue, opacity: alpha)
    }
    
    /// Gets a darkened version of the pass color for better contrast in backgrounds
    /// Always darkens by at least 30% to ensure proper contrast
    static func getDarkenedPassColor(metadata: EnhancedPassMetadata?) -> Color {
        let originalColor = getPassColor(metadata: metadata)
        // Always darken by at least 30% for contrast
        return darkenColor(originalColor, by: max(0.3, 0.3))
    }
    
    /// Gets a darkened version of the pass color for better contrast in backgrounds
    /// Always darkens by at least 30% to ensure proper contrast
    static func getDarkenedPassColor(metadata: EnhancedPassMetadata?, passType: String) -> Color {
        let originalColor = getPassColor(metadata: metadata, passType: passType)
        // Always darken by at least 30% for contrast
        return darkenColor(originalColor, by: max(0.3, 0.3))
    }
}

// MARK: - UIImage Extension for Dominant Color Extraction
extension UIImage {
    /// Extracts the dominant color from an image using k-means clustering approach
    func dominantColor() -> Color? {
        guard let cgImage = self.cgImage else { return nil }
        
        // Resize image for faster processing
        let size = CGSize(width: 50, height: 50)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                               bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        context?.interpolationQuality = .high
        context?.draw(cgImage, in: CGRect(origin: .zero, size: size))
        
        guard let data = context?.data else { return nil }
        
        let buffer = data.bindMemory(to: UInt8.self, capacity: Int(size.width * size.height * 4))
        
        var colorFrequency: [UIColor: Int] = [:]
        
        // Sample colors and count frequency
        for y in stride(from: 0, to: Int(size.height), by: 2) {
            for x in stride(from: 0, to: Int(size.width), by: 2) {
                let pixelIndex = (y * Int(size.width) + x) * 4
                
                let red = CGFloat(buffer[pixelIndex]) / 255.0
                let green = CGFloat(buffer[pixelIndex + 1]) / 255.0
                let blue = CGFloat(buffer[pixelIndex + 2]) / 255.0
                let alpha = CGFloat(buffer[pixelIndex + 3]) / 255.0
                
                // Skip very transparent or very light/dark pixels
                if alpha < 0.5 || (red + green + blue) / 3 < 0.1 || (red + green + blue) / 3 > 0.9 {
                    continue
                }
                
                let color = UIColor(red: red, green: green, blue: blue, alpha: alpha)
                colorFrequency[color, default: 0] += 1
            }
        }
        
        // Find the most frequent color
        guard let dominantUIColor = colorFrequency.max(by: { $0.value < $1.value })?.key else {
            return nil
        }
        
        return Color(dominantUIColor)
    }
}

// MARK: - UIColor Extension for Contrast Calculation
extension UIColor {
    /// Calculates the relative luminance of a color
    var luminance: CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        
        getRed(&red, green: &green, blue: &blue, alpha: nil)
        
        // Apply gamma correction
        func adjust(component: CGFloat) -> CGFloat {
            return component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        
        let r = adjust(component: red)
        let g = adjust(component: green)
        let b = adjust(component: blue)
        
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
    
    /// Calculates the contrast ratio between two colors
    func contrastRatio(with color: UIColor) -> CGFloat {
        let luminance1 = self.luminance
        let luminance2 = color.luminance
        
        let lightest = max(luminance1, luminance2)
        let darkest = min(luminance1, luminance2)
        
        return (lightest + 0.05) / (darkest + 0.05)
    }
}