import XCTest
@testable import MyFitPlateCore

final class RunRouteShareProjectionTests: XCTestCase {
    private func point(_ longitude: Double, _ latitude: Double = 0) -> RunShareCoordinate {
        RunShareCoordinate(latitude: latitude, longitude: longitude)
    }

    func testEndpointCropRemovesRevisitsAndNeverJoinsAcrossHiddenRegion() {
        let original = [[point(0), point(0.004), point(0.005), point(0.0002), point(0.006), point(0.007), point(0.01)]]
        let shared = RunRouteShareProjection.segments(original, hidingEndpointMeters: 200)
        XCTAssertEqual(shared, [[point(0.004), point(0.005)], [point(0.006), point(0.007)]])
        XCTAssertEqual(original[0].count, 7, "The private route must stay unchanged")
        XCTAssertEqual(RunRouteShareProjection.segments(original, hidingEndpointMeters: 0), original)
        XCTAssertTrue(RunRouteShareProjection.segments(original, hidingEndpointMeters: 0, showRoute: false).isEmpty)
    }

    func testSparseLineCrossingHiddenOriginCannotLeakAConnectingTrace() {
        let original = [[point(0), point(-0.004), point(-0.003), point(0.003), point(0.004), point(0.01)]]
        XCTAssertEqual(RunRouteShareProjection.segments(original, hidingEndpointMeters: 200),
                       [[point(-0.004), point(-0.003)], [point(0.003), point(0.004)]])
    }

    func testPreexistingGapsInvalidAndTinyRoutesStayHonest() {
        let original = [[point(0), point(0.004), point(0.005)], [point(0.006), point(0.007), point(0.01)]]
        XCTAssertEqual(RunRouteShareProjection.segments(original, hidingEndpointMeters: 200),
                       [[point(0.004), point(0.005)], [point(0.006), point(0.007)]])
        XCTAssertTrue(RunRouteShareProjection.segments([[point(0), point(0.0001)]], hidingEndpointMeters: 200).isEmpty)
        XCTAssertTrue(RunRouteShareProjection.segments([[point(.nan), point(0)]], hidingEndpointMeters: 0).isEmpty)
        XCTAssertTrue(RunRouteShareProjection.segments(original, hidingEndpointMeters: .nan).isEmpty)
    }
}
