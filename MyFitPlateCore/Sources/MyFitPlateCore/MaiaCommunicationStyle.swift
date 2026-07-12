import Foundation

public enum MaiaConversationStyle {
    public static func promptInstructions(for preference: String?) -> String {
        let tone = preference?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return """
        Natural conversation rules:
        - Answer the user's actual question in the first sentence. Do not open with canned phrases such as "Absolutely," "Great question," "Based on your data," or "Here's a breakdown."
        - Sound like a knowledgeable coach in a real conversation: use contractions, vary sentence openings, and prefer plain language. Never claim to be human, have feelings, or have personal experience.
        - Use the shortest natural answer that solves the request, usually one to three short paragraphs. Use bullets only when the user asks for a list or when three or more genuinely separate choices need comparison.
        - Mention only the logged numbers that change the recommendation. Do not recite the dashboard back to the user.
        - Give one clear next step. Avoid generic praise, repeated encouragement, filler transitions, and a closing question unless an answer is actually needed.
        - Keep visible prose easy to read aloud: avoid slash-heavy shorthand, unexplained abbreviations, excessive parentheses, and robotic headings.
        \(toneInstruction(for: tone))
        """
    }

    private static func toneInstruction(for tone: String?) -> String {
        switch tone {
        case "coach":
            return "Tone preference: Coach. Be energetic and decisive, but never use hype, guilt, or forced cheerleading."
        case "analyst":
            return "Tone preference: Analyst. Lead with the decision, then give the one or two data points that justify it without turning the answer into a report."
        default:
            return "Tone preference: Balanced. Be calm, direct, and encouraging without sounding formal or overly enthusiastic."
        }
    }
}

public enum MaiaSpeechFormatter {
    public static func spokenText(from source: String) -> String {
        var text = source

        text = replacing(
            pattern: "```(?:json)?\\s*.*?```",
            in: text,
            with: "",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        text = replacing(
            pattern: "\\{\\s*\"type\"\\s*:.*\\}\\s*$",
            in: text,
            with: "",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        text = replacing(pattern: "!\\[([^]]*)\\]\\([^)]*\\)", in: text, with: "$1")
        text = replacing(pattern: "\\[([^]]+)\\]\\([^)]*\\)", in: text, with: "$1")
        text = replacing(pattern: "<[^>]+>", in: text, with: " ")
        text = replacing(pattern: "^\\s{0,3}#{1,6}\\s+", in: text, with: "", options: [.anchorsMatchLines])
        text = replacing(pattern: "^\\s*>\\s?", in: text, with: "", options: [.anchorsMatchLines])
        text = replacing(pattern: "^\\s*[-*+]\\s+", in: text, with: "", options: [.anchorsMatchLines])
        text = replacing(pattern: "^\\s*\\d+[.)]\\s+", in: text, with: "", options: [.anchorsMatchLines])

        text = expandUnits(in: text)
        text = text.replacingOccurrences(of: "&", with: " and ")
        text = text.replacingOccurrences(of: "\u{2014}", with: ", ")
        text = text.replacingOccurrences(of: "\u{2013}", with: ", ")
        text = replacing(pattern: "[*_~`]", in: text, with: "")
        text = removingEmojiPresentation(from: text)

        return joinedForSpeech(text)
    }

    private static func expandUnits(in source: String) -> String {
        var text = source
        let replacements: [(String, String)] = [
            ("(?i)\\b1(?:\\.0+)?\\s*kcal\\b", "1 calorie"),
            ("(?i)\\b([0-9][0-9,.]*)\\s*kcal\\b", "$1 calories"),
            ("(?i)\\b1(?:\\.0+)?\\s*cal\\b", "1 calorie"),
            ("(?i)\\b([0-9][0-9,.]*)\\s*cal\\b", "$1 calories"),
            ("(?i)\\b1(?:\\.0+)?\\s*(?:mcg|\u{00B5}g)\\b", "1 microgram"),
            ("(?i)\\b([0-9][0-9,.]*)\\s*(?:mcg|\u{00B5}g)\\b", "$1 micrograms"),
            ("(?i)\\b1(?:\\.0+)?\\s*mg\\b", "1 milligram"),
            ("(?i)\\b([0-9][0-9,.]*)\\s*mg\\b", "$1 milligrams"),
            ("(?i)\\b1(?:\\.0+)?\\s*kg\\b", "1 kilogram"),
            ("(?i)\\b([0-9][0-9,.]*)\\s*kg\\b", "$1 kilograms"),
            ("(?i)\\b1(?:\\.0+)?\\s*oz\\b", "1 ounce"),
            ("(?i)\\b([0-9][0-9,.]*)\\s*oz\\b", "$1 ounces"),
            ("(?i)\\b1(?:\\.0+)?\\s*lbs?\\b", "1 pound"),
            ("(?i)\\b([0-9][0-9,.]*)\\s*lbs?\\b", "$1 pounds"),
            ("(?i)\\b1(?:\\.0+)?\\s*g\\b", "1 gram"),
            ("(?i)\\b([0-9][0-9,.]*)\\s*g\\b", "$1 grams"),
            ("(?i)\\bRPE\\b", "R P E"),
            ("(?i)\\bRIR\\b", "R I R"),
            ("(?i)\\bHR\\b", "heart rate"),
            ("%", " percent")
        ]

        for (pattern, replacement) in replacements {
            text = replacing(pattern: pattern, in: text, with: replacement)
        }
        return text
    }

    private static func joinedForSpeech(_ source: String) -> String {
        let lines = source
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var result = ""
        for line in lines {
            guard !line.isEmpty else { continue }
            if !result.isEmpty {
                let finalCharacter = result.last
                let hasPause = finalCharacter.map { ".!?,:;".contains($0) } ?? false
                result += hasPause ? " " : ". "
            }
            result += line
        }

        return replacing(pattern: "\\s+", in: result, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removingEmojiPresentation(from source: String) -> String {
        let scalars = source.unicodeScalars.filter { scalar in
            !scalar.properties.isEmojiPresentation && scalar.value != 0xFE0F
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func replacing(
        pattern: String,
        in source: String,
        with replacement: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return source
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.stringByReplacingMatches(in: source, range: range, withTemplate: replacement)
    }
}
