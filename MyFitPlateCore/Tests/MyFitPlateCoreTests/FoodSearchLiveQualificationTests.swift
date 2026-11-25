import XCTest
@testable import MyFitPlateCore

/// Explicit capture replay, never a network request in CI. The companion script records
/// public catalog responses; this test runs their projected parser fields through the
/// production parser, ranking, merge cap and visible-section rules.
final class FoodSearchLiveQualificationTests: XCTestCase {
    private struct Capture: Decodable {
        let id: String
        let query: String
        let category: String
        let targetBrand: String?
        let targetWords: [String]
        let provider: String
        let variant: String
        let status: Int?
        let elapsedMs: Double
        let payload: String?
    }

    func testReplayPublicCatalogCapturesWhenExplicitlyRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["MFP_FOOD_SEARCH_REPLAY"] else {
            throw XCTSkip("Opt-in live-capture replay: set MFP_FOOD_SEARCH_REPLAY to the companion script's replay.json; ordinary tests never contact providers.")
        }
        let captures = try JSONDecoder().decode([Capture].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertFalse(captures.isEmpty)
        var results: [[String: Any]] = []
        for capture in captures {
            var result: [String: Any] = ["id": capture.id, "query": capture.query, "category": capture.category,
                "provider": capture.provider, "variant": capture.variant, "request_ms": capture.elapsedMs]
            guard capture.status == 200, let payload = capture.payload else {
                result["outcome"] = "request_failed"; result["http_status"] = capture.status ?? 0
                results.append(result); continue
            }
            let started = ProcessInfo.processInfo.systemUptime
            let parsed: [FoodItem]
            do {
                parsed = capture.provider == "usda"
                    ? try USDAFoodParser.foodItems(from: Data(payload.utf8))
                    : try OpenFoodFactsParser.searchFoods(from: Data(payload.utf8))
            } catch {
                result["outcome"] = "parse_failed"; results.append(result); continue
            }
            let ranked = FoodSearchRanking.rankedRemoteMatches(query: capture.query, foods: parsed)
            let merged = FoodSearchRanking.mergedSearchResults(fatSecret: [],
                usda: capture.provider == "usda" ? ranked : [],
                openFoodFacts: capture.provider == "off" ? ranked : [], query: capture.query)
            let shown = FoodSearchRanking.searchPresentation(query: capture.query, trustedMatches: [], remoteMatches: merged, providersComplete: true)
            let visible = shown.brandedMatches + shown.otherRemoteMatches
            result["parse_rank_merge_ms"] = (ProcessInfo.processInfo.systemUptime - started) * 1_000
            result["returned_foods"] = parsed.count
            result["top5"] = visible.prefix(5).map { ["id": $0.id, "name": $0.name, "brand": $0.sourceMetadata?.brandName ?? ""] }
            let targeted = !["ambiguous", "negative"].contains(capture.category)
            if targeted {
                let present = parsed.contains { matches($0, capture) }
                let hit = visible.prefix(5).contains { matches($0, capture) }
                result["intended_candidate_in_response"] = present
                result["top5_hit"] = hit
                result["promoted_brand_family_mismatches"] = shown.brandedMatches.prefix(5).filter { !matches($0, capture) }.count
                result["outcome"] = hit ? "top5_hit" : present ? "present_below_top5" : parsed.isEmpty ? "empty_response" : "target_not_in_response_window"
            } else {
                result["outcome"] = capture.category == "negative" ? (parsed.isEmpty ? "negative_empty" : "negative_has_candidates") : "ambiguous_no_unique_target"
                result["promoted_branded_candidates"] = shown.brandedMatches.count
            }
            results.append(result)
        }
        let report: [String: Any] = [
            "scope": "Replay through production parser/ranker/provider merge cap/sections. Public captured catalog only; no FatSecret/HealthCanada merge, app rendering, personal records, GTIN verification or network speedup claim.",
            "matching": "Conservative predeclared brand/product-family word labels. Not a serving or exact GTIN identity test. Provider-window absence is not proof of database absence. Unsupported/ambiguous intents are reported separately.",
            "capture_count": captures.count,
            "results": results
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let output = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("swift-replay-report.json")
        try data.write(to: output, options: .atomic)
        print("WAVE4_LIVE_REPLAY " + String(decoding: try JSONSerialization.data(withJSONObject: ["captures": captures.count, "report": output.path]), as: UTF8.self))
        XCTAssertEqual(results.count, captures.count)
    }

    private func matches(_ food: FoodItem, _ capture: Capture) -> Bool {
        let normalizedName = normalized(food.name)
        let nameWords = normalizedName.split(separator: " ").map(String.init)
        if let brand = capture.targetBrand {
            let wanted = " " + normalized(brand) + " "
            let reported = " " + normalized(food.sourceMetadata?.brandName ?? "") + " "
            guard reported.contains(wanted) || (" " + normalizedName + " ").contains(wanted) else { return false }
        }
        let required = capture.targetWords.flatMap { normalized($0).split(separator: " ").map(String.init) }
        return required.allSatisfy { term in nameWords.contains { word in
            word == term || word == term + "s" || word == term + "es" || term == word + "s" || term == word + "es"
        } }
    }

    private func normalized(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
        let cleaned = String(folded.map { $0.isLetter || $0.isNumber ? $0 : Character(" ") })
        return cleaned.split(separator: " ").joined(separator: " ")
    }
}
