import XCTest
@testable import MyFitPlateCore

/// A repeatable local ranking/compute corpus: 40 authored catalog identities and five
/// explicit query forms each. Nutrition values are fixtures, not product-label data.
/// This does not measure live-provider coverage, network latency or typo correction.
final class FoodSearchBenchmarkTests: XCTestCase {
    private struct Product {
        let brand: String
        let name: String
        let queries: [String]
    }

    func testTwoHundredCatalogQueriesRetainIntendedTopFiveMatchAndReportComputeTimes() throws {
        let products = corpus
        XCTAssertEqual(products.count, 40)
        XCTAssertEqual(products.flatMap(\.queries).count, 200)
        let branded = products.enumerated().map { index, product in
            FoodItem(id: "product-\(index)", name: product.name, calories: 100)
                .withDatabaseSource(.fatSecret, sourceName: "Fixture catalog", brandName: product.brand)
        }
        let generic = products.enumerated().map { index, product in
            FoodItem(id: "generic-\(index)", name: product.name, calories: 100)
                .withDatabaseSource(.usda, sourceName: "Fixture generic catalog")
        }
        let catalog = Array(generic.reversed()) + Array(branded.reversed())
        var remoteHits = 0, localHits = 0
        var remoteTimes: [Double] = [], localTimes: [Double] = [], cacheTimes: [Double] = []
        var failures: [String] = []
        var cache = FoodSearchResultCache()
        for (index, product) in products.enumerated() {
            let expected = "product-\(index)"
            for query in product.queries {
                let remoteStart = ProcessInfo.processInfo.systemUptime
                let remote = FoodSearchRanking.rankedRemoteMatches(query: query, foods: catalog)
                remoteTimes.append((ProcessInfo.processInfo.systemUptime - remoteStart) * 1_000)
                if remote.prefix(5).contains(where: { $0.id == expected }) { remoteHits += 1 }
                else { failures.append("Remote: \(query) → \(expected)") }
                let localStart = ProcessInfo.processInfo.systemUptime
                let local = FoodSearchRanking.trustedLocalMatches(query: query, savedFoods: branded, recentFoods: generic)
                localTimes.append((ProcessInfo.processInfo.systemUptime - localStart) * 1_000)
                if local.prefix(5).contains(where: { $0.id == expected }) { localHits += 1 }
                else { failures.append("Local: \(query) → \(expected)") }
                cache.store(remote, for: query, provider: .fatSecret)
                let cacheStart = ProcessInfo.processInfo.systemUptime
                let restored = cache.batches(for: query)
                cacheTimes.append((ProcessInfo.processInfo.systemUptime - cacheStart) * 1_000)
                XCTAssertEqual(restored[.fatSecret]?.map(\.id), remote.map(\.id))
            }
        }
        let report: [String: Any] = [
            "scope": "Synthetic local computation; 40 products, 200 authored query forms, 80 candidates. No live provider/network claim.",
            "queries": 200, "remote_top5": remoteHits, "personal_top5": localHits,
            "remote_p50_ms": percentile(remoteTimes, 0.5), "remote_p95_ms": percentile(remoteTimes, 0.95),
            "personal_p50_ms": percentile(localTimes, 0.5), "personal_p95_ms": percentile(localTimes, 0.95),
            "cache_p50_ms": percentile(cacheTimes, 0.5), "cache_p95_ms": percentile(cacheTimes, 0.95),
            "failures": failures
        ]
        let encoded = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print("WAVE4_FOOD_BENCHMARK " + String(decoding: encoded, as: UTF8.self))
        XCTAssertGreaterThanOrEqual(remoteHits, 190, failures.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(localHits, 190, failures.joined(separator: "\n"))
    }

    private func percentile(_ values: [Double], _ fraction: Double) -> Double {
        let sorted = values.sorted()
        return sorted[max(0, min(sorted.count - 1, Int(ceil(Double(sorted.count) * fraction)) - 1))]
    }

    private var corpus: [Product] { [
        Product(brand: "Chobani", name: "Plain Greek Yogurt", queries: ["chobani", "chobani greek yogurt", "plain greek yogurt", "CHOBANI plain", "greek yog"]),
        Product(brand: "Fage", name: "Total 2% Greek Yogurt", queries: ["fage", "fage total", "2% greek yogurt", "FAGE yogurt", "total 2 greek yog"]),
        Product(brand: "Oikos", name: "Triple Zero Vanilla Yogurt", queries: ["oikos", "triple zero", "oikos vanilla yogurt", "VANILLA OIKOS", "triple zero yog"]),
        Product(brand: "Siggi's", name: "Plain Skyr Yogurt", queries: ["siggi's", "plain skyr", "skyr yogurt", "SIGGI'S plain", "skyr yog"]),
        Product(brand: "Fairlife", name: "2% Reduced Fat Milk", queries: ["fairlife", "fairlife 2%", "reduced fat milk", "FAIRLIFE milk", "2 reduced fat mil"]),
        Product(brand: "Horizon", name: "Organic Whole Milk", queries: ["horizon", "organic whole milk", "horizon milk", "WHOLE HORIZON", "organic whole mil"]),
        Product(brand: "Oatly", name: "Original Oat Milk", queries: ["oatly", "original oat milk", "oatly milk", "OATLY original", "original oat mil"]),
        Product(brand: "Almond Breeze", name: "Unsweetened Almond Milk", queries: ["almond breeze", "unsweetened almond milk", "breeze milk", "ALMOND BREEZE milk", "unsweetened almond mil"]),
        Product(brand: "Quaker", name: "Old Fashioned Oats", queries: ["quaker", "old fashioned oats", "quaker oat", "OATS QUAKER", "old fashioned oa"]),
        Product(brand: "Cheerios", name: "Original Cereal", queries: ["cheerios", "cheerios cereal", "original cereal", "CEREAL CHEERIOS", "cheerios cer"]),
        Product(brand: "Kashi", name: "Go Crunch Cereal", queries: ["kashi", "go crunch", "kashi cereal", "CRUNCH KASHI", "go crunch cer"]),
        Product(brand: "Kodiak", name: "Buttermilk Power Cakes", queries: ["kodiak", "power cakes", "buttermilk kodiak", "KODIAK cakes", "buttermilk power ca"]),
        Product(brand: "Dave's Killer Bread", name: "21 Whole Grains Bread", queries: ["dave's killer", "21 whole grains", "killer bread", "DAVE'S bread", "21 whole grains bre"]),
        Product(brand: "Ezekiel", name: "Sprouted Whole Grain Bread", queries: ["ezekiel", "sprouted whole grain", "ezekiel bread", "SPROUTED EZEKIEL", "sprouted whole grain bre"]),
        Product(brand: "Mission", name: "Carb Balance Tortilla", queries: ["mission", "carb balance", "mission tortillas", "BALANCE MISSION", "carb balance tor"]),
        Product(brand: "Thomas", name: "Whole Wheat English Muffin", queries: ["thomas", "whole wheat english muffin", "thomas muffins", "ENGLISH THOMAS", "whole wheat english muf"]),
        Product(brand: "Jif", name: "Creamy Peanut Butter", queries: ["jif", "creamy peanut butter", "jif peanut", "BUTTER JIF", "creamy peanut but"]),
        Product(brand: "Skippy", name: "Natural Peanut Butter", queries: ["skippy", "natural peanut butter", "skippy peanut", "BUTTER SKIPPY", "natural peanut but"]),
        Product(brand: "Justin's", name: "Almond Butter", queries: ["justin's", "almond butter", "justin's almond", "BUTTER JUSTIN'S", "almond but"]),
        Product(brand: "Smucker's", name: "Strawberry Fruit Spread", queries: ["smucker's", "strawberry fruit spread", "smucker's strawberry", "SPREAD SMUCKER'S", "strawberry fruit spr"]),
        Product(brand: "Quest", name: "Chocolate Brownie Protein Bar", queries: ["quest", "chocolate brownie", "quest protein bar", "BROWNIE QUEST", "chocolate brownie protein ba"]),
        Product(brand: "RXBAR", name: "Chocolate Sea Salt Protein Bar", queries: ["rxbar", "chocolate sea salt", "rxbar protein bar", "SEA SALT RXBAR", "chocolate sea salt protein ba"]),
        Product(brand: "KIND", name: "Dark Chocolate Nut Bar", queries: ["kind", "dark chocolate nut", "kind chocolate bar", "NUT KIND", "dark chocolate nut ba"]),
        Product(brand: "Clif", name: "Crunchy Peanut Butter Energy Bar", queries: ["clif", "crunchy peanut butter", "clif energy bar", "ENERGY CLIF", "crunchy peanut butter energy ba"]),
        Product(brand: "Optimum Nutrition", name: "Gold Standard Whey", queries: ["optimum nutrition", "gold standard whey", "optimum whey", "WHEY OPTIMUM", "gold standard wh"]),
        Product(brand: "Premier Protein", name: "Chocolate Protein Shake", queries: ["premier protein", "premier chocolate", "chocolate protein shake", "SHAKE PREMIER", "premier protein sha"]),
        Product(brand: "Muscle Milk", name: "Vanilla Protein Shake", queries: ["muscle milk", "vanilla protein shake", "muscle vanilla", "SHAKE MUSCLE", "muscle milk sha"]),
        Product(brand: "Ensure", name: "Max Protein Chocolate Shake", queries: ["ensure", "max protein chocolate", "ensure chocolate shake", "SHAKE ENSURE", "max protein chocolate sha"]),
        Product(brand: "Tyson", name: "Grilled Chicken Breast", queries: ["tyson", "grilled chicken breast", "tyson chicken", "BREAST TYSON", "grilled chicken bre"]),
        Product(brand: "Applegate", name: "Oven Roasted Turkey Breast", queries: ["applegate", "oven roasted turkey", "applegate turkey", "BREAST APPLEGATE", "oven roasted turkey bre"]),
        Product(brand: "StarKist", name: "Chunk Light Tuna", queries: ["starkist", "chunk light tuna", "starkist tuna", "TUNA STARKIST", "chunk light tu"]),
        Product(brand: "Bumble Bee", name: "Wild Pink Salmon", queries: ["bumble bee", "wild pink salmon", "bumble salmon", "SALMON BUMBLE", "wild pink sal"]),
        Product(brand: "Ben's Original", name: "Ready Jasmine Rice", queries: ["ben's original", "ready jasmine rice", "ben's rice", "JASMINE BEN'S", "ready jasmine ri"]),
        Product(brand: "Seeds of Change", name: "Brown Rice Quinoa", queries: ["seeds of change", "brown rice quinoa", "seeds quinoa", "QUINOA CHANGE", "brown rice qui"]),
        Product(brand: "Barilla", name: "Whole Grain Penne", queries: ["barilla", "whole grain penne", "barilla penne", "PENNE BARILLA", "whole grain pen"]),
        Product(brand: "Banza", name: "Chickpea Rotini", queries: ["banza", "chickpea rotini", "banza chickpea", "ROTINI BANZA", "chickpea rot"]),
        Product(brand: "Dole", name: "Pineapple Chunks", queries: ["dole", "pineapple chunks", "dole pineapple", "CHUNKS DOLE", "pineapple chu"]),
        Product(brand: "Mott's", name: "Unsweetened Applesauce", queries: ["mott's", "unsweetened applesauce", "mott's applesauce", "APPLESAUCE MOTT'S", "unsweetened apple"]),
        Product(brand: "Birds Eye", name: "Steamfresh Broccoli", queries: ["birds eye", "steamfresh broccoli", "birds broccoli", "BROCCOLI EYE", "steamfresh bro"]),
        Product(brand: "Green Giant", name: "Sweet Corn", queries: ["green giant", "sweet corn", "giant corn", "CORN GREEN", "sweet cor"])
    ] }
}
