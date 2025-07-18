import Foundation
import AVFoundation

class TTSManager: NSObject, ObservableObject {
    static let shared = TTSManager()

    private var audioPlayer: AVAudioPlayer?
    private let fallbackSynth = AVSpeechSynthesizer()
    @Published var isSpeaking: Bool = false

    override init() {
        super.init()
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("❌ Failed to set up audio session: \(error.localizedDescription)")
        }
    }
    
    func speak(_ text: String) {
        stopSpeaking()
        isSpeaking = true
        
        speakWithGoogle(text: text) { [weak self] success in
            guard let self = self else { return }
            if !success {
                self.speakWithAVSpeech(text)
            }
            let estimatedDuration = Double(text.count) * 0.06
            DispatchQueue.main.asyncAfter(deadline: .now() + estimatedDuration) {
                 if self.isSpeaking { self.isSpeaking = false }
            }
        }
    }

    func stopSpeaking() {
        if audioPlayer?.isPlaying ?? false {
            audioPlayer?.stop()
        }
        if fallbackSynth.isSpeaking {
            fallbackSynth.stopSpeaking(at: .immediate)
        }
        if isSpeaking {
             isSpeaking = false
        }
    }

    private func speakWithGoogle(text: String, completion: @escaping (Bool) -> Void) {
        let apiKey = getAPIKey()
        guard !apiKey.isEmpty, apiKey != "YOUR_API_KEY" else {
            completion(false)
            return
        }
        
        let url = URL(string: "https://texttospeech.googleapis.com/v1/text:synthesize?key=\(apiKey)")!

        let body: [String: Any] = [
            "input": ["text": text],
            "voice": ["languageCode": "en-US", "name": "en-US-Neural2-F"],
            "audioConfig": ["audioEncoding": "MP3"]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                DispatchQueue.main.async { completion(false) }
                return
            }
            guard let data = data,
                  let response = try? JSONDecoder().decode(GoogleTTSResponse.self, from: data),
                  let audioData = Data(base64Encoded: response.audioContent) else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            DispatchQueue.main.async {
                self.play(audioData)
                completion(true)
            }
        }.resume()
    }

    private func speakWithAVSpeech(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        fallbackSynth.speak(utterance)
    }

    private func play(_ data: Data) {
        do {
            self.audioPlayer = try AVAudioPlayer(data: data)
            self.audioPlayer?.play()
        } catch {
            DispatchQueue.main.async {
                self.isSpeaking = false
            }
        }
    }
}

struct GoogleTTSResponse: Codable {
    let audioContent: String
}