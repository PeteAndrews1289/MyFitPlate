import Foundation
import SwiftSoup

enum RecipeImportURLPolicy {
    static let maximumResponseBytes = 2_097_152

    static func allowedURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        return allowedURL(url)
    }

    static func allowedURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              let rawHost = components.host?.lowercased() else {
            return nil
        }
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !host.isEmpty,
              isPublicHost(host) else {
            return nil
        }
        components.scheme = "https"
        components.host = host
        return components.url
    }

    static func allowedRedirectRequest(_ request: URLRequest) -> URLRequest? {
        guard let url = request.url, allowedURL(url) != nil else { return nil }
        return request
    }

    private static func isPublicHost(_ host: String) -> Bool {
        guard host != "localhost",
              host != "localdomain",
              !host.hasSuffix(".localhost"),
              !host.hasSuffix(".localdomain"),
              !host.hasSuffix(".local"),
              !host.hasSuffix(".internal"),
              !host.hasSuffix(".lan"),
              !host.hasSuffix(".home"),
              !host.hasSuffix(".home.arpa") else {
            return false
        }
        if host.contains(":") {
            let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            return isPublicIPv6(normalized)
        }
        guard host.contains(".") else { return false }
        if let octets = ipv4Octets(host) {
            return !isPrivateIPv4(octets)
        }
        return !isAmbiguousNumericHost(host)
    }

    private static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        guard parts.allSatisfy({ part in
            part == "0" || (part.first != "0" && part.allSatisfy(\.isNumber))
        }) else { return nil }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return octets
    }

    private static func isPrivateIPv4(_ octets: [Int]) -> Bool {
        let first = octets[0]
        let second = octets[1]
        return first == 0 ||
            first == 10 ||
            first == 127 ||
            first >= 224 ||
            (first == 100 && (64...127).contains(second)) ||
            (first == 169 && second == 254) ||
            (first == 172 && (16...31).contains(second)) ||
            (first == 192 && second == 0) ||
            (first == 192 && second == 168) ||
            (first == 198 && (second == 18 || second == 19)) ||
            (first == 198 && second == 51 && octets[2] == 100) ||
            (first == 203 && second == 0 && octets[2] == 113)
    }

    private static func isAmbiguousNumericHost(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty else { return true }
        return labels.allSatisfy { label in
            if !label.isEmpty, label.allSatisfy(\.isNumber) {
                return true
            }
            let lowercased = label.lowercased()
            let hexadecimal = lowercased.hasPrefix("0x") ? lowercased.dropFirst(2) : ""
            return !hexadecimal.isEmpty && hexadecimal.allSatisfy(\.isHexDigit)
        }
    }

    private static func isPublicIPv6(_ host: String) -> Bool {
        var address = in6_addr()
        guard inet_pton(AF_INET6, host, &address) == 1 else { return false }
        let bytes = withUnsafeBytes(of: &address) { Array($0) }
        guard bytes.count == 16,
              !bytes.allSatisfy({ $0 == 0 }),
              !(bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1),
              (bytes[0] & 0xFE) != 0xFC,
              !(bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80),
              !(bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0xC0),
              bytes[0] != 0xFF else {
            return false
        }

        let isIPv4Mapped = bytes.prefix(10).allSatisfy { $0 == 0 } &&
            bytes[10] == 0xFF && bytes[11] == 0xFF
        if isIPv4Mapped {
            return !isPrivateIPv4(bytes.suffix(4).map(Int.init))
        }

        let isIPv4Compatible = bytes.prefix(12).allSatisfy { $0 == 0 }
        if isIPv4Compatible {
            return !isPrivateIPv4(bytes.suffix(4).map(Int.init))
        }

        let isSixToFour = bytes[0] == 0x20 && bytes[1] == 0x02
        if isSixToFour, isPrivateIPv4(bytes[2...5].map(Int.init)) {
            return false
        }

        let isWellKnownNAT64 = bytes[0] == 0x00 && bytes[1] == 0x64 &&
            bytes[2] == 0xFF && bytes[3] == 0x9B &&
            bytes[4..<12].allSatisfy { $0 == 0 }
        if isWellKnownNAT64, isPrivateIPv4(bytes.suffix(4).map(Int.init)) {
            return false
        }
        return true
    }
}

enum RecipePageTextExtractor {
    private static let maximumCharacters = 8_000
    private static let minimumUsefulCharacters = 40

    static func extract(from html: String) throws -> String? {
        let document = try SwiftSoup.parse(html)
        let structuredData = try document
            .select("script[type=application/ld+json]")
            .array()
            .map { try $0.html() }
            .filter { $0.localizedCaseInsensitiveContains("\"recipe\"") }
        let targetedText = try (
            document.select("h1, h2, h3, h4").array().map { try $0.text() } +
            document.select("p").array().map { try $0.text() } +
            document.select("li").array().map { try $0.text() }
        ).joined(separator: "\n")
        let visibleText = targetedText.count >= minimumUsefulCharacters
            ? targetedText
            : (try document.body()?.text() ?? "")
        let extracted = (structuredData + [visibleText])
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard extracted.count >= minimumUsefulCharacters else { return nil }
        return String(extracted.prefix(maximumCharacters))
    }
}

private final class RecipeImportRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(RecipeImportURLPolicy.allowedRedirectRequest(request))
    }
}

@MainActor
public class RecipeService: ObservableObject {

    @Published public var userRecipes: [Recipe] = []
    @Published public var isLoading: Bool = false
    private var activeAccountID: String?
    private var loadingRequestIDs: Set<UUID> = []

    public init() {}

    public func activateAccount(_ userID: String?) {
        guard activeAccountID != userID else { return }
        activeAccountID = userID
        userRecipes = []
        loadingRequestIDs.removeAll()
        isLoading = false
    }

    private func isActiveAccount(_ userID: String) -> Bool {
        activeAccountID == userID && DIContainer.shared.authService.currentUserID == userID
    }

    private func beginRequest(for userID: String) -> UUID? {
        guard DIContainer.shared.authService.currentUserID == userID else { return nil }
        if activeAccountID != userID {
            activateAccount(userID)
        }
        let requestID = UUID()
        loadingRequestIDs.insert(requestID)
        isLoading = true
        return requestID
    }

    private func finishRequest(_ requestID: UUID, for userID: String) {
        loadingRequestIDs.remove(requestID)
        if isActiveAccount(userID) {
            isLoading = !loadingRequestIDs.isEmpty
        }
    }

    // MARK: - AI Recipe Generation (Refactored)
    public func createRecipeFromAI(description: String, userID: String, retryCount: Int = 1) async -> Recipe? {
        guard let requestID = beginRequest(for: userID) else { return nil }
        defer { finishRequest(requestID, for: userID) }

        let prompt = RecipeRules.createRecipeFromAIPrompt(description: description)

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        // Use the centralized service
        let result = await DIContainer.shared.aiService.performRequest(
            messages: messages,
            temperature: 0.5,
            responseFormat: ["type": "json_object"],
            retryCount: 0 // We handle logic retries below
        )
        guard isActiveAccount(userID) else { return nil }

        switch result {
        case .success(let jsonString):
            do {
                let recipe = try RecipeRules.parseRecipeFromAIResponse(jsonString)
                let savedRecipe = try await saveRecipe(recipe, for: userID)
                guard isActiveAccount(userID) else { return nil }
                DIContainer.shared.analyticsManager?.logEvent("ai_recipe_generated", parameters: nil)
                return savedRecipe
            } catch {
                AppLog.recipes.error("Recipe parsing failed: \(error.localizedDescription, privacy: .public)")
                if retryCount > 0 {
                    AppLog.recipes.info("Retrying recipe generation.")
                    return await createRecipeFromAI(description: description, userID: userID, retryCount: retryCount - 1)
                }
                return nil
            }
        case .failure(let error):
            AppLog.recipes.error("Recipe AI request failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func createRecipeFromText(text: String, userID: String, retryCount: Int = 1) async -> Recipe? {
        guard let requestID = beginRequest(for: userID) else { return nil }
        defer { finishRequest(requestID, for: userID) }

        let prompt = RecipeRules.createRecipeFromTextPrompt(text: text)

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        let result = await DIContainer.shared.aiService.performRequest(
            messages: messages,
            temperature: 0.5,
            responseFormat: ["type": "json_object"],
            retryCount: 0
        )
        guard isActiveAccount(userID) else { return nil }

        switch result {
        case .success(let jsonString):
            do {
                let recipe = try RecipeRules.parseRecipeFromAIResponse(jsonString)
                let savedRecipe = try await saveRecipe(recipe, for: userID)
                guard isActiveAccount(userID) else { return nil }
                DIContainer.shared.analyticsManager?.logEvent("ai_recipe_text_imported", parameters: nil)
                return savedRecipe
            } catch {
                AppLog.recipes.error("Recipe text parsing failed: \(error.localizedDescription, privacy: .public)")
                if retryCount > 0 {
                    AppLog.recipes.info("Retrying recipe text generation.")
                    return await createRecipeFromText(text: text, userID: userID, retryCount: retryCount - 1)
                }
                return nil
            }
        case .failure(let error):
            AppLog.recipes.error("Recipe text AI request failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func createRecipeFromPantry(itemsString: String, userID: String, retryCount: Int = 1) async -> Recipe? {
        guard let requestID = beginRequest(for: userID) else { return nil }
        defer { finishRequest(requestID, for: userID) }

        let prompt = RecipeRules.createRecipeFromPantryPrompt(itemsString: itemsString)

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        let result = await DIContainer.shared.aiService.performRequest(
            messages: messages,
            temperature: 0.5,
            responseFormat: ["type": "json_object"],
            retryCount: 0
        )
        guard isActiveAccount(userID) else { return nil }

        switch result {
        case .success(let jsonString):
            do {
                let recipe = try RecipeRules.parseRecipeFromAIResponse(jsonString)
                DIContainer.shared.analyticsManager?.logEvent("ai_recipe_pantry_generated", parameters: nil)
                return recipe
            } catch {
                AppLog.recipes.error("Pantry Recipe parsing failed: \(error.localizedDescription, privacy: .public)")
                if retryCount > 0 {
                    AppLog.recipes.info("Retrying pantry recipe generation.")
                    return await createRecipeFromPantry(itemsString: itemsString, userID: userID, retryCount: retryCount - 1)
                }
                return nil
            }
        case .failure(let error):
            AppLog.recipes.error("Pantry Recipe AI request failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func createRecipesFromPantry(itemsString: String, userID: String, retryCount: Int = 1) async -> [Recipe] {
        guard let requestID = beginRequest(for: userID) else { return [] }
        defer { finishRequest(requestID, for: userID) }

        let prompt = RecipeRules.createRecipesFromPantryPrompt(itemsString: itemsString)

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        let result = await DIContainer.shared.aiService.performRequest(
            messages: messages,
            temperature: 0.6,
            responseFormat: ["type": "json_object"],
            retryCount: 0
        )
        guard isActiveAccount(userID) else { return [] }

        switch result {
        case .success(let jsonString):
            do {
                let recipes = try RecipeRules.parseRecipesFromAIResponse(jsonString)
                DIContainer.shared.analyticsManager?.logEvent("ai_recipe_pantry_generated", parameters: ["count": recipes.count])
                return recipes
            } catch {
                AppLog.recipes.error("Pantry Recipes parsing failed: \(error.localizedDescription, privacy: .public)")
                if retryCount > 0 {
                    return await createRecipesFromPantry(itemsString: itemsString, userID: userID, retryCount: retryCount - 1)
                }
                return []
            }
        case .failure(let error):
            AppLog.recipes.error("Pantry Recipes AI request failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func createRecipeFromURL(url: String, userID: String, retryCount: Int = 1) async -> Recipe? {
        guard let requestID = beginRequest(for: userID) else { return nil }
        defer { finishRequest(requestID, for: userID) }

        guard let urlObj = RecipeImportURLPolicy.allowedURL(from: url) else {
            AppLog.recipes.error("Recipe URL was rejected by the public HTTPS policy.")
            return nil
        }

        var scrapedText = ""
        do {
            var request = URLRequest(
                url: urlObj,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 20
            )
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            request.setValue(
                "bytes=0-\(RecipeImportURLPolicy.maximumResponseBytes - 1)",
                forHTTPHeaderField: "Range"
            )

            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            let redirectDelegate = RecipeImportRedirectDelegate()
            let session = URLSession(
                configuration: configuration,
                delegate: redirectDelegate,
                delegateQueue: nil
            )
            defer { session.invalidateAndCancel() }

            let (bytes, response) = try await session.bytes(for: request)
            guard isActiveAccount(userID) else { return nil }
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 || httpResponse.statusCode == 206,
                  httpResponse.expectedContentLength <= Int64(RecipeImportURLPolicy.maximumResponseBytes) ||
                    httpResponse.expectedContentLength == NSURLSessionTransferSizeUnknown,
                  httpResponse.url.flatMap(RecipeImportURLPolicy.allowedURL) != nil,
                  httpResponse.mimeType.map({ $0 == "text/html" || $0 == "application/xhtml+xml" }) ?? true,
                  httpResponse.textEncodingName?.lowercased() != "utf-16" else {
                throw URLError(.badServerResponse)
            }

            var data = Data()
            data.reserveCapacity(min(
                max(Int(httpResponse.expectedContentLength), 0),
                RecipeImportURLPolicy.maximumResponseBytes
            ))
            for try await byte in bytes {
                guard data.count < RecipeImportURLPolicy.maximumResponseBytes else {
                    throw URLError(.dataLengthExceedsMaximum)
                }
                data.append(byte)
            }
            guard let htmlString = String(data: data, encoding: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }

            guard let extractedText = try RecipePageTextExtractor.extract(from: htmlString) else {
                throw URLError(.cannotParseResponse)
            }
            scrapedText = extractedText
        } catch {
            AppLog.recipes.error("Failed to scrape URL: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let prompt = RecipeRules.createRecipeFromURLPrompt(scrapedText: scrapedText)

        let messages: [[String: Any]] = [["role": "user", "content": prompt]]

        let result = await DIContainer.shared.aiService.performRequest(
            messages: messages,
            temperature: 0.5,
            responseFormat: ["type": "json_object"],
            retryCount: 0
        )
        guard isActiveAccount(userID) else { return nil }

        switch result {
        case .success(let jsonString):
            do {
                guard let recipe = try RecipeRules.parseRecipeFromURLResponse(jsonString) else {
                    AppLog.recipes.info("Recipe URL response did not affirmatively identify a recipe.")
                    return nil
                }
                let savedRecipe = try await saveRecipe(recipe, for: userID)
                guard isActiveAccount(userID) else { return nil }
                DIContainer.shared.analyticsManager?.logEvent("url_recipe_imported", parameters: nil)
                return savedRecipe
            } catch {
                AppLog.recipes.error("Recipe parsing failed: \(error.localizedDescription, privacy: .public)")
                if retryCount > 0 {
                    AppLog.recipes.info("Retrying URL recipe import.")
                    return await createRecipeFromURL(url: url, userID: userID, retryCount: retryCount - 1)
                }
                return nil
            }
        case .failure(let error):
            AppLog.recipes.error("URL Recipe import request failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // ... [CRUD Operations - Keep Existing] ...

    public func fetchUserRecipes() async {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
        guard let requestID = beginRequest(for: userID) else { return }
        defer { finishRequest(requestID, for: userID) }
        do {
            let recipes = try await DIContainer.shared.nutritionRepository.fetchRecipes(userID: userID)
            guard isActiveAccount(userID) else { return }
            self.userRecipes = recipes
        } catch {
            AppLog.recipes.error("Failed to fetch user recipes: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    public func saveRecipe(_ recipe: Recipe, for userID: String) async throws -> Recipe {
        guard isActiveAccount(userID) else { throw CancellationError() }
        let savedRecipe = try await DIContainer.shared.nutritionRepository.saveRecipe(userID: userID, recipe: recipe)
        guard isActiveAccount(userID) else { return savedRecipe }
        DIContainer.shared.analyticsManager?.logEvent("recipe_created", parameters: nil)

        if let recipeID = savedRecipe.id,
           let index = userRecipes.firstIndex(where: { $0.id == recipeID }) {
            userRecipes[index] = savedRecipe
        } else {
            userRecipes.append(savedRecipe)
        }

        return savedRecipe
    }

    public func deleteRecipe(recipe: Recipe) async {
        guard let userID = DIContainer.shared.authService.currentUserID,
              isActiveAccount(userID),
              let recipeID = recipe.id else { return }
        do {
            try await DIContainer.shared.nutritionRepository.deleteRecipe(userID: userID, recipeID: recipeID)
            guard isActiveAccount(userID) else { return }
            if let index = userRecipes.firstIndex(where: { $0.id == recipeID }) { userRecipes.remove(at: index) }
        } catch {
            AppLog.recipes.error("Failed to delete recipe: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func recipeToFoodItem(recipe: Recipe) -> FoodItem {
        let nutrition = recipe.nutrition
        var food = FoodItem(
            id: recipe.id ?? UUID().uuidString,
            name: recipe.name,
            calories: nutrition.calories,
            protein: nutrition.protein,
            carbs: nutrition.carbs,
            fats: nutrition.fats,
            saturatedFat: nutrition.saturatedFat,
            polyunsaturatedFat: nutrition.polyunsaturatedFat,
            monounsaturatedFat: nutrition.monounsaturatedFat,
            fiber: nutrition.fiber,
            servingSize: "1 serving",
            servingWeight: 0,
            timestamp: nil,
            sourceMetadata: FoodSourceMetadata(
                sourceType: .recipe,
                confidence: .userVerified,
                reviewStatus: .notRequired,
                sourceName: "Recipe",
                sourceID: recipe.id
            ),
            calcium: nutrition.calcium,
            iron: nutrition.iron,
            potassium: nutrition.potassium,
            sodium: nutrition.sodium,
            vitaminA: nutrition.vitaminA,
            vitaminC: nutrition.vitaminC,
            vitaminD: nutrition.vitaminD,
            vitaminB12: nutrition.vitaminB12,
            folate: nutrition.folate,
            magnesium: nutrition.magnesium,
            phosphorus: nutrition.phosphorus,
            zinc: nutrition.zinc,
            copper: nutrition.copper,
            manganese: nutrition.manganese,
            selenium: nutrition.selenium,
            vitaminB1: nutrition.vitaminB1,
            vitaminB2: nutrition.vitaminB2,
            vitaminB3: nutrition.vitaminB3,
            vitaminB5: nutrition.vitaminB5,
            vitaminB6: nutrition.vitaminB6,
            vitaminE: nutrition.vitaminE,
            vitaminK: nutrition.vitaminK
        )
        food.quantityValue = 1.0
        food.servingUnit = "serving"
        return food
    }

}
