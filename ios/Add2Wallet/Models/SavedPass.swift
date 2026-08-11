import Foundation
import SwiftData
import UniformTypeIdentifiers

@Model
class SavedPass {
    var id: String = UUID().uuidString
    var createdAt: Date = Date()
    var passType: String = ""
    var title: String = ""
    var eventDate: String?
    var venue: String?
    var city: String?
    var passDatas: [Data] = []
    var passURL: String?

    // Legacy property name retained for a lightweight SwiftData migration.
    // It stores the original PDF or image bytes.
    var pdfData: Data?
    var sourceFilename: String?
    var sourceContentTypeIdentifier: String?

    // Store the full metadata as JSON for complete preservation
    var metadataJSON: Data?

    // Trip identity, denormalised out of the metadata blob so passes can be
    // grouped without decoding every record. Optional with a default, so
    // SwiftData migrates existing stores automatically — passes imported
    // before this shipped simply have no trip and stay standalone.
    var groupId: String?
    var groupName: String?

    /// Trip assigned by the user rather than by the booking reference. Takes
    /// precedence over `groupId` so "Move to trip…" can override the backend.
    var manualTripId: String?

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
        sourceFilename: String? = nil,
        sourceContentTypeIdentifier: String? = nil,
        metadata: EnhancedPassMetadata? = nil,
        manualTripId: String? = nil
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
        self.sourceFilename = sourceFilename
        self.sourceContentTypeIdentifier = sourceContentTypeIdentifier

        self.manualTripId = manualTripId

        if let metadata = metadata {
            self.metadataJSON = try? JSONEncoder().encode(metadata)
            self.groupId = metadata.groupId
            self.groupName = metadata.groupName
        }
    }

    /// The trip this pass belongs to, or nil when it stands alone.
    /// A user's manual assignment beats the booking reference.
    var tripId: String? {
        if let manualTripId, !manualTripId.isEmpty { return manualTripId }
        guard let groupId, !groupId.isEmpty else { return nil }
        return groupId
    }

    /// Legs of a multi-part booking. A pass split out of an itinerary carries
    /// its own single leg; an unsplit booking carries the whole list.
    var segments: [PassSegment] {
        guard let metadata else { return [] }
        if let segment = metadata.segment { return [segment] }
        return metadata.segments ?? []
    }

    /// "Málaga → Madrid" when this pass represents a journey.
    var routeDescription: String? {
        if let route = metadata?.route, !route.isEmpty { return route }
        return segments.first?.routeDescription
    }
    
    var sourceData: Data? { pdfData }

    var effectiveSourceFilename: String {
        sourceFilename ?? "\(id).pdf"
    }

    var sourceMIMEType: String {
        SupportedFile.mimeType(
            forContentTypeIdentifier: sourceContentTypeIdentifier,
            filename: effectiveSourceFilename
        )
    }

    /// Decoded once per pass. `metadataJSON` is written at init and never
    /// mutated, and the timeline asks for this dozens of times per pass while
    /// grouping — a full decode of a fifty-field blob each time.
    private static let decodedMetadata = NSCache<NSString, MetadataBox>()

    private final class MetadataBox {
        let value: EnhancedPassMetadata
        init(_ value: EnhancedPassMetadata) { self.value = value }
    }

    // Computed property to retrieve the full metadata
    var metadata: EnhancedPassMetadata? {
        guard let metadataJSON = metadataJSON else { return nil }

        let key = id as NSString
        if let cached = SavedPass.decodedMetadata.object(forKey: key) {
            return cached.value
        }
        guard let decoded = try? JSONDecoder().decode(EnhancedPassMetadata.self, from: metadataJSON) else {
            return nil
        }
        SavedPass.decodedMetadata.setObject(MetadataBox(decoded), forKey: key)
        return decoded
    }
    
    // Convenience computed properties for display
    var displayTitle: String {
        let baseTitle = title.isEmpty ? (passType.isEmpty ? "Pass" : passType) : title
        return cleanTicketSuffix(from: baseTitle)
    }
    
    /// What to call this record when it stands for several passes at once.
    ///
    /// A multi-ticket import stores the *first* ticket's title — "Coldplay #1",
    /// or the opening leg of an itinerary — so using it for the set names the
    /// whole after one of its parts. The backend sends a name for the booking
    /// as a whole; that is the only one that can be right. Single passes are
    /// untouched: there `groupName` is the trip's name, not this pass's.
    var displayGroupTitle: String {
        guard passCount > 1,
              let name = groupName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return displayTitle }
        return name
    }

    // Helper function to remove "Ticket" suffix from titles
    private func cleanTicketSuffix(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if title ends with "Ticket" (case-insensitive)
        if trimmed.lowercased().hasSuffix("ticket") {
            let endIndex = trimmed.index(trimmed.endIndex, offsetBy: -6) // "ticket" has 6 characters
            let withoutTicket = String(trimmed[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            return withoutTicket.isEmpty ? trimmed : withoutTicket
        }
        
        return trimmed
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
    
    /// Whether the event date has passed (expired)
    var isExpired: Bool {
        guard let eventDateString = eventDate, !eventDateString.isEmpty else {
            // No date → never expires
            return false
        }
        // eventDateOrFallback already parses multiple formats
        let eventDay = eventDateOrFallback
        // If it fell back to createdAt and there's no real event date, don't expire
        if eventDay == createdAt { return false }
        // Expired = event date is before start of today
        return Calendar.current.startOfDay(for: eventDay) < Calendar.current.startOfDay(for: Date())
    }
    
    /// Built once. Creating a `DateFormatter` is expensive, and this list was
    /// being rebuilt — seventeen of them — on *every* call.
    private static let eventDateFormatters: [DateFormatter] = [
        "MMM d, yyyy 'at' h:mm a",
        "MMM d, yyyy h:mm a",
        "MMMM d, yyyy 'at' h:mm a",
        "MMMM d, yyyy h:mm a",
        "M/d/yy, h:mm a",
        "M/d/yyyy, h:mm a",
        "d/M/yy, h:mm a",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
        "MMM d, yyyy",
        "MMMM d, yyyy",
        "MM/dd/yyyy",
        "dd/MM/yyyy",
        "yyyy-MM-dd",
        "d MMMM yyyy",
        "MMM d",
        "MMMM d"
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    /// Parsing the same handful of strings over and over is the hot path: the
    /// timeline sorts, groups and filters, and every comparison asks for this.
    private static let parsedDates = NSCache<NSString, NSDate>()

    /// Parse event date string or fallback to creation date for sorting/grouping.
    var eventDateOrFallback: Date {
        guard let eventDateString = eventDate, !eventDateString.isEmpty else {
            return createdAt
        }

        let key = eventDateString as NSString
        if let cached = SavedPass.parsedDates.object(forKey: key) {
            return cached as Date
        }

        for formatter in SavedPass.eventDateFormatters {
            if let parsed = formatter.date(from: eventDateString) {
                SavedPass.parsedDates.setObject(parsed as NSDate, forKey: key)
                return parsed
            }
        }

        return createdAt
    }
}
