import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case noData
    case decodingError(Error)
    case networkError(Error)
    case apiError(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The provided URL was invalid."
        case .noData:
            return "No data was received from the server."
        case .decodingError(let error):
            return "There was an error decoding the data: \(error.localizedDescription)"
        case .networkError(let error):
            return "There was a network error: \(error.localizedDescription)"
        case .apiError(let message):
            return message
        case .unknown:
            return "An unknown error occurred."
        }
    }
}
