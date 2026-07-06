import Foundation
#if canImport(Speech) && canImport(AVFoundation)
import Speech
import AVFoundation
#endif

public enum VoiceLoggingState: String, Sendable, Equatable {
    case idle
    case recording
    case transcribing
    case completed
    case error
}

public struct VoiceLogResult: Codable, Sendable, Equatable {
    public let transcript: String
    public let durationSeconds: TimeInterval
    public let timestamp: Date

    public init(transcript: String, durationSeconds: TimeInterval, timestamp: Date = Date()) {
        self.transcript = transcript
        self.durationSeconds = durationSeconds
        self.timestamp = timestamp
    }
}

/// Seam over live speech capture, so the service's state machine tests without a
/// microphone — the same pattern as UserNotificationScheduling/HealthStoreScheduling.
@MainActor
public protocol VoiceCaptureEngine: AnyObject {
    /// Begins capture. Partial transcripts stream to `onPartial`; asynchronous failures
    /// (permission denied after the fact, recognizer dropouts) arrive via `onError`.
    func start(onPartial: @escaping @MainActor (String) -> Void, onError: @escaping @MainActor (Error) -> Void) throws
    /// Ends capture and resolves with the final transcript once recognition settles.
    func finish() async -> String?
    func cancel()
}

@MainActor
public protocol VoiceLoggingServicing: AnyObject {
    var state: VoiceLoggingState { get }
    var currentTranscript: String { get }

    func startRecording() throws
    func stopRecording() async throws -> VoiceLogResult
    func cancelRecording()
}

/// State machine for voice logging. With an engine it drives real speech capture; without
/// one it is a pure, mic-free state machine — which is exactly what the tests exercise.
@MainActor
public class VoiceLoggingService: ObservableObject, VoiceLoggingServicing {
    @Published public private(set) var state: VoiceLoggingState = .idle
    @Published public private(set) var currentTranscript: String = ""

    private let engine: VoiceCaptureEngine?
    private var recordingStartTime: Date?

    public init(engine: VoiceCaptureEngine? = nil) {
        self.engine = engine
    }

    public func startRecording() throws {
        guard state == .idle || state == .completed || state == .error else {
            throw VoiceLoggingError.alreadyRecording
        }
        currentTranscript = ""
        recordingStartTime = Date()

        if let engine {
            try engine.start(
                onPartial: { [weak self] partial in
                    self?.ingestPartialTranscript(partial)
                },
                onError: { [weak self] _ in
                    self?.engine?.cancel()
                    self?.state = .error
                }
            )
        }
        state = .recording
    }

    public func stopRecording() async throws -> VoiceLogResult {
        guard state == .recording else {
            throw VoiceLoggingError.notRecording
        }
        state = .transcribing
        let duration = Date().timeIntervalSince(recordingStartTime ?? Date())

        let finalTranscript = await engine?.finish() ?? currentTranscript
        currentTranscript = finalTranscript

        state = .completed
        return VoiceLogResult(
            transcript: finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines),
            durationSeconds: max(1.0, duration)
        )
    }

    public func cancelRecording() {
        engine?.cancel()
        state = .idle
        currentTranscript = ""
        recordingStartTime = nil
    }

    /// Live partial results land here (engine callback); public so tests can drive the
    /// state machine without a microphone.
    public func ingestPartialTranscript(_ transcript: String) {
        guard state == .recording else { return }
        currentTranscript = transcript
    }

    /// Clears an error state after the UI has surfaced it.
    public func acknowledgeError() {
        guard state == .error else { return }
        state = .idle
        currentTranscript = ""
        recordingStartTime = nil
    }
}

public enum VoiceLoggingError: Error, LocalizedError, Equatable {
    case alreadyRecording
    case notRecording
    case permissionDenied
    case speechRecognitionUnavailable

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording: return "Voice logging is already recording."
        case .notRecording: return "No active voice recording to stop."
        case .permissionDenied: return "Microphone or speech recognition permission was declined."
        case .speechRecognitionUnavailable: return "Speech recognition is currently unavailable."
        }
    }
}

#if canImport(Speech) && canImport(AVFoundation)
/// The real capture engine: AVAudioEngine microphone tap streaming into SFSpeechRecognizer
/// with live partial results. Constructing it touches no hardware; only start() does.
@MainActor
public final class SpeechCaptureEngine: VoiceCaptureEngine {

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var latestTranscript: String?
    private var finalContinuation: CheckedContinuation<String?, Never>?

    public init() {}

    public func start(
        onPartial: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) throws {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw VoiceLoggingError.speechRecognitionUnavailable
        }
        latestTranscript = nil

        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard status == .authorized else {
                    onError(VoiceLoggingError.permissionDenied)
                    return
                }
                #if os(iOS)
                let granted = await AVAudioApplication.requestRecordPermission()
                guard granted else {
                    onError(VoiceLoggingError.permissionDenied)
                    return
                }
                #endif
                do {
                    try self.beginCapture(onPartial: onPartial, onError: onError)
                } catch {
                    onError(error)
                }
            }
        }
    }

    private func beginCapture(
        onPartial: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = SFSpeechRecognizer()?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.latestTranscript = result.bestTranscription.formattedString
                    onPartial(result.bestTranscription.formattedString)
                    if result.isFinal {
                        self.resolveFinal()
                    }
                }
                if error != nil {
                    // Post-stop errors just mean "no more results" — resolve with what we have.
                    self.resolveFinal()
                }
            }
        }
    }

    public func finish() async -> String? {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        let transcript = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            finalContinuation = continuation
            // Recognition usually settles well under a second after endAudio; the timeout
            // guarantees the UI never hangs in "transcribing".
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self?.resolveFinal()
            }
        }
        teardown()
        return transcript
    }

    public func cancel() {
        recognitionTask?.cancel()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        resolveFinal()
        teardown()
        latestTranscript = nil
    }

    private func resolveFinal() {
        guard let continuation = finalContinuation else { return }
        finalContinuation = nil
        continuation.resume(returning: latestTranscript)
    }

    private func teardown() {
        recognitionTask = nil
        recognitionRequest = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
#endif
