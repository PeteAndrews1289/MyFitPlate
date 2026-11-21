import Foundation

/// Coordinates are copied into a share-only projection. No timestamps, sensor IDs,
/// Health identifiers or account metadata enter social artwork.
public struct RunShareCoordinate: Codable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
    public var isValid: Bool { latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180 }
}

public enum RunRouteShareProjection {
    /// Hide circular regions around both endpoints, including later revisits. A removed
    /// point or a line crossing a hidden region breaks the trace; no cosmetic bridge.
    public static func segments(_ original: [[RunShareCoordinate]], hidingEndpointMeters radius: Double,
                                showRoute: Bool = true) -> [[RunShareCoordinate]] {
        guard showRoute, radius.isFinite, radius >= 0,
              let start = original.first?.first, let finish = original.last?.last,
              start.isValid, finish.isValid else { return [] }
        let centers = [start, finish]
        var result: [[RunShareCoordinate]] = []
        for segment in original {
            var visible: [RunShareCoordinate] = []
            for point in segment {
                guard point.isValid, radius == 0 || centers.allSatisfy({ distance(point, $0) >= radius }) else {
                    if visible.count > 1 { result.append(visible) }
                    visible = []
                    continue
                }
                if radius > 0, let previous = visible.last, centers.contains(where: { lineDistance(previous, point, center: $0) < radius }) {
                    if visible.count > 1 { result.append(visible) }
                    visible = []
                }
                visible.append(point)
            }
            if visible.count > 1 { result.append(visible) }
        }
        return result
    }

    private static func longitudeDelta(_ first: Double, _ second: Double) -> Double {
        let delta = (first - second).truncatingRemainder(dividingBy: 360)
        return delta > 180 ? delta - 360 : delta < -180 ? delta + 360 : delta
    }

    private static func distance(_ first: RunShareCoordinate, _ second: RunShareCoordinate) -> Double {
        let radians = Double.pi / 180
        let latitude = (first.latitude - second.latitude) * radians
        let longitude = longitudeDelta(first.longitude, second.longitude) * radians
        let haversine = pow(sin(latitude / 2), 2) + cos(first.latitude * radians) * cos(second.latitude * radians) * pow(sin(longitude / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(max(0, min(1, haversine))))
    }

    private static func lineDistance(_ first: RunShareCoordinate, _ second: RunShareCoordinate, center: RunShareCoordinate) -> Double {
        let scale = Double.pi / 180 * 6_371_000
        let cosine = cos(center.latitude * Double.pi / 180)
        let ax = longitudeDelta(first.longitude, center.longitude) * scale * cosine
        let ay = (first.latitude - center.latitude) * scale
        let bx = longitudeDelta(second.longitude, center.longitude) * scale * cosine
        let by = (second.latitude - center.latitude) * scale
        let dx = bx - ax, dy = by - ay
        let squaredLength = dx * dx + dy * dy
        guard squaredLength > 0 else { return sqrt(ax * ax + ay * ay) }
        let fraction = max(0, min(1, -(ax * dx + ay * dy) / squaredLength))
        let x = ax + fraction * dx, y = ay + fraction * dy
        return sqrt(x * x + y * y)
    }
}
