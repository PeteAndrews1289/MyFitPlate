import XCTest
import AVFoundation
@testable import MyFitPlateCore

@MainActor
final class TTSManagerTests: XCTestCase {
    
    func testTTSManagerInit() {
        let manager = TTSManager()
        XCTAssertFalse(manager.isSpeaking)
        XCTAssertEqual(manager.mouthShape, "mouth_neutral")
    }
    
    func testSpeakAndStop() {
        let manager = TTSManager()
        manager.speak("Hello")
        
        manager.stopSpeaking()
        XCTAssertFalse(manager.isSpeaking)
        XCTAssertEqual(manager.mouthShape, "mouth_neutral")
    }
    
    func testDelegateDidStartAndFinish() {
        let manager = TTSManager()
        let utterance = AVSpeechUtterance(string: "Test")
        
        manager.speechSynthesizer(AVSpeechSynthesizer(), didStart: utterance)
        XCTAssertTrue(manager.isSpeaking)
        
        manager.speechSynthesizer(AVSpeechSynthesizer(), didFinish: utterance)
        XCTAssertFalse(manager.isSpeaking)
        XCTAssertEqual(manager.mouthShape, "mouth_neutral")
    }
    
    func testDelegateWillSpeakRangeOfSpeechString() {
        let manager = TTSManager()
        let text = "Hello you awesome person"
        let utterance = AVSpeechUtterance(string: text)
        
        // Test "you" which has 'o' and 'u'
        let range1 = NSRange(location: 6, length: 3)
        manager.speechSynthesizer(AVSpeechSynthesizer(), willSpeakRangeOfSpeechString: range1, utterance: utterance)
        XCTAssertEqual(manager.mouthShape, "mouth_o")
        
        // Test "awesome" which has 'a' and 'e'
        let range2 = NSRange(location: 10, length: 7)
        manager.speechSynthesizer(AVSpeechSynthesizer(), willSpeakRangeOfSpeechString: range2, utterance: utterance)
        XCTAssertEqual(manager.mouthShape, "mouth_o") // Contains w and o! wait, awesome has o and w, so mouth_o!
        
        // Let's test "a" only
        let text2 = "a cat"
        let utterance2 = AVSpeechUtterance(string: text2)
        manager.speechSynthesizer(AVSpeechSynthesizer(), willSpeakRangeOfSpeechString: NSRange(location: 2, length: 3), utterance: utterance2)
        XCTAssertEqual(manager.mouthShape, "mouth_open") // "cat" has a
        
        // Test neutral
        let text3 = "hmm"
        let utterance3 = AVSpeechUtterance(string: text3)
        manager.speechSynthesizer(AVSpeechSynthesizer(), willSpeakRangeOfSpeechString: NSRange(location: 0, length: 3), utterance: utterance3)
        XCTAssertEqual(manager.mouthShape, "mouth_neutral")
    }
}
