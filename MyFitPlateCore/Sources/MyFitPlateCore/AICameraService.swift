import Foundation

public enum ImageAttachmentSource: String, Codable, Sendable {
    case camera = "camera"
    case photoLibrary = "photo_library"
    case menuPhoto = "menu_photo"
}

public struct ImageAttachment: Codable, Sendable {
    public let id: String
    public let source: ImageAttachmentSource
    public let timestamp: Date
    public let imageData: Data?
    public let estimatedFoodItems: [FoodItem]

    public init(id: String = UUID().uuidString, source: ImageAttachmentSource, timestamp: Date = Date(), imageData: Data? = nil, estimatedFoodItems: [FoodItem] = []) {
        self.id = id
        self.source = source
        self.timestamp = timestamp
        self.imageData = imageData
        self.estimatedFoodItems = estimatedFoodItems
    }
}

public protocol AICameraServicing: AnyObject, Sendable {
    func prepareImageData(_ data: Data, maxSizeBytes: Int) -> Data?
    func createAttachment(from data: Data, source: ImageAttachmentSource) -> ImageAttachment?
}

public final class AICameraService: AICameraServicing, Sendable {
    public init() {}

    public func prepareImageData(_ data: Data, maxSizeBytes: Int = 1_000_000) -> Data? {
        guard !data.isEmpty else { return nil }
        if data.count <= maxSizeBytes {
            return data
        }
        return data.prefix(maxSizeBytes)
    }

    public func createAttachment(from data: Data, source: ImageAttachmentSource) -> ImageAttachment? {
        guard let validData = prepareImageData(data) else { return nil }
        return ImageAttachment(source: source, imageData: validData)
    }
}
