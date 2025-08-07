import Foundation
import Combine

struct UploadResponse: Codable {
    let jobId: String
    let status: String
    let passUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status
        case passUrl = "pass_url"
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
    private let session = URLSession.shared
    
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