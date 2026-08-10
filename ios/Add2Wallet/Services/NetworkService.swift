import Foundation
import Combine
import RevenueCat

struct EnhancedPassMetadata: Codable {
    // Basic Information
    let eventType: String?
    let eventName: String?
    let title: String?
    let description: String?

    // Date and Time
    let date: String?
    let time: String?
    let duration: String?

    // Location Information
    let venueName: String?
    let venueAddress: String?
    let city: String?
    let stateCountry: String?
    let latitude: Double?
    let longitude: Double?

    // Event Details
    let organizer: String?
    let performerArtist: String?
    let seatInfo: String?
    let barcodeData: String?
    let price: String?
    let confirmationNumber: String?
    let gateInfo: String?

    // Enriched Information
    let eventDescription: String?
    let venueType: String?
    let capacity: String?
    let website: String?
    let phone: String?
    let nearbyLandmarks: [String]?
    let publicTransport: String?
    let parkingInfo: String?

    // Additional Details
    let ageRestriction: String?
    let dressCode: String?
    let weatherConsiderations: String?
    let amenities: [String]?
    let accessibility: String?

    // Processing Information
    let aiProcessed: Bool?
    let confidenceScore: Int?
    let processingTimestamp: String?
    let modelUsed: String?
    let enrichmentCompleted: Bool?
    
    // Pass Colors
    let backgroundColor: String?
    let foregroundColor: String?
    let labelColor: String?
    
    // iOS 26 Features
    let multipleEvents: Bool?
    let upcomingEvents: [UpcomingEvent]?
    let venuePlaceId: String?
    let performerNames: [String]?
    let exhibitName: String?
    let hasAssignedSeating: Bool?
    let eventUrls: EventURLs?

    // Trip identity and per-leg detail. A five-leg booking arrives as five
    // passes sharing one groupId, each carrying its own segment.
    let groupId: String?
    let groupName: String?
    let route: String?
    let segment: PassSegment?
    let segments: [PassSegment]?

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case eventName = "event_name"
        case title
        case description
        case date
        case time
        case duration
        case venueName = "venue_name"
        case venueAddress = "venue_address"
        case city
        case stateCountry = "state_country"
        case latitude
        case longitude
        case organizer
        case performerArtist = "performer_artist"
        case seatInfo = "seat_info"
        case barcodeData = "barcode_data"
        case price
        case confirmationNumber = "confirmation_number"
        case gateInfo = "gate_info"
        case eventDescription = "event_description"
        case venueType = "venue_type"
        case capacity
        case website
        case phone
        case nearbyLandmarks = "nearby_landmarks"
        case publicTransport = "public_transport"
        case parkingInfo = "parking_info"
        case ageRestriction = "age_restriction"
        case dressCode = "dress_code"
        case weatherConsiderations = "weather_considerations"
        case amenities
        case accessibility
        case aiProcessed = "ai_processed"
        case confidenceScore = "confidence_score"
        case processingTimestamp = "processing_timestamp"
        case modelUsed = "model_used"
        case enrichmentCompleted = "enrichment_completed"
        case backgroundColor = "background_color"
        case foregroundColor = "foreground_color"
        case labelColor = "label_color"
        case multipleEvents = "multiple_events"
        case upcomingEvents = "upcoming_events"
        case venuePlaceId = "venue_place_id"
        case performerNames = "performer_names"
        case exhibitName = "exhibit_name"
        case hasAssignedSeating = "has_assigned_seating"
        case eventUrls = "event_urls"
        case groupId = "group_id"
        case groupName = "group_name"
        case route
        case segment
        case segments
    }

    init(
        eventType: String? = nil,
        eventName: String? = nil,
        title: String? = nil,
        description: String? = nil,
        date: String? = nil,
        time: String? = nil,
        duration: String? = nil,
        venueName: String? = nil,
        venueAddress: String? = nil,
        city: String? = nil,
        stateCountry: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        organizer: String? = nil,
        performerArtist: String? = nil,
        seatInfo: String? = nil,
        barcodeData: String? = nil,
        price: String? = nil,
        confirmationNumber: String? = nil,
        gateInfo: String? = nil,
        eventDescription: String? = nil,
        venueType: String? = nil,
        capacity: String? = nil,
        website: String? = nil,
        phone: String? = nil,
        nearbyLandmarks: [String]? = nil,
        publicTransport: String? = nil,
        parkingInfo: String? = nil,
        ageRestriction: String? = nil,
        dressCode: String? = nil,
        weatherConsiderations: String? = nil,
        amenities: [String]? = nil,
        accessibility: String? = nil,
        aiProcessed: Bool? = nil,
        confidenceScore: Int? = nil,
        processingTimestamp: String? = nil,
        modelUsed: String? = nil,
        enrichmentCompleted: Bool? = nil,
        backgroundColor: String? = nil,
        foregroundColor: String? = nil,
        labelColor: String? = nil,
        multipleEvents: Bool? = nil,
        upcomingEvents: [UpcomingEvent]? = nil,
        venuePlaceId: String? = nil,
        performerNames: [String]? = nil,
        exhibitName: String? = nil,
        hasAssignedSeating: Bool? = nil,
        eventUrls: EventURLs? = nil,
        groupId: String? = nil,
        groupName: String? = nil,
        route: String? = nil,
        segment: PassSegment? = nil,
        segments: [PassSegment]? = nil
    ) {
        self.eventType = eventType
        self.eventName = eventName
        self.title = title
        self.description = description
        self.date = date
        self.time = time
        self.duration = duration
        self.venueName = venueName
        self.venueAddress = venueAddress
        self.city = city
        self.stateCountry = stateCountry
        self.latitude = latitude
        self.longitude = longitude
        self.organizer = organizer
        self.performerArtist = performerArtist
        self.seatInfo = seatInfo
        self.barcodeData = barcodeData
        self.price = price
        self.confirmationNumber = confirmationNumber
        self.gateInfo = gateInfo
        self.eventDescription = eventDescription
        self.venueType = venueType
        self.capacity = capacity
        self.website = website
        self.phone = phone
        self.nearbyLandmarks = nearbyLandmarks
        self.publicTransport = publicTransport
        self.parkingInfo = parkingInfo
        self.ageRestriction = ageRestriction
        self.dressCode = dressCode
        self.weatherConsiderations = weatherConsiderations
        self.amenities = amenities
        self.accessibility = accessibility
        self.aiProcessed = aiProcessed
        self.confidenceScore = confidenceScore
        self.processingTimestamp = processingTimestamp
        self.modelUsed = modelUsed
        self.enrichmentCompleted = enrichmentCompleted
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.labelColor = labelColor
        self.multipleEvents = multipleEvents
        self.upcomingEvents = upcomingEvents
        self.groupId = groupId
        self.groupName = groupName
        self.route = route
        self.segment = segment
        self.segments = segments
        self.venuePlaceId = venuePlaceId
        self.performerNames = performerNames
        self.exhibitName = exhibitName
        self.hasAssignedSeating = hasAssignedSeating
        self.eventUrls = eventUrls
    }
}

// iOS 26 Upcoming Event structure
struct UpcomingEvent: Codable {
    let id: String
    let name: String
    let date: String?
    let venueName: String?
    let latitude: Double?
    let longitude: Double?
    let appleMapsId: String?
    let seatInfo: String?
    let performerArtist: String?
    let eventType: String?
    let urls: EventURLs?
    let isActive: Bool?
    let headerImageUrl: String?
    let venueMapUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case date
        case venueName = "venue_name"
        case latitude
        case longitude
        case appleMapsId = "apple_maps_id"
        case seatInfo = "seat_info"
        case performerArtist = "performer_artist"
        case eventType = "event_type"
        case urls
        case isActive = "is_active"
        case headerImageUrl = "header_image_url"
        case venueMapUrl = "venue_map_url"
    }
}

/// One leg of a multi-part booking — a train ride, a flight, a night.
/// Mirrors the backend's `PassSegment`.
struct PassSegment: Codable, Hashable {
    let page: Int?
    let label: String?
    let origin: String?
    let destination: String?
    let departDate: String?
    let departTime: String?
    let arriveDate: String?
    let arriveTime: String?
    let carrier: String?
    let vehicleInfo: String?
    let seatInfo: String?
    let travelClass: String?
    let confirmationNumber: String?
    let traveler: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case page
        case label
        case origin
        case destination
        case departDate = "depart_date"
        case departTime = "depart_time"
        case arriveDate = "arrive_date"
        case arriveTime = "arrive_time"
        case carrier
        case vehicleInfo = "vehicle_info"
        case seatInfo = "seat_info"
        case travelClass = "travel_class"
        case confirmationNumber = "confirmation_number"
        case traveler
        case notes
    }

    /// "Málaga → Madrid", or whichever end we know. Nil when neither is present.
    var routeDescription: String? {
        switch (origin, destination) {
        case let (origin?, destination?): return "\(origin) → \(destination)"
        case let (origin?, nil): return origin
        case let (nil, destination?): return destination
        default: return nil
        }
    }
}

// iOS 26 Event URLs structure
struct EventURLs: Codable {
    let parkingInfoUrl: String?
    let merchandiseUrl: String?
    let venueInfoUrl: String?
    let ticketTransferUrl: String?
    let foodOrderingUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case parkingInfoUrl = "parking_info_url"
        case merchandiseUrl = "merchandise_url"
        case venueInfoUrl = "venue_info_url"
        case ticketTransferUrl = "ticket_transfer_url"
        case foodOrderingUrl = "food_ordering_url"
    }
}

struct UploadResponse: Codable {
    let jobId: String
    let status: String
    let passUrl: String?
    let aiMetadata: EnhancedPassMetadata?
    let ticketCount: Int?
    let warnings: [String]?
    let remainingPasses: Int?

    init(
        jobId: String,
        status: String,
        passUrl: String?,
        aiMetadata: EnhancedPassMetadata?,
        ticketCount: Int?,
        warnings: [String]?,
        remainingPasses: Int? = nil
    ) {
        self.jobId = jobId
        self.status = status
        self.passUrl = passUrl
        self.aiMetadata = aiMetadata
        self.ticketCount = ticketCount
        self.warnings = warnings
        self.remainingPasses = remainingPasses
    }

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status
        case passUrl = "pass_url"
        case aiMetadata = "ai_metadata"
        case ticketCount = "ticket_count"
        case warnings
        case remainingPasses = "remaining_passes"
    }
}

struct ErrorResponse: Codable {
    let error: String
}

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(String, statusCode: Int? = nil)
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let message, let statusCode):
            if let code = statusCode {
                return "\(message) (Code: \(code))"
            }
            return message
        case .decodingError:
            return "Failed to decode server response"
        }
    }
    
    var statusCode: Int? {
        switch self {
        case .serverError(_, let statusCode):
            return statusCode
        default:
            return nil
        }
    }
}

class NetworkService {
    private let baseURL: URL
    private let session: URLSession
    private let appUserIDProvider: () -> String

    init(
        baseURL: URL = URL(string: "https://add2wallet-backend-production.up.railway.app")!,
        session: URLSession? = nil,
        appUserIDProvider: @escaping () -> String = { Purchases.shared.appUserID }
    ) {
        self.baseURL = baseURL
        self.appUserIDProvider = appUserIDProvider

        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60.0
            config.timeoutIntervalForResource = 60.0
            self.session = URLSession(configuration: config)
        }
    }
    
    private static let retryDelays: [TimeInterval] = [0.5, 1.0, 2.0]

    private static func isRetryableError(_ error: Error) -> Bool {
        guard let networkError = error as? NetworkError,
              let statusCode = networkError.statusCode else {
            return false
        }
        return statusCode >= 500
    }

    func uploadFile(data: Data, filename: String, isRetry: Bool = false, isDemo: Bool = false) -> AnyPublisher<UploadResponse, Error> {
        func attempt(retryIndex: Int) -> AnyPublisher<UploadResponse, Error> {
            return makeUploadRequest(data: data, filename: filename, isRetry: isRetry, isDemo: isDemo)
                .catch { error -> AnyPublisher<UploadResponse, Error> in
                    guard retryIndex < Self.retryDelays.count,
                          Self.isRetryableError(error) else {
                        return Fail(error: error).eraseToAnyPublisher()
                    }
                    let delay = Self.retryDelays[retryIndex]
                    print("[NetworkService] Upload failed with \(error.localizedDescription), retrying in \(delay)s (attempt \(retryIndex + 2)/\(Self.retryDelays.count + 1))")
                    return Just(())
                        .delay(for: .seconds(delay), scheduler: DispatchQueue.main)
                        .setFailureType(to: Error.self)
                        .flatMap { _ in attempt(retryIndex: retryIndex + 1) }
                        .eraseToAnyPublisher()
                }
                .eraseToAnyPublisher()
        }

        return attempt(retryIndex: 0)
    }

    // Kept for source compatibility with older call sites and tests.
    func uploadPDF(data: Data, filename: String, isRetry: Bool = false, isDemo: Bool = false) -> AnyPublisher<UploadResponse, Error> {
        uploadFile(data: data, filename: filename, isRetry: isRetry, isDemo: isDemo)
    }

    private func makeUploadRequest(data: Data, filename: String, isRetry: Bool, isDemo: Bool) -> AnyPublisher<UploadResponse, Error> {
        let url = baseURL.appendingPathComponent("api/v1/conversions")
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("add2wallet-prod-4fafa87d63f30ecc38e1a156bcb240d6", forHTTPHeaderField: "X-API-Key")

        var body = Data()

        // Add file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(SupportedFile.mimeType(for: filename))\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)

        // Add user_id (from RevenueCat)
        let appUserId = appUserIDProvider()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"user_id\"\r\n\r\n".data(using: .utf8)!)
        body.append(appUserId.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        // Add session_token
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"session_token\"\r\n\r\n".data(using: .utf8)!)
        body.append("development-token".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        // Add is_retry flag
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"is_retry\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(isRetry)".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        // Add is_demo flag
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"is_demo\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(isDemo)".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        return session.dataTaskPublisher(for: request)
            .tryMap { data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }

                if httpResponse.statusCode == 200 {
                    return data
                } else {
                    if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                        throw NetworkError.serverError(errorResponse.error, statusCode: httpResponse.statusCode)
                    }
                    throw NetworkError.serverError("Server error: \(httpResponse.statusCode)", statusCode: httpResponse.statusCode)
                }
            }
            .decode(type: UploadResponse.self, decoder: JSONDecoder())
            .eraseToAnyPublisher()
    }
    
    func downloadPass(from passUrl: String) -> AnyPublisher<Data, Error> {
        guard let url = URL(string: passUrl, relativeTo: baseURL)?.absoluteURL else {
            return Fail(error: NetworkError.invalidURL)
                .eraseToAnyPublisher()
        }

        var request = URLRequest(url: url)
        request.setValue("add2wallet-prod-4fafa87d63f30ecc38e1a156bcb240d6", forHTTPHeaderField: "X-API-Key")
        
        return session.dataTaskPublisher(for: request)
            .tryMap { data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }
                
                if httpResponse.statusCode == 200 {
                    return data
                } else {
                    throw NetworkError.serverError("Failed to download pass: \(httpResponse.statusCode)")
                }
            }
            .eraseToAnyPublisher()
    }
}
