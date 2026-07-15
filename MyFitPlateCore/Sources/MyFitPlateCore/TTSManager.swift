import Foundation
import AVFoundation

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
        "\(name) · \(accentLabel) · \(quality.label)"
    }

    public init(
        id: String,
        name: String,
        language: String,
        quality: Quality,
        gender: Gender = .unspecified,
        isNovelty: Bool = false,
        isPersonal: Bool = false
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.quality = quality
        self.gender = gender
        self.isNovelty = isNovelty
        self.isPersonal = isPersonal
    }
}

@MainActor
public class TTSManager: NSObject, ObservableObject, @preconcurrency AVSpeechSynthesizerDelegate {
    public static let shared = TTSManager()

    private let speechSynthesizer = AVSpeechSynthesizer()
    private let selectedVoiceDefaultsKey = "maiaSpokenVoiceIdentifier"
    @Published public var isSpeaking: Bool = false
    @Published public var mouthShape: String = "mouth_neutral"
    @Published public private(set) var availableVoices: [MaiaVoiceOption] = []
    @Published public private(set) var selectedVoiceIdentifier: String = ""
    @Published public private(set) var currentSpokenText: String?
    private var selectedVoice: AVSpeechSynthesisVoice?

    public var selectedVoiceOption: MaiaVoiceOption? {
        availableVoices.first { $0.id == selectedVoiceIdentifier }
    }

    public var hasNaturalQualityVoice: Bool {
        selectedVoiceOption.map { $0.quality != .standard } ?? false
    }

    override init() {
        super.init()
        self.speechSynthesizer.delegate = self
        #if os(iOS) || os(watchOS) || os(tvOS)
        self.speechSynthesizer.usesApplicationAudioSession = false
        #endif
        refreshAvailableVoices()
    }

    public func refreshAvailableVoices() {
        let systemVoices = AVSpeechSynthesisVoice.speechVoices()
        let rankedOptions = Self.rankEligibleVoiceOptions(systemVoices.map(Self.option(from:)))
        availableVoices = rankedOptions

        let storedIdentifier = UserDefaults.standard.string(forKey: selectedVoiceDefaultsKey)
        let preferredIdentifier = storedIdentifier.flatMap { identifier in
            rankedOptions.contains { $0.id == identifier } ? identifier : nil
        }
        selectedVoiceIdentifier = preferredIdentifier ?? rankedOptions.first?.id ?? ""
        selectedVoice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    public func selectVoice(identifier: String) {
        guard availableVoices.contains(where: { $0.id == identifier }),
              let voice = AVSpeechSynthesisVoice(identifier: identifier) else { return }
        stopSpeaking()
        selectedVoiceIdentifier = identifier
        selectedVoice = voice
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

        let utterance = AVSpeechUtterance(string: spokenText)
        utterance.voice = selectedVoice
        utterance.rate = selectedVoiceOption?.language.hasPrefix("fr-") == true ? 0.46 : 0.49
        utterance.pitchMultiplier = selectedVoiceOption?.gender == .female ? 1.02 : 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.04
        utterance.postUtteranceDelay = 0.08

        self.speechSynthesizer.speak(utterance)
    }

    public func stopSpeaking() {
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
        isSpeaking = false
        mouthShape = "mouth_neutral"
        currentSpokenText = nil
    }
}
