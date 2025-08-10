import Foundation
import SwiftData

@Model
class SavedPass {
    var id: String
    var createdAt: Date
    var passType: String
    var title: String
    var eventDate: String?
    var venue: String?
    var city: String?
    var passDatas: [Data]
    var passURL: String?
    var pdfData: Data?
    
    // Store the full metadata as JSON for complete preservation
    var metadataJSON: Data?
    
    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        passType: String,
        title: String,
        eventDate: String? = nil,
        venue: String? = nil,
        city: String? = nil,
        passDatas: [Data] = [],
        passURL: String? = nil,
        pdfData: Data? = nil,
        metadata: EnhancedPassMetadata? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.passType = passType
        self.title = title
        self.eventDate = eventDate
        self.venue = venue
        self.city = city
        self.passDatas = passDatas
        self.passURL = passURL
        self.pdfData = pdfData
        
        if let metadata = metadata {
            self.metadataJSON = try? JSONEncoder().encode(metadata)
        }
    }
    
    // Computed property to retrieve the full metadata
    var metadata: EnhancedPassMetadata? {
        guard let metadataJSON = metadataJSON else { return nil }
        return try? JSONDecoder().decode(EnhancedPassMetadata.self, from: metadataJSON)
    }
    
    // Convenience computed properties for display
    var displayTitle: String {
        return title.isEmpty ? (passType.isEmpty ? "Pass" : passType) : title
    }
    
    var displaySubtitle: String {
        var components: [String] = []
        
        if let eventDate = eventDate, !eventDate.isEmpty {
            components.append(eventDate)
        }
        
        if let venue = venue, !venue.isEmpty {
            components.append(venue)
        } else if let city = city, !city.isEmpty {
            components.append(city)
        }
        
        return components.joined(separator: " • ")
    }
    
    // Venue-only subtitle for cleaner display in lists
    var displayVenue: String {
        if let venue = venue, !venue.isEmpty {
            return venue
        } else if let city = city, !city.isEmpty {
            return city
        }
        return ""
    }
    
    var formattedCreatedAt: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
    
    var passCount: Int {
        return passDatas.count
    }
    
    // Parse event date string or fallback to creation date for sorting/grouping
    var eventDateOrFallback: Date {
        if let eventDateString = eventDate, !eventDateString.isEmpty {
            // Try common date formats
            let formatters = [
                "MMM d, yyyy",    // "Dec 15, 2024"
                "MMMM d, yyyy",   // "December 15, 2024"
                "MM/dd/yyyy",     // "12/15/2024"
                "dd/MM/yyyy",     // "15/12/2024"
                "yyyy-MM-dd",     // "2024-12-15"
                "d MMMM yyyy",    // "15 December 2024"
                "MMM d",          // "Dec 15" (current year assumed)
                "MMMM d"          // "December 15" (current year assumed)
            ]
            
            for formatString in formatters {
                let formatter = DateFormatter()
                formatter.dateFormat = formatString
                if let parsedDate = formatter.date(from: eventDateString) {
                    return parsedDate
                }
            }
        }
        
        // Fallback to creation date
        return createdAt
    }
}