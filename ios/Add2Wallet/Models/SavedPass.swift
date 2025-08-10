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
    var passData: Data?
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
        passData: Data? = nil,
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
        self.passData = passData
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
    
    var formattedCreatedAt: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}