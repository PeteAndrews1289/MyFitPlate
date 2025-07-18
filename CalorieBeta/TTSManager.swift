import Foundation
import AVFoundation

class TTSManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = TTSManager()

    private let speechSynthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking: Bool = false
    @Published var mouthShape: String = "mouth_neutral"
    private var bestVoice: AVSpeechSynthesisVoice?

    override init() {
        super.init()
        self.speechSynthesizer.delegate = self
        self.bestVoice = findBestVoice()
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("❌ Failed to set up audio session: \(error.localizedDescription)")
        }
    }
    
    private func findBestVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        
        let premiumVoices = voices.filter { $0.language == "en-US" && $0.quality == .premium }
        if let voice = premiumVoices.first { return voice }
        
        let enhancedVoices = voices.filter { $0.language == "en-US" && $0.quality == .enhanced }
        if let voice = enhancedVoices.first { return voice }

        return AVSpeechSynthesisVoice(language: "en-US")
    }
    
    func speak(_ text: String) {
        stopSpeaking()
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = self.bestVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        
        self.speechSynthesizer.speak(utterance)
    }

    func stopSpeaking() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.mouthShape = "mouth_neutral"
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = true
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.mouthShape = "mouth_neutral"
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let word = (utterance.speechString as NSString).substring(with: characterRange).lowercased()
        
        DispatchQueue.main.async {
            if word.contains("o") || word.contains("u") || word.contains("w") {
                self.mouthShape = "mouth_o"
            } else if word.contains("a") || word.contains("e") || word.contains("i") {
                self.mouthShape = "mouth_open"
            } else {
                self.mouthShape = "mouth_neutral"
            }
        }
    }
}
