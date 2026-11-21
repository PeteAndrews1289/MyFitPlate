import XCTest
@testable import MyFitPlateCore

@MainActor
final class MaiaSpeechPrivacyTests: XCTestCase {
    func testLateAudioAfterConsentRevocationCannotRecreateCacheOrPlay() async throws {
        let fixture = Fixture()
        let manager = fixture.manager()
        manager.speak("Keep the next set controlled.")
        await fixture.waitUntilRequested()
        fixture.receipt = nil
        manager.clearCachedSpeech(for: "one")
        fixture.finish()
        await settle()
        XCTAssertEqual(fixture.plays, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.accountDirectory.path))
        XCTAssertFalse(manager.isSpeaking)
    }

    func testLateAudioAfterAccountChangeCannotCachePlayOrUseLocalFallback() async throws {
        let fixture = Fixture()
        let manager = fixture.manager()
        manager.speak("A short recovery meal.")
        await fixture.waitUntilRequested()
        fixture.owner = "two"
        fixture.finish()
        await settle()
        XCTAssertEqual(fixture.plays, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.accountDirectory.path))
        manager.stopSpeaking()
    }

    func testPauseWhilePreparingDiscardsLateAudioAndResumeUsesNewGeneration() async {
        let fixture = Fixture()
        let manager = fixture.manager()
        manager.speak("Keep this sentence controlled. Then rest.")
        await fixture.waitUntilRequested()
        manager.pauseSpeaking()
        XCTAssertEqual(manager.playbackState, .paused)
        fixture.finish()
        await settle()
        XCTAssertEqual(fixture.plays, 0)
        XCTAssertEqual(manager.playbackState, .paused)
        manager.resumeSpeaking()
        await fixture.waitUntilRequested()
        XCTAssertEqual(fixture.requests, 2)
        fixture.finish()
        await settle()
        XCTAssertEqual(fixture.plays, 1)
        XCTAssertEqual(manager.playbackState, .playing)
        manager.stopSpeaking()
    }

    func testRelaunchRestoresPausedSentenceWithoutNetworkOrAutoplay() async {
        let fixture = Fixture()
        let first = fixture.manager()
        first.speak("First sentence. Second sentence.")
        await fixture.waitUntilRequested()
        first.pauseSpeaking(); fixture.finish(); await settle()
        first.seekSentence(1)
        let restored = fixture.manager(selectVoice: false)
        restored.restorePlayback()
        XCTAssertEqual(restored.playbackState, .paused)
        XCTAssertEqual(restored.sentenceIndex, 1)
        XCTAssertEqual(fixture.requests, 1)
        XCTAssertEqual(fixture.plays, 0)
        restored.stopSpeaking(); first.stopSpeaking()
    }

    func testPausedSpeechCannotResumeOrCheckpointIntoAnotherAccount() async throws {
        let fixture = Fixture()
        let manager = fixture.manager()
        manager.speak("Private first-account sentence. Another sentence.")
        await fixture.waitUntilRequested()
        manager.pauseSpeaking(); fixture.finish(); await settle()
        fixture.owner = "two"
        manager.resumeSpeaking()
        await settle()
        XCTAssertEqual(manager.playbackState, .idle)
        XCTAssertNil(manager.currentSpokenText)
        XCTAssertEqual(fixture.requests, 1)
        XCTAssertNil(try EditorDraftStore(directory: fixture.directory.appendingPathComponent("drafts"))
            .load(MaiaSpeechBookmark.self, userID: "two", scope: "maia-speech-bookmark-v1"))
    }

    func testNewConsentReceiptAndNewPlaybackGenerationInvalidateOriginalLease() {
        let receipt = AIDataConsent(grantedAt: Date(timeIntervalSince1970: 100), includesHealthData: false)
        let generation = UUID()
        let lease = MaiaSpeechLease(ownerID: "one", consent: receipt, generation: generation)
        XCTAssertTrue(lease.allows(ownerID: "one", consent: receipt, generation: generation))
        XCTAssertFalse(lease.allows(ownerID: "one", consent: receipt, generation: UUID()))
        XCTAssertFalse(lease.allows(ownerID: "one", consent: .init(grantedAt: Date(timeIntervalSince1970: 101), includesHealthData: false), generation: generation))
        XCTAssertFalse(lease.allows(ownerID: "two", consent: receipt, generation: generation))
    }

    func testExpiredCachedAudioIsFetchedAgain() async throws {
        let fixture = Fixture()
        let manager = fixture.manager()
        manager.speak("Keep it easy.")
        await fixture.waitUntilRequested()
        fixture.finish()
        await settle()
        XCTAssertEqual(fixture.plays, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.accountDirectory.path))
        manager.stopSpeaking()
        fixture.now = fixture.now.addingTimeInterval(TTSManager.maximumCacheAge + 1)
        manager.speak("Keep it easy.")
        await fixture.waitUntilRequested()
        XCTAssertEqual(fixture.requests, 2)
        fixture.finish()
        await settle()
        XCTAssertEqual(fixture.plays, 2)
        manager.stopSpeaking()
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @MainActor private final class Fixture {
        var owner: String? = "one"
        var receipt: AIDataConsent? = .init(includesHealthData: false)
        var now = Date()
        var plays = 0
        var requests = 0
        var continuation: CheckedContinuation<Data, Error>?
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var accountDirectory: URL { directory.appendingPathComponent(TTSManager.cacheScopeIdentifier(for: "one")) }

        func manager(selectVoice: Bool = true) -> TTSManager {
            let manager = TTSManager(environment: .init(currentOwner: { self.owner }, consent: { _ in self.receipt },
                request: { _ in
                    self.requests += 1
                    return try await withCheckedThrowingContinuation { self.continuation = $0 }
                }, cacheDirectory: directory, now: { self.now }, playAudio: { _ in self.plays += 1; return true },
                defaults: UserDefaults(suiteName: UUID().uuidString)!, drafts: EditorDraftStore(directory: directory.appendingPathComponent("drafts"))))
            if selectVoice { manager.selectVoice(identifier: TTSManager.onlineVoiceIdentifier) }
            return manager
        }

        func waitUntilRequested() async {
            for _ in 0..<100 where continuation == nil { await Task.yield() }
            XCTAssertNotNil(continuation)
        }

        func finish() {
            continuation?.resume(returning: Data([1, 2, 3]))
            continuation = nil
        }

        deinit { try? FileManager.default.removeItem(at: directory) }
    }
}
