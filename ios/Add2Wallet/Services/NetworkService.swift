import Foundation
import Combine

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
    }
}

struct UploadResponse: Codable {
    let jobId: String
    let status: String
    let passUrl: String?
    let aiMetadata: EnhancedPassMetadata?
    let ticketCount: Int?
    let warnings: [String]?
    
    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status
        case passUrl = "pass_url"
        case aiMetadata = "ai_metadata"
        case ticketCount = "ticket_count"
        case warnings
    }
}

struct ErrorResponse: Codable {
    let error: String
}

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(String)
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let message):
            return message
        case .decodingError:
            return "Failed to decode server response"
        }
    }
}

class NetworkService {
    private let baseURL = "https://add2wallet-backend-production.up.railway.app"
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0  // 60 seconds
        config.timeoutIntervalForResource = 60.0 // 60 seconds
        self.session = URLSession(configuration: config)
    }
    
    func uploadPDF(data: Data, filename: String) -> AnyPublisher<UploadResponse, Error> {
        guard let url = URL(string: "\(baseURL)/upload") else {
            return Fail(error: NetworkError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("add2wallet-prod-4fafa87d63f30ecc38e1a156bcb240d6", forHTTPHeaderField: "X-API-Key")
        
        var body = Data()
        
        // Add file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/pdf\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add user_id
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"user_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("ios-test-user".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add session_token
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"session_token\"\r\n\r\n".data(using: .utf8)!)
        body.append("development-token".data(using: .utf8)!)
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
                        throw NetworkError.serverError(errorResponse.error)
                    }
                    throw NetworkError.serverError("Server error: \(httpResponse.statusCode)")
                }
            }
            .decode(type: UploadResponse.self, decoder: JSONDecoder())
            .eraseToAnyPublisher()
    }
    
    func downloadPass(from passUrl: String) -> AnyPublisher<Data, Error> {
        guard let url = URL(string: "\(baseURL)\(passUrl)") else {
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