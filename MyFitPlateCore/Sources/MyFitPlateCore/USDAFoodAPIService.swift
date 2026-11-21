import Foundation

enum USDAFoodRequestBuilder {
    private struct SearchCriteria: Encodable {
        let query: String
        let requireAllWords: Bool
        let pageSize = 20
        let dataType = ["Branded", "Foundation", "SR Legacy", "Survey (FNDDS)"]
    }

    static func searchRequest(query: String, apiKey: String, requireAllWords: Bool = true) -> URLRequest? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search") else { return nil }
        components.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        let criteria = SearchCriteria(query: String(query.prefix(160)), requireAllWords: requireAllWords)
        guard let url = components.url, let body = try? JSONEncoder().encode(criteria) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }
}

/// Specific retrieval protects the small response window from unrelated generic foods.
/// An empty successful response gets one broader attempt for portions, extra descriptors
/// and typos. A rejected multiword query can retry a shorter family lookup.
/// Both attempts share one budget; auth, rate-limit and transport failures return immediately.
enum USDAFoodSearchPipeline {
    enum RequestError: Error { case rejectedQuery }
    static func search(query: String, apiKey: String, timeout: TimeInterval,
                       now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                       load: (URLRequest, TimeInterval) async throws -> Data) async throws -> [FoodItem] {
        let deadline = now() + timeout
        var rejectedPhrase = false
        let words = query.split(whereSeparator: \.isWhitespace)
        for requireAllWords in [true, false] {
            try Task.checkCancellation()
            let remaining = deadline - now()
            guard remaining > 0 else { throw URLError(.timedOut) }
            // A partial final word can empty the strict window. Retrieve the named
            // product family and rank its variants against the full original input.
            let retryPrefix = !requireAllWords && words.count >= 3 && words.first?.first?.isLetter == true &&
                words.last.map { (2...3).contains($0.count) && $0.allSatisfy(\.isLetter) } == true
            let lookup: String
            if rejectedPhrase { lookup = words.prefix(2).joined(separator: " ") } else if retryPrefix { lookup = words.dropLast().joined(separator: " ") } else { lookup = query }
            guard let request = USDAFoodRequestBuilder.searchRequest(query: lookup, apiKey: apiKey, requireAllWords: requireAllWords || retryPrefix || rejectedPhrase) else {
                throw APIError.invalidURL
            }
            let data: Data
            do { data = try await load(request, remaining) } catch RequestError.rejectedQuery where requireAllWords && words.count > 2 {
                rejectedPhrase = true
                continue
            }
            try Task.checkCancellation()
            let foods = try USDAFoodParser.foodItems(from: data)
            if !foods.isEmpty || !requireAllWords {
                return FoodSearchRanking.rankedRemoteMatches(query: query, foods: foods)
            }
        }
        return []
    }
}

// USDA FoodData Central API. Production search requires a dedicated key from
// https://fdc.nal.usda.gov/api-key-signup.html; the shared DEMO_KEY is intentionally not used.
public class USDAFoodAPIService {
    private let apiKey: String?
    private let baseURL = "https://api.nal.usda.gov/fdc/v1"
    private let requestTimeout: TimeInterval = 6
    private let session: URLSession

    public init(apiKey: String? = nil, session: URLSession? = nil) {
        let plistKey = Bundle.main.object(forInfoDictionaryKey: "USDA_API_KEY") as? String
        self.apiKey = apiKey ?? ((plistKey?.isEmpty == false && plistKey != "$(USDA_API_KEY)") ? plistKey : nil)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        self.session = session ?? URLSession(configuration: configuration)
    }

    // A bounded text search includes named products as well as reference/prepared foods.
    // Branded is the same supported USDA dataset used by the barcode lookup below.
    public func searchFoods(query: String) async -> [FoodItem] {
        (try? await searchFoodsResult(query: query).get()) ?? []
    }

    public func searchFoodsResult(query: String) async -> Result<[FoodItem], Error> {
        guard let apiKey else { return .failure(APIError.apiError("USDA search is not configured.")) }
        do {
            return .success(try await USDAFoodSearchPipeline.search(query: query, apiKey: apiKey, timeout: requestTimeout) { request, timeout in
                try await self.responseData(for: request, timeout: timeout)
            })
        } catch {
            return .failure(error)
        }
    }

    // Barcode (GTIN/UPC) lookup — searches Branded foods dataset by the UPC string.
    public func lookupBarcode(_ barcode: String) async -> FoodItem? {
        guard let apiKey else { return nil }
        let normalized = BarcodeCorrectionRules.normalizedBarcode(barcode)
        guard (8...14).contains(normalized.count),
              normalized.allSatisfy(\.isNumber) else { return nil }
        guard var components = URLComponents(string: "\(baseURL)/foods/search") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "query", value: normalized),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "pageSize", value: "5"),
            URLQueryItem(name: "dataType", value: "Branded")
        ]
        guard let url = components.url else { return nil }
        do {
            let data = try await responseData(for: URLRequest(url: url))
            return try USDAFoodParser.foodItem(matchingBarcode: normalized, from: data)
        } catch {
            return nil
        }
    }

    private func responseData(for search: URLRequest, timeout: TimeInterval? = nil) async throws -> Data {
        var request = search
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = timeout ?? requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 400 { throw USDAFoodSearchPipeline.RequestError.rejectedQuery }
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

/// Pure, testable parsing of a USDA FoodData Central search response into `FoodItem`s.
/// Extracted from the network call so the per-serving scaling, unit conversion and name/serving
/// cleanup can be unit-tested without hitting the network.
public enum USDAFoodParser {
    public static func foodItems(from data: Data) throws -> [FoodItem] {
        let response = try JSONDecoder().decode(USDASearchResponse.self, from: data)
        return response.foods.map { foodItem(from: $0) }
    }

    /// USDA's barcode endpoint is a text search, so the first result is not proof of identity.
    /// Accept only a response carrying the scanned GTIN or a zero-padded equivalent.
    public static func foodItem(matchingBarcode barcode: String, from data: Data) throws -> FoodItem? {
        let candidates = Set(BarcodeCorrectionRules.lookupCandidates(for: barcode))
        guard !candidates.isEmpty else { return nil }
        let response = try JSONDecoder().decode(USDASearchResponse.self, from: data)
        guard let match = response.foods.first(where: { food in
            guard let gtin = food.gtinUpc else { return false }
            return candidates.contains(BarcodeCorrectionRules.normalizedBarcode(gtin))
        }) else {
            return nil
        }
        return foodItem(from: match)
    }

    fileprivate static func foodItem(from food: USDAFood) -> FoodItem {
        // Build lookup by standard nutrient number string ("208", "203", etc.)
        var nutrients = [String: Double]()
        for n in food.foodNutrients {
            if let num = n.nutrientNumber, let val = n.value {
                nutrients[num] = val
            }
        }

        // USDA reports per 100 g; scale to the item's declared serving size (grams only).
        let massUnit = food.servingSizeUnit?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let measuredGrams = ["g", "grm", "gram", "grams"].contains(massUnit) ? food.servingSize : nil
        let validGrams = measuredGrams.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let servingGrams = validGrams ?? 100.0
        let scale = servingGrams / 100.0

        func v(_ num: String) -> Double { (nutrients[num] ?? 0) * scale }
        func o(_ num: String, multiplier: Double = 1) -> Double? {
            guard let value = nutrients[num], value.isFinite, value >= 0 else { return nil }
            return value * scale * multiplier
        }

        // Foundation Foods may omit legacy Energy208/1008. USDA publishes the
        // replacement kcal values as957/2047 (general) and958/2048 (specific).
        // Preserve a reported legacy value, including zero; never fabricate energy
        // from macros when a provider value exists. General factors are the default
        // fallback, consistent with USDA's Foundation→FNDDS energy treatment.
        let energyFields: [(number: String, id: Int, note: String?)] = [
            ("208", 1008, nil),
            ("957", 2047, "Energy reported by USDA using Atwater general factors."),
            ("958", 2048, "Energy reported by USDA using Atwater specific factors.")
        ]
        let energy = energyFields.compactMap { field -> (value: Double, note: String?)? in
            let candidates = food.foodNutrients.filter { $0.nutrientNumber == field.number || $0.nutrientId == field.id }
            let candidate = candidates.compactMap { nutrient -> Double? in
                let unit = nutrient.unitName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                guard unit.isEmpty || unit == "kcal", let value = nutrient.value,
                      value.isFinite, value >= 0, (value * scale).isFinite, value * scale >= 0 else { return nil }
                return value * scale
            }.first
            return candidate.map { ($0, field.note) }
        }.first

        let servingDescription: String
        if validGrams != nil, let hh = food.householdServingFullText, !hh.isEmpty {
            servingDescription = hh
        } else if let size = validGrams {
            servingDescription = "\(size.formatted(.number.precision(.fractionLength(0...2)))) g"
        } else {
            servingDescription = "100 g"
        }

        // Preserve preparation and form qualifiers. "APPLES, DRIED" must never be presented as
        // plain "Apples" because the calorie density is materially different.
        let displayName = food.description
            .lowercased()
            .capitalized
            .replacingOccurrences(of: ",", with: ", ")
            .replacingOccurrences(of: "  ", with: " ")

        let brand = FoodSearchRanking.reportedBrandName(food.brandName) ?? FoodSearchRanking.reportedBrandName(food.brandOwner)
        let item = FoodItem(
            id: "usda_\(food.fdcId)",
            name: FoodSearchRanking.productDisplayName(displayName, brandName: brand),
            calories: energy?.value ?? 0,
            protein: v("203"),
            carbs: v("205"),
            fats: v("204"),
            saturatedFat: o("606"),
            polyunsaturatedFat: o("646"),
            monounsaturatedFat: o("645"),
            fiber: o("291"),
            servingSize: servingDescription,
            servingWeight: servingGrams,
            timestamp: nil,
            calcium: o("301"),
            iron: o("303"),
            potassium: o("306"),
            sodium: o("307"),
            // FoodItem uses mcg RAE. Nutrient 318 is IU and cannot be relabeled as mcg.
            vitaminA: o("320"),
            vitaminC: o("401"),
            vitaminD: o("328"),
            vitaminB12: o("418"),
            folate: o("417"),
            magnesium: o("304"),
            phosphorus: o("305"),
            zinc: o("309"),
            // USDA reports copper in mg; FoodItem's established display/goal unit is mcg.
            copper: o("312", multiplier: 1_000),
            manganese: o("315"),
            selenium: o("317"),
            vitaminB1: o("404"),
            vitaminB2: o("405"),
            vitaminB3: o("406"),
            vitaminB5: o("410"),
            vitaminB6: o("415"),
            vitaminE: o("323"),
            vitaminK: o("430")
        )
        var metadata = FoodSourceMetadata.database(
            .usda,
            sourceName: "USDA FoodData Central",
            sourceID: "usda_\(food.fdcId)",
            brandName: brand,
            barcode: food.gtinUpc
        )
        metadata.confidence = usdaConfidence(for: food.dataType)
        metadata.evidenceLineage = usdaLineage(for: food.dataType)
        if validGrams == nil, let amount = food.servingSize, amount.isFinite, amount > 0, !massUnit.isEmpty {
            let unit = ["mlt", "ml", "milliliters", "millilitres"].contains(massUnit) ? "ml" : massUnit
            metadata.labeledServing = "\(amount.formatted(.number.precision(.fractionLength(0...2)))) \(unit)"
        }
        metadata.sourceUpdatedAt = usdaDate(food.modifiedDate ?? food.publishedDate)
        metadata.notes = energy?.note
        return item.withSourceMetadata(metadata)
    }

    private static func usdaConfidence(for dataType: String?) -> FoodConfidenceLevel {
        let normalized = dataType?.lowercased() ?? ""
        if normalized.contains("foundation") || normalized.contains("sr legacy") {
            return .verified
        }
        // Branded records are manufacturer label submissions hosted by USDA, not an
        // independent laboratory confirmation. Unknown future types stay conservative.
        return .databaseMatch
    }

    private static func usdaLineage(for dataType: String?) -> FoodEvidenceLineage {
        let normalized = dataType?.lowercased() ?? ""
        if normalized.contains("foundation") ||
            normalized.contains("sr legacy") ||
            normalized.contains("experimental") {
            return .analyticalReference
        }
        if normalized.contains("survey") || normalized.contains("fndds") {
            return .governmentCompilation
        }
        if normalized.contains("branded") {
            return .manufacturerLabel
        }
        return .unknown
    }

    private static func usdaDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: value)
    }
}

// MARK: - Response Models

private struct USDASearchResponse: Decodable {
    public let foods: [USDAFood]
}

private struct USDAFood: Decodable {
    public let fdcId: Int
    public let description: String
    public let dataType: String?
    public let brandOwner: String?
    public let brandName: String?
    public let gtinUpc: String?
    public let servingSize: Double?
    public let servingSizeUnit: String?
    public let householdServingFullText: String?
    public let publishedDate: String?
    public let modifiedDate: String?
    public let foodNutrients: [USDANutrient]
}

private struct USDANutrient: Decodable {
    public let nutrientId: Int?
    public let nutrientNumber: String?
    public let value: Double?
    public let unitName: String?
}
