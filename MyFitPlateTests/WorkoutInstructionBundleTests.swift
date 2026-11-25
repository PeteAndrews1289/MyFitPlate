import XCTest
import AVFoundation
import CryptoKit
import MyFitPlateCore

final class WorkoutInstructionBundleTests: XCTestCase {
    func testBundledCatalogHasPlayableExactIdentityAssetsAndLicenseEvidence() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "WorkoutInstructionManifest", withExtension: "json"))
        let catalog = try WorkoutBuiltinInstructionCatalog.decode(Data(contentsOf: url))
        XCTAssertEqual(catalog.entries.count, 4)
        for entry in catalog.entries {
            let file = try XCTUnwrap(Bundle.main.url(forResource: entry.resourceName, withExtension: entry.fileExtension))
            let data = try Data(contentsOf: file)
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), entry.contentSHA256)
            let asset = AVURLAsset(url: file)
            let playable = try await asset.load(.isPlayable), duration = try await asset.load(.duration)
            XCTAssertTrue(playable); XCTAssertGreaterThan(duration.seconds, 2); XCTAssertLessThan(duration.seconds, 20)
            XCTAssertEqual(entry.author, "FitnessScape"); XCTAssertEqual(entry.licenseName, "CC BY 3.0")
            XCTAssertEqual(entry.sourceURL.host, "commons.wikimedia.org")
            var movement = RoutineExercise(name: entry.canonicalName)
            movement.movementIdentity = WorkoutMovementCatalog.identity(for: entry.canonicalName)
            XCTAssertEqual(catalog.media(for: movement)?.id, entry.id)
            movement.movementIdentity?.variantID = "different-variant"
            XCTAssertNil(catalog.media(for: movement))
            movement.movementIdentity = .init(movementID: entry.movementID, variantID: entry.variantID, ownerID: "custom-owner")
            XCTAssertNil(catalog.media(for: movement))
        }
        XCTAssertNil(catalog.media(for: RoutineExercise(name: "Smith Machine Bench Press")))
    }
    func testMovementCaptionsAreBoundedOrderedAndMatchPlayableAssetDuration() async throws {
        let manifestURL = try XCTUnwrap(Bundle.main.url(forResource: "WorkoutInstructionManifest", withExtension: "json"))
        let catalog = try WorkoutBuiltinInstructionCatalog.decode(Data(contentsOf: manifestURL))
        let captionsURL = try XCTUnwrap(Bundle.main.url(forResource: "WorkoutInstructionCaptions", withExtension: "json"))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: captionsURL)) as? [String: Any])
        XCTAssertEqual(document["version"] as? Int, 1)
        let clips = try XCTUnwrap(document["clips"] as? [String: [[String: Any]]])
        XCTAssertEqual(Set(clips.keys), Set(catalog.entries.map(\.id)))
        for entry in catalog.entries {
            let url = try XCTUnwrap(Bundle.main.url(forResource: entry.resourceName, withExtension: entry.fileExtension))
            let duration = try await AVURLAsset(url: url).load(.duration).seconds
            let cues = try XCTUnwrap(clips[entry.id]); XCTAssertFalse(cues.isEmpty)
            var previousEnd: Double = 0
            for cue in cues {
                let start = try XCTUnwrap(cue["start"] as? Double), end = try XCTUnwrap(cue["end"] as? Double)
                let text = try XCTUnwrap(cue["text"] as? String)
                XCTAssertGreaterThanOrEqual(start, previousEnd); XCTAssertGreaterThan(end, start)
                XCTAssertLessThanOrEqual(end, duration + 0.02); XCTAssertFalse(text.isEmpty)
                previousEnd = end
            }
        }
    }
}
