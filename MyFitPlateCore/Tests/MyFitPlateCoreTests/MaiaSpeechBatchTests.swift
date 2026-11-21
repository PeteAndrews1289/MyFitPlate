import XCTest
@testable import MyFitPlateCore

@MainActor
final class MaiaSpeechBatchTests: XCTestCase {
    func testClientBatchPreservesSentenceOrderAndNeverExceedsOriginalRequestSize() {
        let plan = MaiaSpeechPlan(source: (1...20).map { "Sentence \($0) has a precise 42.5 pound target." }.joined(separator: " "))
        let first = plan.onlineBatch(startingAt: 0)
        XCTAssertEqual(first, Array(plan.sentences.prefix(6)))
        XCTAssertEqual(plan.onlineBatch(startingAt: 6).first, plan.sentences[6])
        XCTAssertLessThanOrEqual(first.joined(separator: " ").utf16.count, 1_800)
        let long = MaiaSpeechPlan(source: String(repeating: "Use the same controlled weight and repetitions. ", count: 100))
        for index in long.sentences.indices { XCTAssertLessThanOrEqual(long.onlineBatch(startingAt: index).joined(separator: " ").utf16.count, 1_800) }
    }

    func testJoinedLegacyResponseAndWrongOrderCannotMasqueradeAsSentenceAudio() throws {
        let encoded = Data([1, 2]).base64EncodedString()
        XCTAssertThrowsError(try MaiaSpeechBatchPayload.audio(from: ["audioBase64": encoded], expectedCount: 2))
        XCTAssertThrowsError(try MaiaSpeechBatchPayload.audio(from: ["segments": [["index": 1, "audioBase64": encoded], ["index": 0, "audioBase64": encoded]]], expectedCount: 2))
        let ordered: [String: Any] = ["segments": [["index": 0, "audioBase64": encoded], ["index": 1, "audioBase64": encoded]]]
        XCTAssertEqual(try MaiaSpeechBatchPayload.audio(from: ordered, expectedCount: 2), [Data([1, 2]), Data([1, 2])])
    }

    func testNextSentenceUsesItsOrderedCachedChunkWithoutAnotherProviderRequest() async {
        let fixture = BatchFixture()
        let manager = fixture.manager()
        manager.speak("First sentence. Second sentence. Third sentence.")
        await fixture.waitUntilRequested()
        fixture.finish(); await settle()
        XCTAssertEqual(fixture.played, [Data([1])])
        manager.pauseSpeaking(); manager.seekSentence(1); manager.resumeSpeaking()
        await settle()
        XCTAssertEqual(fixture.requests, 1)
        XCTAssertEqual(fixture.played, [Data([1]), Data([2])])
        manager.stopSpeaking()
    }

    func testCancelledBatchCannotRecreateAnyOfItsCachedChunks() async {
        let fixture = BatchFixture()
        let manager = fixture.manager()
        manager.speak("First private sentence. Second private sentence.")
        await fixture.waitUntilRequested()
        manager.clearCachedSpeech(for: "one")
        fixture.finish(); await settle()
        XCTAssertTrue(fixture.played.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent(TTSManager.cacheScopeIdentifier(for: "one")).path))
        XCTAssertNil(manager.currentSpokenText)
    }

    private func settle() async { for _ in 0..<100 { await Task.yield() } }

    @MainActor private final class BatchFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let receipt = AIDataConsent(includesHealthData: false)
        var texts: [String] = []
        var requests = 0
        var played: [Data] = []
        var continuation: CheckedContinuation<[Data], Error>?
        func manager() -> TTSManager {
            let manager = TTSManager(environment: .init(currentOwner: { "one" }, consent: { _ in self.receipt },
                request: { _ in XCTFail("This reply fits one batch"); throw APIError.noData },
                requestBatch: { texts in
                    self.requests += 1; self.texts = texts
                    return try await withCheckedThrowingContinuation { self.continuation = $0 }
                }, cacheDirectory: directory, playAudio: { self.played.append($0); return true },
                defaults: UserDefaults(suiteName: UUID().uuidString)!, drafts: EditorDraftStore(directory: directory.appendingPathComponent("drafts"))))
            manager.selectVoice(identifier: TTSManager.onlineVoiceIdentifier)
            return manager
        }
        func waitUntilRequested() async {
            for _ in 0..<100 where continuation == nil { await Task.yield() }
            XCTAssertNotNil(continuation)
        }
        func finish() {
            continuation?.resume(returning: texts.indices.map { Data([UInt8($0 + 1)]) }); continuation = nil
        }
        deinit { try? FileManager.default.removeItem(at: directory) }
    }
}
