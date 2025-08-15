import SwiftUI
import Foundation

struct PassColorUtils {
    
    // MARK: - Brand Colors (matching app icon teal palette)
    private static let brandTeal = Color(red: 0.125, green: 0.698, blue: 0.667) // #20B2AA
    private static let brandTealSecondary = Color(red: 0.098, green: 0.549, blue: 0.525) // Darker teal
    
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
            let color = parseRGBColor("rgb(48,176,199)") ?? brandTeal // Rail teal (use brand teal)
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
            let color = parseRGBColor("rgb(50,173,230)") ?? brandTeal // Business teal (use brand teal)
            print("💼 [PassColorUtils] Using conference/business teal color")
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
            return brandTeal // Default to brand teal instead of gray
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
            let color = parseRGBColor("rgb(48,176,199)") ?? brandTeal // Rail teal (use brand teal)
            print("🚂 [PassColorUtils] Using transit teal color for passType")
            return color
        default:
            print("❓ [PassColorUtils] Using brand teal color for passType")
            return brandTeal // Default to brand teal instead of gray
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
        
        print("⚠️ [PassColorUtils] No metadata available, using default brand teal color")
        // Final fallback to brand teal
        return brandTeal
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
    
    // MARK: - Dynamic Pass Accent Color Extraction
    
    /// Extracts a dynamic accent color from a pass image with proper contrast validation
    /// Falls back to brand teal if extraction fails or contrast is insufficient
    static func extractPassAccentColor(from image: UIImage?) -> Color {
        guard let image = image else {
            print("🎨 [PassColorUtils] No image provided, using brand teal")
            return brandTeal
        }
        
        guard let dominantColor = image.dominantColor() else {
            print("🎨 [PassColorUtils] Failed to extract dominant color, using brand teal")
            return brandTeal
        }
        
        // Ensure minimum contrast ratio of 4.5:1 against both light and dark backgrounds
        let adjustedColor = ensureContrast(color: dominantColor, minRatio: 4.5)
        
        print("🎨 [PassColorUtils] Successfully extracted and adjusted pass accent color")
        return adjustedColor
    }
    
    /// Ensures a color meets minimum contrast requirements
    /// If it doesn't, blends it with brand teal at 70% mix
    private static func ensureContrast(color: Color, minRatio: Double) -> Color {
        // Convert Color to UIColor for luminance calculation
        let uiColor = UIColor(color)
        
        // Calculate contrast ratios against white and black
        let contrastWhite = uiColor.contrastRatio(with: .white)
        let contrastBlack = uiColor.contrastRatio(with: .black)
        
        // Check if either contrast ratio meets the minimum
        if contrastWhite >= minRatio || contrastBlack >= minRatio {
            return color
        }
        
        // If contrast is insufficient, mix with brand teal (70% brand, 30% original)
        print("🎨 [PassColorUtils] Color contrast insufficient, blending with brand teal")
        return blendColors(brandTeal, color, ratio: 0.7)
    }
    
    /// Blends two colors with the specified ratio
    private static func blendColors(_ color1: Color, _ color2: Color, ratio: Double) -> Color {
        let ui1 = UIColor(color1)
        let ui2 = UIColor(color2)
        
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        
        ui1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        ui2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        
        let blendedR = r1 * ratio + r2 * (1 - ratio)
        let blendedG = g1 * ratio + g2 * (1 - ratio)
        let blendedB = b1 * ratio + b2 * (1 - ratio)
        let blendedA = a1 * ratio + a2 * (1 - ratio)
        
        return Color(red: blendedR, green: blendedG, blue: blendedB, opacity: blendedA)
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
    static func getDarkenedPassColor(metadata: EnhancedPassMetadata?) -> Color {
        let originalColor = getPassColor(metadata: metadata)
        return darkenColor(originalColor, by: 0.3) // 30% darker
    }
    
    /// Gets a darkened version of the pass color for better contrast in backgrounds
    static func getDarkenedPassColor(metadata: EnhancedPassMetadata?, passType: String) -> Color {
        let originalColor = getPassColor(metadata: metadata, passType: passType)
        return darkenColor(originalColor, by: 0.3) // 30% darker
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