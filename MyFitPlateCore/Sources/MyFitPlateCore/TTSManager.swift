import Foundation
import AVFoundation
import CryptoKit

public struct MaiaVoiceOption: Identifiable, Equatable {
    public enum Quality: Int, Comparable {
        case standard
        case enhanced
        case premium

        public static func < (lhs: Quality, rhs: Quality) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        public var label: String {
            switch self {
            case .standard: return "Standard"
            case .enhanced: return "Enhanced"
            case .premium: return "Premium"
            }
        }
    }

    public enum Gender: Int {
        case unspecified
        case male
        case female
    }

    public let id: String
    public let name: String
    public let language: String
    public let quality: Quality
    public let gender: Gender
    public let isNovelty: Bool
    public let isPersonal: Bool
    public let isOnline: Bool

    public var accentLabel: String {
        switch language {
        case "en-US": return "American English"
        case "en-GB": return "British English"
        case "en-IE": return "Irish English"
        case "en-AU": return "Australian English"
        case "en-ZA": return "South African English"
        case "fr-FR": return "French"
        case "fr-CA": return "French Canadian"
        default:
            return Locale.current.localizedString(forIdentifier: language) ?? language
        }
    }

    public var pickerLabel: String {
        if isOnline {
            return "\(name) · Online · Natural"
        }
        return "\(name) · \(accentLabel) · \(quality.label)"
    }

    public init(
        id: String,
        name: String,
        language: String,
        quality: Quality,
        gender: Gender = .unspecified,
        isNovelty: Bool = false,
        isPersonal: Bool = false,
        isOnline: Bool = false
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.quality = quality
        self.gender = gender
        self.isNovelty = isNovelty
        self.isPersonal = isPersonal
        self.isOnline = isOnline
    }
}

@MainActor
public class TTSManager: NSObject, ObservableObject, @preconcurrency AVSpeechSynthesizerDelegate, @preconcurrency AVAudioPlayerDelegate {
    public static let shared = TTSManager()
    public static let onlineVoiceIdentifier = "maia-natural-online"
    static let maximumOnlineCharacterCount = 1_800

    private let speechSynthesizer = AVSpeechSynthesizer()
    private let selectedVoiceDefaultsKey = "maiaSpokenVoiceIdentifier"
    private let maximumCachedSpeechFiles = 20
    @Published public var isSpeaking: Bool = false
    @Published public var mouthShape: String = "mouth_neutral"
    @Published public private(set) var availableVoices: [MaiaVoiceOption] = []
    @Published public private(set) var selectedVoiceIdentifier: String = ""
    @Published public private(set) var currentSpokenText: String?
    private var selectedVoice: AVSpeechSynthesisVoice?
    private var fallbackVoice: AVSpeechSynthesisVoice?
    private var audioPlayer: AVAudioPlayer?
    private var speechTask: Task<Void, Never>?

    public var selectedVoiceOption: MaiaVoiceOption? {
        availableVoices.first { $0.id == selectedVoiceIdentifier }
    }

    public var hasNaturalQualityVoice: Bool {
        selectedVoiceOption.map { $0.isOnline || $0.quality != .standard } ?? false
    }

    override init() {
        super.init()
        self.speechSynthesizer.delegate = self
        #if os(iOS) || os(watchOS) || os(tvOS)
        self.speechSynthesizer.usesApplicationAudioSession = false
        #endif
        removeLegacyUnscopedSpeechCache()
        refreshAvailableVoices()
    }

    public func refreshAvailableVoices() {
        let systemVoices = AVSpeechSynthesisVoice.speechVoices()
        let systemOptions = Self.rankEligibleVoiceOptions(systemVoices.map(Self.option(from:)))
        let onlineEnabled = DIContainer.shared.featureFlagService?.boolValue(for: .maiaNaturalVoice)
            ?? FeatureFlag.maiaNaturalVoice.defaultValue
        let rankedOptions = (onlineEnabled ? [Self.onlineVoiceOption] : []) + systemOptions
        availableVoices = rankedOptions

        let storedIdentifier = UserDefaults.standard.string(forKey: selectedVoiceDefaultsKey)
        let preferredIdentifier = storedIdentifier.flatMap { identifier in
            rankedOptions.contains { $0.id == identifier } ? identifier : nil
        }
        selectedVoiceIdentifier = preferredIdentifier ?? rankedOptions.first?.id ?? ""
        fallbackVoice = systemOptions.first.flatMap { AVSpeechSynthesisVoice(identifier: $0.id) }
            ?? AVSpeechSynthesisVoice(language: "en-US")
        selectedVoice = selectedVoiceIdentifier == Self.onlineVoiceIdentifier
            ? nil
            : AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier) ?? fallbackVoice
    }

    public func selectVoice(identifier: String) {
        guard availableVoices.contains(where: { $0.id == identifier }) else { return }
        stopSpeaking()
        selectedVoiceIdentifier = identifier
        selectedVoice = identifier == Self.onlineVoiceIdentifier
            ? nil
            : AVSpeechSynthesisVoice(identifier: identifier) ?? fallbackVoice
        UserDefaults.standard.set(identifier, forKey: selectedVoiceDefaultsKey)
    }

    public func previewSelectedVoice() {
        speak("Hi, I'm Maia. Let's look at your day and choose one practical next step.")
    }

    public func speak(_ text: String) {
        stopSpeaking()

        let spokenText = MaiaSpeechFormatter.spokenText(from: text)
        guard !spokenText.isEmpty else { return }
        currentSpokenText = spokenText

        if selectedVoiceIdentifier == Self.onlineVoiceIdentifier {
            speakOnline(spokenText)
            return
        }
        speakWithSystemVoice(spokenText)
    }

    private func speakWithSystemVoice(_ spokenText: String) {
        let utterance = AVSpeechUtterance(string: spokenText)
        utterance.voice = selectedVoice ?? fallbackVoice
        utterance.rate = selectedVoiceOption?.language.hasPrefix("fr-") == true ? 0.46 : 0.49
        utterance.pitchMultiplier = selectedVoiceOption?.gender == .female ? 1.02 : 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.04
        utterance.postUtteranceDelay = 0.08

        self.speechSynthesizer.speak(utterance)
    }

    public func stopSpeaking() {
        speechTask?.cancel()
        speechTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        finishSpeaking()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeaking = true
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishSpeaking()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finishSpeaking()
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finishSpeaking()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let word = (utterance.speechString as NSString).substring(with: characterRange).lowercased()
        
        if word.contains("o") || word.contains("u") || word.contains("w") {
            mouthShape = "mouth_o"
        } else if word.contains("a") || word.contains("e") || word.contains("i") {
            mouthShape = "mouth_open"
        } else {
            mouthShape = "mouth_neutral"
        }
    }

    static func rankEligibleVoiceOptions(_ options: [MaiaVoiceOption]) -> [MaiaVoiceOption] {
        let preferredNames = [
            "ava", "audrey", "amélie", "aurelie", "samantha", "zoe", "nicky", "joelle", "allison", "susan"
        ]
        let preferredLanguages = ["en-US", "fr-FR", "en-GB", "en-IE", "en-AU", "en-ZA", "fr-CA"]
        return options
            .filter { preferredLanguages.contains($0.language) && !$0.isNovelty && !$0.isPersonal }
            .sorted { lhs, rhs in
                let lhsNatural = lhs.quality == .standard ? 0 : 1
                let rhsNatural = rhs.quality == .standard ? 0 : 1
                if lhsNatural != rhsNatural { return lhsNatural > rhsNatural }
                if lhs.quality != rhs.quality { return lhs.quality > rhs.quality }
                if lhs.gender != rhs.gender { return lhs.gender.rawValue > rhs.gender.rawValue }

                let lhsLanguageRank = preferredLanguages.firstIndex(of: lhs.language) ?? preferredLanguages.count
                let rhsLanguageRank = preferredLanguages.firstIndex(of: rhs.language) ?? preferredLanguages.count
                if lhsLanguageRank != rhsLanguageRank { return lhsLanguageRank < rhsLanguageRank }

                let lhsNameRank = preferredNames.firstIndex(of: lhs.name.lowercased()) ?? preferredNames.count
                let rhsNameRank = preferredNames.firstIndex(of: rhs.name.lowercased()) ?? preferredNames.count
                if lhsNameRank != rhsNameRank { return lhsNameRank < rhsNameRank }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private static var onlineVoiceOption: MaiaVoiceOption {
        MaiaVoiceOption(
            id: onlineVoiceIdentifier,
            name: "Maia Natural",
            language: "en-US",
            quality: .premium,
            gender: .female,
            isOnline: true
        )
    }

    private static func option(from voice: AVSpeechSynthesisVoice) -> MaiaVoiceOption {
        let quality: MaiaVoiceOption.Quality
        switch voice.quality {
        case .premium: quality = .premium
        case .enhanced: quality = .enhanced
        default: quality = .standard
        }

        let gender: MaiaVoiceOption.Gender
        switch voice.gender {
        case .female: gender = .female
        case .male: gender = .male
        default: gender = .unspecified
        }

        return MaiaVoiceOption(
            id: voice.identifier,
            name: voice.name,
            language: voice.language,
            quality: quality,
            gender: gender,
            isNovelty: voice.voiceTraits.contains(.isNoveltyVoice),
            isPersonal: voice.voiceTraits.contains(.isPersonalVoice)
        )
    }

    private func finishSpeaking() {
        speechTask = nil
        audioPlayer = nil
        isSpeaking = false
        mouthShape = "mouth_neutral"
        currentSpokenText = nil
    }

    private func speakOnline(_ spokenText: String) {
        let authService: AuthServiceProtocol? = DIContainer.shared.authService
        guard let userID = authService?.currentUserID,
              AIDataConsentStore.shared.hasCurrentConsent(for: userID) else {
            if authService?.currentUserID != nil {
                NotificationCenter.default.post(name: .aiDataConsentRequired, object: nil)
            }
            speakWithSystemVoice(spokenText)
            return
        }

        guard Self.canUseOnlineSpeech(spokenText) else {
            speakWithSystemVoice(spokenText)
            return
        }

        isSpeaking = true
        speechTask = Task { [weak self] in
            guard let self else { return }
            do {
                let data: Data
                if let cached = self.cachedAudioData(for: spokenText, userID: userID) {
                    data = cached
                } else {
                    guard let service = DIContainer.shared.cloudFunctionService else {
                        throw APIError.noData
                    }
                    let payload = try await service.callFunction(
                        "generateMaiaSpeech",
                        with: ["text": spokenText]
                    )
                    guard let dictionary = payload as? [String: Any],
                          let encoded = dictionary["audioBase64"] as? String,
                          let decoded = Data(base64Encoded: encoded),
                          !decoded.isEmpty else {
                        throw APIError.noData
                    }
                    data = decoded
                    self.cacheAudioData(decoded, for: spokenText, userID: userID)
                }

                try Task.checkCancellation()
                guard self.currentSpokenText == spokenText else { return }
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                self.audioPlayer = player
                self.mouthShape = "mouth_open"
                guard player.play() else {
                    throw APIError.apiError("Audio playback could not start.")
                }
            } catch {
                guard !Task.isCancelled, self.currentSpokenText == spokenText else { return }
                self.speechTask = nil
                self.speakWithSystemVoice(spokenText)
            }
        }
    }

    static func canUseOnlineSpeech(_ text: String) -> Bool {
        !text.isEmpty && text.utf16.count <= maximumOnlineCharacterCount
    }

    static func cacheScopeIdentifier(for userID: String) -> String {
        SHA256.hash(data: Data(userID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public func clearCachedSpeech(for userID: String) {
        stopSpeaking()
        try? FileManager.default.removeItem(at: speechCacheDirectory(for: userID))
        removeLegacyUnscopedSpeechCache()
    }

    private func cachedAudioData(for text: String, userID: String) -> Data? {
        try? Data(contentsOf: speechCacheURL(for: text, userID: userID))
    }

    private func cacheAudioData(_ data: Data, for text: String, userID: String) {
        let directory = speechCacheDirectory(for: userID)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            try data.write(
                to: speechCacheURL(for: text, userID: userID),
                options: [.atomic, .completeFileProtection]
            )
            trimSpeechCache(in: directory)
        } catch {
            // Speech still plays when caching is unavailable.
        }
    }

    private var speechCacheRootDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("MaiaSpeech", isDirectory: true)
    }

    private func speechCacheDirectory(for userID: String) -> URL {
        speechCacheRootDirectory.appendingPathComponent(
            Self.cacheScopeIdentifier(for: userID),
            isDirectory: true
        )
    }

    private func speechCacheURL(for text: String, userID: String) -> URL {
        let digest = SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return speechCacheDirectory(for: userID).appendingPathComponent("\(digest).mp3")
    }

    private func removeLegacyUnscopedSpeechCache() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: speechCacheRootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in urls where url.pathExtension.lowercased() == "mp3" {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func trimSpeechCache(in directory: URL) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ), urls.count > maximumCachedSpeechFiles else {
            return
        }

        let sorted = urls.sorted {
            let left = try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let right = try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return (left ?? .distantPast) < (right ?? .distantPast)
        }
        for url in sorted.prefix(urls.count - maximumCachedSpeechFiles) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
