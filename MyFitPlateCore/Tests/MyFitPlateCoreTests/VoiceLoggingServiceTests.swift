import XCTest
@testable import MyFitPlateCore

@MainActor
final class VoiceLoggingServiceTests: XCTestCase {
    private var service: VoiceLoggingService!

    override func setUp() {
        super.setUp()
        service = VoiceLoggingService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    func testInitialState() {
        XCTAssertEqual(service.state, .idle)
        XCTAssertTrue(service.currentTranscript.isEmpty)
    }

    func testPartialTranscriptsFlowIntoTheResult() async throws {
        try service.startRecording()
        XCTAssertEqual(service.state, .recording)

        service.ingestPartialTranscript("grilled")
        service.ingestPartialTranscript("grilled chicken and rice")
        XCTAssertEqual(service.currentTranscript, "grilled chicken and rice")

        let result = try await service.stopRecording()
        XCTAssertEqual(service.state, .completed)
        XCTAssertEqual(result.transcript, "grilled chicken and rice")
        XCTAssertGreaterThanOrEqual(result.durationSeconds, 1.0)
    }

    func testSilenceProducesAnEmptyTranscriptNotACannedOne() async throws {
        try service.startRecording()
        let result = try await service.stopRecording()
        XCTAssertTrue(result.transcript.isEmpty, "No speech means no transcript — never a fabricated one")
    }

    func testPartialsAreIgnoredOutsideRecording() {
        service.ingestPartialTranscript("should not land")
        XCTAssertTrue(service.currentTranscript.isEmpty)
    }

    func testStartRecordingWhenAlreadyRecordingThrows() throws {
        try service.startRecording()
        XCTAssertThrowsError(try service.startRecording()) { error in
            XCTAssertEqual(error as? VoiceLoggingError, .alreadyRecording)
        }
    }

    func testStopRecordingWhenNotRecordingThrows() async {
        do {
            _ = try await service.stopRecording()
            XCTFail("Should throw error when stopping while not recording")
        } catch {
            XCTAssertEqual(error as? VoiceLoggingError, .notRecording)
        }
    }

    func testCancelRecording() throws {
        try service.startRecording()
        XCTAssertEqual(service.state, .recording)

        service.cancelRecording()
        XCTAssertEqual(service.state, .idle)
        XCTAssertTrue(service.currentTranscript.isEmpty)
    }

    func testEngineErrorsLandInErrorStateAndAcknowledgeClears() throws {
        let engine = FailingCaptureEngine()
        let failing = VoiceLoggingService(engine: engine)

        try failing.startRecording()
        engine.reportError(VoiceLoggingError.permissionDenied)

        XCTAssertEqual(failing.state, .error)
        XCTAssertTrue(engine.cancelled, "A failed engine is torn down")

        failing.acknowledgeError()
        XCTAssertEqual(failing.state, .idle)
        XCTAssertNoThrow(try failing.startRecording(), "Recoverable after acknowledging")
    }
}

@MainActor
private final class FailingCaptureEngine: VoiceCaptureEngine {
    private var onError: (@MainActor (Error) -> Void)?
    private(set) var cancelled = false

    func start(onPartial: @escaping @MainActor (String) -> Void, onError: @escaping @MainActor (Error) -> Void) throws {
        self.onError = onError
    }

    func reportError(_ error: Error) {
        onError?(error)
    }

    func finish() async -> String? { nil }

    func cancel() { cancelled = true }
}
