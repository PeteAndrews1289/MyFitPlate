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
    @Published public private(set) var playbackState: MaiaPlaybackState = .idle
    @Published public private(set) var sentenceIndex = 0
    @Published public private(set) var playbackRate: Double = 1
    @Published public private(set) var playbackNotice: String?
    private var speechPlan: MaiaSpeechPlan?
    private var usesLocalVoiceForCurrentPlan = false
    private var playbackOwnerID: String?
    private var activeUtterance: AVSpeechUtterance?
    private var audioObservers: [NSObjectProtocol] = []
    private let bookmarkScope = "maia-speech-bookmark-v1"
    public var sentenceCount: Int { speechPlan?.sentences.count ?? 0 }
    public var currentSentence: String? {
        guard let plan = speechPlan, plan.sentences.indices.contains(sentenceIndex) else { return nil }
        return plan.sentences[sentenceIndex]
    }
    private var selectedVoice: AVSpeechSynthesisVoice?
    private var fallbackVoice: AVSpeechSynthesisVoice?
    private var audioPlayer: AVAudioPlayer?
    private var speechTask: Task<Void, Never>?
    private var speechGeneration = UUID()
    private var consentObserver: NSObjectProtocol?
    private let environment: MaiaSpeechEnvironment
    static let maximumCacheAge: TimeInterval = 7 * 24 * 60 * 60

    public var selectedVoiceOption: MaiaVoiceOption? {
        availableVoices.first { $0.id == selectedVoiceIdentifier }
    }

    public var hasNaturalQualityVoice: Bool {
        selectedVoiceOption.map { $0.isOnline || $0.quality != .standard } ?? false
    }

    override convenience init() {
        self.init(environment: .live)
    }

    init(environment: MaiaSpeechEnvironment) {
        self.environment = environment
        super.init()
        self.speechSynthesizer.delegate = self
        #if os(iOS) || os(watchOS) || os(tvOS)
        self.speechSynthesizer.usesApplicationAudioSession = false
        #endif
        removeLegacyUnscopedSpeechCache()
        refreshAvailableVoices()
        installAudioObservers()
        consentObserver = NotificationCenter.default.addObserver(forName: .aiDataConsentChanged, object: nil, queue: .main) { [weak self] notification in
            guard let owner = notification.userInfo?["ownerID"] as? String else { return }
            Task { @MainActor [weak self] in
                guard let self, self.environment.currentOwner() == owner else { return }
                self.clearCachedSpeech(for: owner)
            }
        }
    }

    deinit {
        if let consentObserver { NotificationCenter.default.removeObserver(consentObserver) }
        audioObservers.forEach(NotificationCenter.default.removeObserver)
    }

    public func refreshAvailableVoices() {
        let systemVoices = AVSpeechSynthesisVoice.speechVoices()
        let systemOptions = Self.rankEligibleVoiceOptions(systemVoices.map(Self.option(from:)))
        let onlineEnabled = DIContainer.shared.featureFlagService?.boolValue(for: .maiaNaturalVoice)
            ?? FeatureFlag.maiaNaturalVoice.defaultValue
        let rankedOptions = (onlineEnabled ? [Self.onlineVoiceOption] : []) + systemOptions
        availableVoices = rankedOptions

        let scopedKey = environment.currentOwner().flatMap { AccountScopedStorageKey.make(prefix: selectedVoiceDefaultsKey, userID: $0) }
        if let scopedKey, environment.defaults.string(forKey: scopedKey) == nil,
           let legacy = environment.defaults.string(forKey: selectedVoiceDefaultsKey) {
            environment.defaults.set(legacy, forKey: scopedKey)
            environment.defaults.removeObject(forKey: selectedVoiceDefaultsKey)
        }
        let storedIdentifier = scopedKey.flatMap { environment.defaults.string(forKey: $0) }
        let preferredIdentifier = storedIdentifier.flatMap { identifier in
            rankedOptions.contains { $0.id == identifier } ? identifier : nil
        }
        selectedVoiceIdentifier = preferredIdentifier ?? rankedOptions.first?.id ?? ""
        fallbackVoice = systemOptions.first.flatMap { AVSpeechSynthesisVoice(identifier: $0.id) }
            ?? AVSpeechSynthesisVoice(language: "en-US")
        selectedVoice = selectedVoiceIdentifier == Self.onlineVoiceIdentifier
            ? nil
            : AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier) ?? fallbackVoice
        if let owner = environment.currentOwner() { pruneExpiredCache(in: speechCacheDirectory(for: owner)) }
    }

    public func selectVoice(identifier: String) {
        guard availableVoices.contains(where: { $0.id == identifier }) else { return }
        stopSpeaking()
        selectedVoiceIdentifier = identifier
        selectedVoice = identifier == Self.onlineVoiceIdentifier
            ? nil
            : AVSpeechSynthesisVoice(identifier: identifier) ?? fallbackVoice
        if let owner = environment.currentOwner(), let key = AccountScopedStorageKey.make(prefix: selectedVoiceDefaultsKey, userID: owner) {
            environment.defaults.set(identifier, forKey: key)
        }
    }

    public func previewSelectedVoice() {
        speak("Hi, I'm Maia. Let's look at your day and choose one practical next step.")
    }

    public func speak(_ text: String) {
        stopSpeaking()
        refreshAvailableVoices()
        let plan = MaiaSpeechPlan(source: text)
        guard !plan.sentences.isEmpty else { return }
        playbackOwnerID = environment.currentOwner()
        speechPlan = plan; currentSpokenText = plan.text; sentenceIndex = 0; playbackNotice = nil
        usesLocalVoiceForCurrentPlan = false
        playCurrentSentence()
    }

    public func pauseSpeaking() {
        guard ensurePlaybackOwner(), playbackState == .playing || playbackState == .preparing else { return }
        if playbackState == .preparing {
            speechGeneration = UUID(); speechTask?.cancel(); speechTask = nil
        }
        audioPlayer?.pause()
        if speechSynthesizer.isSpeaking { _ = speechSynthesizer.pauseSpeaking(at: .word) }
        playbackState = .paused; isSpeaking = false; mouthShape = "mouth_neutral"
        saveBookmark()
    }

    public func resumeSpeaking() {
        guard ensurePlaybackOwner(), playbackState == .paused, currentSentence != nil else { return }
        if let player = audioPlayer {
            if player.play() { playbackState = .playing; isSpeaking = true }
        } else if speechSynthesizer.isPaused {
            if speechSynthesizer.continueSpeaking() { playbackState = .playing; isSpeaking = true }
        } else { playCurrentSentence() }
    }

    public func seekSentence(_ index: Int) {
        guard ensurePlaybackOwner(), let plan = speechPlan, plan.sentences.indices.contains(index) else { return }
        let wasPlaying = playbackState != .paused
        stopEngines(); sentenceIndex = index
        if wasPlaying { playCurrentSentence() } else { playbackState = .paused; saveBookmark() }
    }

    public func setPlaybackRate(_ rate: Double) {
        guard ensurePlaybackOwner(), rate.isFinite else { return }
        playbackRate = min(1.5, max(0.75, rate))
        if let player = audioPlayer { player.rate = Float(playbackRate) } else if playbackState == .playing { seekSentence(sentenceIndex) }
        saveBookmark()
    }

    public func restorePlayback() {
        if playbackOwnerID != environment.currentOwner() { stopEngines(); finishSpeaking() }
        guard playbackState == .idle, let owner = environment.currentOwner(),
              let bookmark = try? environment.drafts.load(MaiaSpeechBookmark.self, userID: owner, scope: bookmarkScope)?.value else { return }
        guard bookmark.canResume(now: environment.now()) else {
            try? environment.drafts.remove(userID: owner, scope: bookmarkScope)
            return
        }
        refreshAvailableVoices()
        playbackOwnerID = owner
        speechPlan = bookmark.plan; currentSpokenText = bookmark.plan.text; sentenceIndex = bookmark.sentenceIndex
        playbackRate = bookmark.rate; playbackState = .paused; isSpeaking = false
        playbackNotice = "Ready to resume from the start of this sentence."
    }

    private func playCurrentSentence() {
        guard ensurePlaybackOwner(), let sentence = currentSentence else { finishSpeaking(); return }
        speechGeneration = UUID(); playbackState = .preparing; isSpeaking = true
        saveBookmark()
        if selectedVoiceIdentifier == Self.onlineVoiceIdentifier && !usesLocalVoiceForCurrentPlan { speakOnline(sentence) } else { speakWithSystemVoice(sentence) }
    }

    private func finishSentence() {
        guard ensurePlaybackOwner() else { return }
        audioPlayer = nil; activeUtterance = nil; speechTask = nil
        if sentenceIndex + 1 < sentenceCount { sentenceIndex += 1; playCurrentSentence() } else {
            if let owner = environment.currentOwner() { try? environment.drafts.remove(userID: owner, scope: bookmarkScope) }
            finishSpeaking()
        }
    }

    private func saveBookmark() {
        guard let owner = playbackOwnerID, owner == environment.currentOwner(), let plan = speechPlan, !plan.sentences.isEmpty else { return }
        do {
            try environment.drafts.save(MaiaSpeechBookmark(plan: plan, sentenceIndex: sentenceIndex,
                voiceIdentifier: selectedVoiceIdentifier, rate: playbackRate, now: environment.now()), userID: owner, scope: bookmarkScope)
        } catch { playbackNotice = "Playback works, but its position could not be saved on this device." }
    }

    private func installAudioObservers() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        audioObservers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor [weak self] in self?.pauseSpeaking(); self?.playbackNotice = "Audio was interrupted. Resume when ready." }
        })
        audioObservers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            Task { @MainActor [weak self] in self?.pauseSpeaking(); self?.playbackNotice = "Audio output changed. Resume when ready." }
        })
        #endif
    }

    private func speakWithSystemVoice(_ spokenText: String) {
        let utterance = AVSpeechUtterance(string: spokenText)
        utterance.voice = selectedVoice ?? fallbackVoice
        utterance.rate = (selectedVoiceOption?.language.hasPrefix("fr-") == true ? 0.46 : 0.49) * Float(playbackRate)
        utterance.pitchMultiplier = selectedVoiceOption?.gender == .female ? 1.02 : 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.04
        utterance.postUtteranceDelay = 0.08

        activeUtterance = utterance
        playbackState = .playing; isSpeaking = true
        self.speechSynthesizer.speak(utterance)
    }

    public func stopSpeaking() {
        let owner = playbackOwnerID
        stopEngines()
        if let owner { try? environment.drafts.remove(userID: owner, scope: bookmarkScope) }
        finishSpeaking()
    }

    private func ensurePlaybackOwner() -> Bool {
        guard playbackOwnerID == environment.currentOwner() else {
            stopEngines(); finishSpeaking()
            return false
        }
        return true
    }

    private func stopEngines() {
        speechGeneration = UUID(); speechTask?.cancel(); speechTask = nil
        audioPlayer?.stop(); audioPlayer = nil; activeUtterance = nil
        if speechSynthesizer.isSpeaking || speechSynthesizer.isPaused { speechSynthesizer.stopSpeaking(at: .immediate) }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        guard utterance === activeUtterance, ensurePlaybackOwner() else { return }
        isSpeaking = true; playbackState = .playing
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard utterance === activeUtterance, ensurePlaybackOwner() else { return }
        finishSentence()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard utterance === activeUtterance, ensurePlaybackOwner() else { return }
        finishSpeaking()
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === audioPlayer, ensurePlaybackOwner() else { return }
        if flag { finishSentence() } else { pauseSpeaking(); playbackNotice = "Playback was interrupted. Resume this sentence when ready." }
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
        currentSpokenText = nil; speechPlan = nil; playbackOwnerID = nil; sentenceIndex = 0; playbackState = .idle
    }

    private func speakOnline(_ spokenText: String) {
        guard let userID = environment.currentOwner(),
              let consent = environment.consent(userID) else {
            if environment.currentOwner() != nil {
                NotificationCenter.default.post(name: .aiDataConsentRequired, object: nil)
            }
            speakWithSystemVoice(spokenText)
            return
        }
        guard Self.canUseOnlineSpeech(spokenText) else {
            speakWithSystemVoice(spokenText)
            return
        }

        let lease = MaiaSpeechLease(ownerID: userID, consent: consent, generation: speechGeneration)
        isSpeaking = true
        speechTask = Task { [weak self] in
            guard let self else { return }
            do {
                try self.validate(lease)
                let data: Data
                if let cached = self.cachedAudioData(for: spokenText, userID: userID) {
                    data = cached
                } else {
                    let batch = self.speechPlan?.onlineBatch(startingAt: self.sentenceIndex) ?? [spokenText]
                    if let requestBatch = self.environment.requestBatch, batch.count > 1 {
                        let audio = try await requestBatch(batch)
                        try self.validate(lease)
                        guard audio.count == batch.count, audio.allSatisfy({ !$0.isEmpty }) else { throw APIError.noData }
                        for (text, chunk) in zip(batch, audio) {
                            try self.validate(lease)
                            self.cacheAudioData(chunk, for: text, userID: userID)
                        }
                        data = audio[0]
                    } else {
                        data = try await self.environment.request(spokenText)
                        // A cancelled request can still return. Fence cache creation as well as playback.
                        try self.validate(lease)
                        guard !data.isEmpty else { throw APIError.noData }
                        self.cacheAudioData(data, for: spokenText, userID: userID)
                    }
                }
                try self.validate(lease)
                guard self.currentSentence == spokenText else { return }
                if let playAudio = self.environment.playAudio {
                    guard playAudio(data) else { throw APIError.noData }
                    self.playbackState = .playing
                } else {
                    let player = try AVAudioPlayer(data: data)
                    player.delegate = self
                    player.enableRate = true; player.rate = Float(self.playbackRate)
                    self.audioPlayer = player
                    self.mouthShape = "mouth_open"
                    guard player.play() else { throw APIError.apiError("Audio playback could not start.") }
                    self.playbackState = .playing
                }
            } catch {
                guard (try? self.validate(lease)) != nil, self.currentSentence == spokenText else {
                    if self.speechGeneration == lease.generation { self.finishSpeaking() }
                    return
                }
                self.speechTask = nil
                self.usesLocalVoiceForCurrentPlan = true
                self.playbackNotice = "Using the installed voice for this reply; the online voice is unavailable."
                self.speakWithSystemVoice(spokenText)
            }
        }
    }

    private func validate(_ lease: MaiaSpeechLease) throws {
        try Task.checkCancellation()
        guard lease.allows(ownerID: environment.currentOwner(), consent: environment.consent(lease.ownerID),
                           generation: speechGeneration) else { throw CancellationError() }
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
        if playbackOwnerID == userID || environment.currentOwner() == nil { stopSpeaking() }
        try? FileManager.default.removeItem(at: speechCacheDirectory(for: userID))
        try? environment.drafts.remove(userID: userID, scope: bookmarkScope)
        removeLegacyUnscopedSpeechCache()
    }

    /// Checked, captured-owner deletion for a cleanup retry while another account may be active.
    public func removeCachedSpeech(for userID: String) throws {
        guard !userID.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
        let mayClearCurrentProjection = environment.currentOwner() == nil || environment.currentOwner() == userID
        if playbackOwnerID == userID || environment.currentOwner() == nil { stopSpeaking() }
        let directory = speechCacheDirectory(for: userID)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try environment.drafts.remove(userID: userID, scope: bookmarkScope)
        if mayClearCurrentProjection { removeLegacyUnscopedSpeechCache() }
    }

    private func cachedAudioData(for text: String, userID: String) -> Data? {
        let url = speechCacheURL(for: text, userID: userID)
        guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              environment.now().timeIntervalSince(modified) >= 0,
              environment.now().timeIntervalSince(modified) <= Self.maximumCacheAge else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private func cacheAudioData(_ data: Data, for text: String, userID: String) {
        let directory = speechCacheDirectory(for: userID)
        do {
            #if os(iOS) || os(watchOS) || os(tvOS)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            try data.write(
                to: speechCacheURL(for: text, userID: userID),
                options: [.atomic, .completeFileProtection]
            )
            #else
            // Match the Core host-file policy: macOS tools may not have access to the
            // complete-protection class. Keep host cache data private to its owner.
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let file = speechCacheURL(for: text, userID: userID)
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            #endif
            try? FileManager.default.setAttributes([.modificationDate: environment.now()], ofItemAtPath: speechCacheURL(for: text, userID: userID).path)
            trimSpeechCache(in: directory)
        } catch {
            // Speech still plays when caching is unavailable.
        }
    }

    private var speechCacheRootDirectory: URL {
        if let root = environment.cacheDirectory { return root }
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

    private func pruneExpiredCache(in directory: URL) {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        for url in urls where url.pathExtension == "mp3" {
            let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            guard let date else { try? FileManager.default.removeItem(at: url); continue }
            let age = environment.now().timeIntervalSince(date)
            if age < 0 || age > Self.maximumCacheAge { try? FileManager.default.removeItem(at: url) }
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
