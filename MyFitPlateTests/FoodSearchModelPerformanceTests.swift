import XCTest
import UIKit
import MyFitPlateCore
@testable import MyFitPlate

/// Measures model readiness on the actual test destination, excluding XCTest UI waits,
/// pixels and live providers. Catalog sizes and query count are part of the report.
@MainActor
final class FoodSearchModelPerformanceTests: XCTestCase {
    func testLargePersonalCatalogAndWarmResultsReportModelReadiness() async throws {
        let priorAuth = DIContainer.shared.authService
        let auth = MockAuthService(); auth.currentUserID = "wave4-performance-\(UUID().uuidString)"
        DIContainer.shared.authService = auth
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "wave4-search-performance-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            DIContainer.shared.authService = priorAuth
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        var requests = 0
        let model = FoodSearchViewModel(defaults: defaults, draftStore: EditorDraftStore(directory: directory), searchLoader: { provider, query in
            requests += 1
            let foods = provider == .fatSecret ? [FoodItem(id: "remote-\(query)", name: query, calories: 120)
                .withDatabaseSource(.fatSecret, sourceName: "Benchmark fixture", brandName: "Fixture brand")] : []
            return .success(foods)
        })
        defer { model.searchText = "" }
        let products: [(String, String)] = [
            ("Chobani", "Plain Greek Yogurt"), ("Fairlife", "Reduced Fat Milk"),
            ("Quaker", "Old Fashioned Oats"), ("Mission", "Carb Balance Tortilla"),
            ("Jif", "Creamy Peanut Butter"), ("Quest", "Chocolate Brownie Bar"),
            ("Premier Protein", "Chocolate Shake"), ("Tyson", "Grilled Chicken Breast"),
            ("Barilla", "Penne Pasta"), ("Goya", "Black Beans"),
            ("Kashi", "Crunch Cereal"), ("Kodiak", "Buttermilk Power Cakes"),
            ("Oatly", "Original Oat Milk"), ("Applegate", "Roasted Turkey Breast"),
            ("Fage", "Total Greek Yogurt"), ("Clif", "Peanut Butter Bar"),
            ("Oikos", "Vanilla Yogurt"), ("Minute", "Brown Rice"),
            ("Tillamook", "Sharp Cheddar Cheese"), ("Smartfood", "White Cheddar Popcorn")
        ]
        let catalog = (0..<1_000).map { index in
            let product = products[index % products.count]
            return FoodItem(id: "catalog-\(index)", name: "\(product.0) \(product.1)", calories: 120,
                            protein: 10, carbs: 12, fats: 4, servingSize: "\(100 + index % 4 * 25) g", servingWeight: Double(100 + index % 4 * 25))
                .withDatabaseSource(.fatSecret, sourceName: "Benchmark fixture", brandName: product.0)
        }
        model.savedFoods = Array(catalog.prefix(500)); model.recentFoods = Array(catalog.suffix(500))
        let queries = products.flatMap { brand, food in
            [brand, "\(brand) \(food)", food, "\(food) \(brand)", "\(brand) \(food.dropLast(2))"]
        }
        XCTAssertEqual(queries.count, 100)
        var localMS: [Double] = [], cachedMS: [Double] = []
        for query in queries {
            let started = ProcessInfo.processInfo.systemUptime
            model.searchText = query
            let local = model.trustedSearchResults
            localMS.append((ProcessInfo.processInfo.systemUptime - started) * 1_000)
            XCTAssertFalse(local.isEmpty, query)
            model.submitSearch()
            let deadline = Date().addingTimeInterval(3)
            while model.isLoading && Date() < deadline { await Task.yield() }
            XCTAssertFalse(model.isLoading)
            let requestCount = requests
            let cachedStart = ProcessInfo.processInfo.systemUptime
            model.searchText = ""; model.searchText = query
            let presentation = model.searchPresentation
            cachedMS.append((ProcessInfo.processInfo.systemUptime - cachedStart) * 1_000)
            XCTAssertFalse(model.isLoading)
            XCTAssertFalse(presentation.brandedMatches.isEmpty)
            XCTAssertEqual(requests, requestCount, "Warm results must be ready without another provider call")
        }
        func percentile(_ values: [Double], _ fraction: Double) -> Double {
            let values = values.sorted()
            return values[min(values.count - 1, max(0, Int(ceil(Double(values.count) * fraction)) - 1))]
        }
        let report: [String: Any] = [
            "scope": "Main-actor model readiness; synthetic personal catalog and injected providers; no rendering or live-network claim",
            "device": ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? UIDevice.current.model,
            "system_version": UIDevice.current.systemVersion,
            "queries": queries.count, "saved_foods": 500, "recent_foods": 500,
            "local_p50_ms": percentile(localMS, 0.5), "local_p95_ms": percentile(localMS, 0.95),
            "warm_catalog_p50_ms": percentile(cachedMS, 0.5), "warm_catalog_p95_ms": percentile(cachedMS, 0.95),
            "local_200ms_p95_target_met": percentile(localMS, 0.95) < 200,
            "warm_200ms_p95_target_met": percentile(cachedMS, 0.95) < 200
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        print("WAVE4_SEARCH_MODEL_BENCHMARK " + text)
    }
}
