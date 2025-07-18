import Foundation
import AVFoundation

class TTSManager: NSObject {
    static let shared = TTSManager()

    private var audioPlayer: AVAudioPlayer?
    private let fallbackSynth = AVSpeechSynthesizer()

    func speak(_ text: String) {
        speakWithGoogle(text: text) { success in
            if !success {
                self.speakWithAVSpeech(text)
            }
        }
    }

    func stopSpeaking() {
        audioPlayer?.stop()
        fallbackSynth.stopSpeaking(at: .immediate)
    }

    private func speakWithGoogle(text: String, completion: @escaping (Bool) -> Void) {
        guard let apiKey = getGoogleTTSKey() else {
            completion(false)
            return
        }

        let url = URL(string: "https://texttospeech.googleapis.com/v1/text:synthesize?key=\(apiKey)")!

        let body: [String: Any] = [
            "input": ["text": text],
            "voice": [
                "languageCode": "en-US",
                "name": "en-US-Neural2-F"
            ],
            "audioConfig": ["audioEncoding": "MP3"]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                print("❌ Google TTS error: \(error.localizedDescription)")
                completion(false)
                return
            }

            guard let data = data,
                  let response = try? JSONDecoder().decode(GoogleTTSResponse.self, from: data),
                  let audioData = Data(base64Encoded: response.audioContent) else {
                print("❌ Failed to decode TTS response")
                completion(false)
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
        utterance.rate = 0.45
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        fallbackSynth.speak(utterance)
    }

    private func play(_ data: Data) {
        do {
            self.audioPlayer = try AVAudioPlayer(data: data)
            self.audioPlayer?.prepareToPlay()
            self.audioPlayer?.play()
        } catch {
            print("🎵 Audio error: \(error.localizedDescription)")
        }
    }

    private func getGoogleTTSKey() -> String? {
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let key = dict["GOOGLE_TTS_API_KEY"] as? String {
            return key
        }
        return nil
    }
}

struct GoogleTTSResponse: Codable {
    let audioContent: String
}
