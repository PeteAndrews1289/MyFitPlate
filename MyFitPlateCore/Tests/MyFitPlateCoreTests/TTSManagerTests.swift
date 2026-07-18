import XCTest
import AVFoundation
@testable import MyFitPlateCore

@MainActor
final class TTSManagerTests: XCTestCase {
    
    func testTTSManagerInit() {
        let manager = TTSManager()
        XCTAssertFalse(manager.isSpeaking)
        XCTAssertEqual(manager.mouthShape, "mouth_neutral")
        XCTAssertNil(manager.currentSpokenText)
    }
    
    func testSpeakAndStop() {
        let manager = TTSManager()
        manager.speak("Hello")
        XCTAssertEqual(manager.currentSpokenText, "Hello")
        
        manager.stopSpeaking()
        XCTAssertFalse(manager.isSpeaking)
        XCTAssertEqual(manager.mouthShape, "mouth_neutral")
        XCTAssertNil(manager.currentSpokenText)
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

    func testDelegateDidCancelResetsSpeakingState() {
        let manager = TTSManager()
        let utterance = AVSpeechUtterance(string: "Test")

        manager.speechSynthesizer(AVSpeechSynthesizer(), didStart: utterance)
        manager.speechSynthesizer(AVSpeechSynthesizer(), didCancel: utterance)

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

    func testSpeechFormatterRemovesActionPayloadAndMarkdown() {
        let source = """
        ## A simple next step
        **Greek yogurt** gives you 25g protein and about 220 cal.

        ```json
        {
          "type": "meal_suggestion",
          "mealName": "Greek yogurt"
        }
        ```
        """

        XCTAssertEqual(
            MaiaSpeechFormatter.spokenText(from: source),
            "A simple next step. Greek yogurt gives you 25 grams protein and about 220 calories."
        )
    }

    func testSpeechFormatterMakesCommonCoachingShorthandSpeakable() {
        let source = """
        - Keep HR easy.
        - Use RPE 6\u{2013}7 for 30 min.
        - Drink 16 oz & aim for 75%.
        """

        XCTAssertEqual(
            MaiaSpeechFormatter.spokenText(from: source),
            "Keep heart rate easy. Use R P E 6, 7 for 30 min. Drink 16 ounces and aim for 75 percent."
        )
    }

    func testSpeechFormatterReturnsEmptyForActionOnlyResponse() {
        let source = """
        ```json
        {
          "type": "log_water",
          "amountOunces": 16
        }
        ```
        """

        XCTAssertTrue(MaiaSpeechFormatter.spokenText(from: source).isEmpty)
    }

    func testVoiceRankingPrefersNaturalFemaleVoiceAndRejectsUnsafeTraits() {
        let options = [
            MaiaVoiceOption(
                id: "novelty",
                name: "Novelty",
                language: "en-US",
                quality: .premium,
                gender: .female,
                isNovelty: true
            ),
            MaiaVoiceOption(
                id: "male-premium",
                name: "Aaron",
                language: "en-US",
                quality: .premium,
                gender: .male
            ),
            MaiaVoiceOption(
                id: "ava-premium",
                name: "Ava",
                language: "en-US",
                quality: .premium,
                gender: .female
            ),
            MaiaVoiceOption(
                id: "samantha-enhanced",
                name: "Samantha",
                language: "en-US",
                quality: .enhanced,
                gender: .female
            ),
            MaiaVoiceOption(
                id: "personal",
                name: "Personal",
                language: "en-US",
                quality: .premium,
                gender: .female,
                isPersonal: true
            ),
            MaiaVoiceOption(
                id: "australian",
                name: "Karen",
                language: "en-AU",
                quality: .premium,
                gender: .female
            ),
            MaiaVoiceOption(
                id: "french-enhanced",
                name: "Audrey",
                language: "fr-FR",
                quality: .enhanced,
                gender: .female
            )
        ]

        XCTAssertEqual(
            TTSManager.rankEligibleVoiceOptions(options).map(\.id),
            ["ava-premium", "australian", "male-premium", "samantha-enhanced", "french-enhanced"]
        )
    }

    func testOnlineVoiceUsesExplicitNaturalLabel() {
        let option = MaiaVoiceOption(
            id: TTSManager.onlineVoiceIdentifier,
            name: "Maia Natural",
            language: "en-US",
            quality: .premium,
            gender: .female,
            isOnline: true
        )

        XCTAssertEqual(option.pickerLabel, "Maia Natural · Online · Natural")
        XCTAssertTrue(option.isOnline)
    }

    func testOnlineSpeechNeverSilentlyTruncatesLongResponses() {
        XCTAssertTrue(TTSManager.canUseOnlineSpeech(String(repeating: "a", count: 1_800)))
        XCTAssertFalse(TTSManager.canUseOnlineSpeech(String(repeating: "a", count: 1_801)))
        XCTAssertFalse(TTSManager.canUseOnlineSpeech(String(repeating: "🙂", count: 901)))
    }

    func testSpeechCacheScopeIsHashedAndAccountSpecific() {
        let first = TTSManager.cacheScopeIdentifier(for: "user-one@example.com")
        let second = TTSManager.cacheScopeIdentifier(for: "user-two@example.com")

        XCTAssertEqual(first.count, 64)
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(first.contains("user-one"))
    }

    func testConversationStyleExplainsEachToneWithoutCannedOpeners() {
        let balanced = MaiaConversationStyle.promptInstructions(for: "Balanced")
        let coach = MaiaConversationStyle.promptInstructions(for: "Coach")
        let analyst = MaiaConversationStyle.promptInstructions(for: "Analyst")

        XCTAssertTrue(balanced.contains("calm, direct"))
        XCTAssertTrue(coach.contains("never use hype"))
        XCTAssertTrue(analyst.contains("Lead with the decision"))
        XCTAssertTrue(balanced.contains("Do not open with canned phrases"))
    }
}
