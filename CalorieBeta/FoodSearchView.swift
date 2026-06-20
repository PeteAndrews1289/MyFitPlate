import SwiftUI
import FirebaseAuth

struct FoodSearchView: View {
    @Binding var dailyLog: DailyLog?
    var onFoodItemLogged: (() -> Void)?
    var onFoodItemSelected: ((FoodItem) -> Void)?
    var searchContext: String

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dailyLogService: DailyLogService

    @State private var searchText = ""
    @State private var selectedMeal: String = FoodSearchView.defaultMealName()
    private let foodTypes = ["Breakfast", "Lunch", "Dinner", "Snacks"]

    @State private var showingAddFoodManually = false
    @State private var showingBarcodeScanner = false
    @State private var showingImagePicker = false
    @State private var showingAITextLog = false

    @State private var searchResults: [FoodItem] = []
    @State private var isLoading = false
    @State private var searchErrorMessage: String? = nil
    @State private var activeSearchQuery = ""
    @State private var quickLoggedFoodIDs: Set<String> = []
    @State private var debounceTimer: Timer?
    @State private var selectedFoodItem: FoodItem? = nil
    @State private var selectedFoodSource: String = "search_result"

    @State private var isProcessingImage = false
    @State private var isSearchingAfterScan = false
    @State private var estimatedFoodItemsWrapper: IdentifiableFoodItems? = nil
    @State private var scannedFoodItem: FoodItem? = nil
    @State private var scanError: (Bool, String) = (false, "")

    private let foodAPIService = FatSecretFoodAPIService()
    private let imageModel = MLImageModel()

    @State private var savedFoods: [FoodItem] = []
    @State private var recentFoods: [FoodItem] = []
    @State private var recommendedFoods: [FoodItem] = []

    @State private var yesterdaysMealItems: [FoodItem] = []
    @State private var yesterdaysLog: DailyLog? = nil
    @State private var isFetchingYesterday = false

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var yesterdaysDayItems: [FoodItem] {
        yesterdaysLog?.meals.flatMap(\.foodItems) ?? []
    }

    private var hasYesterdayFoods: Bool {
        !yesterdaysMealItems.isEmpty || !yesterdaysDayItems.isEmpty
    }

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        FoodSearchHeader(
                            searchText: $searchText,
                            placeholder: onFoodItemSelected == nil ? "Search foods, meals, brands..." : "Search ingredients...",
                            onClear: {
                                searchText = ""
                                handleSearchQueryChange("")
                            },
                            onSubmit: hideKeyboard
                        )
                        .onChange(of: searchText) { _, newValue in
                            handleSearchQueryChange(newValue)
                        }

                        if onFoodItemSelected == nil && isSearching {
                            FoodSearchCompactMealPicker(selectedMeal: $selectedMeal, foodTypes: foodTypes)
                        }

                        if onFoodItemSelected == nil && !isSearching {
                            FoodSearchActionGrid(
                                manualAction: { showingAddFoodManually = true },
                                cameraAction: { showingImagePicker = true },
                                barcodeAction: { showingBarcodeScanner = true },
                                textAction: { showingAITextLog = true }
                            )

                            FoodSearchMealPicker(selectedMeal: $selectedMeal, foodTypes: foodTypes)

                            if hasYesterdayFoods {
                                YesterdayLogActions(
                                    selectedMeal: selectedMeal,
                                    mealItemCount: yesterdaysMealItems.count,
                                    mealCalories: yesterdaysMealItems.reduce(0) { $0 + $1.calories },
                                    dayItemCount: yesterdaysDayItems.count,
                                    dayCalories: yesterdaysDayItems.reduce(0) { $0 + $1.calories },
                                    onLogMeal: logYesterdayMeal,
                                    onLogDay: logYesterdayDay
                                )
                            }
                        }

                        if isSearching {
                            if isLoading {
                                FoodSearchLoadingState(query: searchText)
                            } else if let searchErrorMessage {
                                FoodSearchEmptyState(
                                    icon: "wifi.exclamationmark",
                                    title: "Search could not load",
                                    message: searchErrorMessage
                                )
                            } else if searchResults.isEmpty {
                                FoodSearchEmptyState(
                                    icon: "magnifyingglass",
                                    title: "No foods found",
                                    message: "Try a simpler search like \"chicken breast\" or use Manual to add it yourself."
                                )
                            } else {
                                FoodPickerSection(
                                    title: "Search Results",
                                    subtitle: "Tap a food to review servings before logging to \(selectedMeal).",
                                    foods: searchResults,
                                    quickLoggedFoodIDs: [],
                                    emptyTitle: "",
                                    emptyMessage: "",
                                    onSelect: { handleSelection(food: $0, source: "search_result") },
                                    onQuickLog: nil,
                                    onDelete: nil
                                )
                            }
                        } else {
                            FoodHorizontalScroller(
                                title: "My Foods",
                                subtitle: "Saved foods with your usual serving.",
                                foods: savedFoods,
                                quickLoggedFoodIDs: quickLoggedFoodIDs,
                                emptyTitle: "No saved foods yet",
                                emptyMessage: "Star foods from detail screens and they will appear here.",
                                onSelect: { handleSelection(food: $0, source: "custom_food") },
                                onQuickLog: onFoodItemSelected == nil ? quickLog : nil
                            )

                            FoodHorizontalScroller(
                                title: "Recommended for \(selectedMeal)",
                                subtitle: "Common picks based on your recent logging.",
                                foods: recommendedFoods,
                                quickLoggedFoodIDs: quickLoggedFoodIDs,
                                emptyTitle: "No recommendations yet",
                                emptyMessage: "Log a few \(selectedMeal.lowercased()) foods and this area will become faster.",
                                onSelect: { handleSelection(food: $0, source: "recent_tap") },
                                onQuickLog: onFoodItemSelected == nil ? quickLog : nil
                            )

                            FoodHorizontalScroller(
                                title: "Recent Foods",
                                subtitle: "Your fastest path for repeat meals.",
                                foods: recentFoods,
                                quickLoggedFoodIDs: quickLoggedFoodIDs,
                                emptyTitle: "No recent foods",
                                emptyMessage: "Foods you log will appear here for one-tap reuse.",
                                onSelect: { handleSelection(food: $0, source: "recent_tap") },
                                onQuickLog: onFoodItemSelected == nil ? quickLog : nil
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
                .background(Color.backgroundPrimary.ignoresSafeArea())
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle(onFoodItemSelected == nil ? "Log Food" : "Select Ingredient")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
                .onAppear(perform: fetchData)
                .onChange(of: selectedMeal) { _, _ in
                    fetchRecommendedFoods()
                    fetchYesterdayMeal()
                }
                .sheet(isPresented: $showingAddFoodManually) {
                    AddFoodView(
                        initialFoodItem: FoodItem(id: UUID().uuidString, name: "", calories: 0, protein: 0, carbs: 0, fats: 0, servingSize: "", servingWeight: 0),
                        dailyLog: $dailyLogService.currentDailyLog,
                        date: dailyLogService.activelyViewedDate,
                        source: "manual_add",
                        targetMealName: selectedMeal,
                        onLogUpdated: {
                            showingAddFoodManually = false
                            onFoodItemLogged?()
                        }
                    )
                }
                .sheet(isPresented: $showingBarcodeScanner) {
                    BarcodeScannerView { barcode in
                        self.showingBarcodeScanner = false
                        self.isSearchingAfterScan = true
                        foodAPIService.fetchFoodByBarcode(barcode: barcode) { result in
                            self.isSearchingAfterScan = false
                            switch result {
                            case .success(let foodItem):
                                self.scannedFoodItem = foodItem
                            case .failure(let error):
                                self.scanError = (true, "Could not find a food for this barcode. Error: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                .sheet(isPresented: $showingImagePicker) {
                    ImagePicker(sourceType: .camera) { image in
                        self.isProcessingImage = true
                        imageModel.estimateNutritionFromImage(image: image) { result in
                            self.isProcessingImage = false
                            switch result {
                            case .success(let foodItems):
                                self.estimatedFoodItemsWrapper = IdentifiableFoodItems(items: foodItems)
                            case .failure(let error):
                                self.scanError = (true, "Could not analyze the image. Error: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                .sheet(isPresented: $showingAITextLog) { AITextLogView() }
                .sheet(item: $selectedFoodItem) { foodItem in
                    FoodDetailView(
                        initialFoodItem: foodItem,
                        dailyLog: $dailyLog,
                        date: dailyLogService.activelyViewedDate,
                        source: selectedFoodSource,
                        targetMealName: selectedMeal,
                        onLogUpdated: {
                            selectedFoodItem = nil
                            onFoodItemLogged?()
                        }
                    )
                }
                .sheet(item: $scannedFoodItem) { foodItem in
                    FoodDetailView(
                        initialFoodItem: foodItem,
                        dailyLog: $dailyLog,
                        date: dailyLogService.activelyViewedDate,
                        source: "barcode_result",
                        targetMealName: selectedMeal,
                        onLogUpdated: {
                            self.scannedFoodItem = nil
                            onFoodItemLogged?()
                        }
                    )
                }
                .sheet(item: $estimatedFoodItemsWrapper) { wrapper in
                     AISummaryView(estimatedItems: .constant(wrapper.items))
                }
                .alert("Scan Error", isPresented: $scanError.0) { Button("OK") { } } message: { Text(scanError.1) }

                if isProcessingImage || isSearchingAfterScan {
                    Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                    ProgressView(isProcessingImage ? "Analyzing Image..." : "Searching Barcode...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                        .padding(20)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(15)
                }
            }
        }
    }

    private func handleSelection(food: FoodItem, source: String) {
        if let selectionHandler = onFoodItemSelected {
            guard source == "search_result", isLikelyFoodAPIID(food.id) else {
                selectionHandler(food)
                return
            }

            isSearchingAfterScan = true
            foodAPIService.fetchFoodDetails(foodId: food.id) { result in
                DispatchQueue.main.async {
                    isSearchingAfterScan = false
                    switch result {
                    case .success(let (detailedFood, _)):
                        selectionHandler(detailedFood)
                    case .failure(let error):
                        AppLog.data.error("Failed to fetch food details: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        } else {
            selectedFoodSource = source
            self.selectedFoodItem = food
        }
    }

    private func isLikelyFoodAPIID(_ id: String) -> Bool {
        id.count < 20 && !id.contains("-")
    }

    private func quickLog(food: FoodItem) {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let sourceFoodID = food.id
        var itemToLog = food
        itemToLog.id = UUID().uuidString
        itemToLog.timestamp = Date()
        dailyLogService.addMealToLog(
            for: userID,
            date: dailyLogService.activelyViewedDate,
            mealName: selectedMeal,
            foodItems: [itemToLog],
            source: "quick_log"
        )
        quickLoggedFoodIDs.insert(sourceFoodID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            quickLoggedFoodIDs.remove(sourceFoodID)
        }
        HapticManager.instance.feedback(.medium)
    }

    private func handleSearchQueryChange(_ newValue: String) {
        debounceTimer?.invalidate()
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            activeSearchQuery = ""
            searchResults = []
            searchErrorMessage = nil
            isLoading = false
            return
        }
        activeSearchQuery = trimmed
        isLoading = true
        searchErrorMessage = nil
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
            searchByQuery(query: trimmed)
        }
    }

    private func searchByQuery(query: String) {
        foodAPIService.fetchFoodByQuery(query: query) { result in
            DispatchQueue.main.async {
                guard query == activeSearchQuery else { return }
                isLoading = false
                switch result {
                case .success(let foodItems):
                    self.searchErrorMessage = nil
                    self.searchResults = foodItems
                case .failure(let error):
                    self.searchErrorMessage = "Check your connection and try again. \(error.localizedDescription)"
                    self.searchResults = []
                }
            }
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func fetchData() {
        fetchSavedFoods()
        fetchRecents()
        fetchRecommendedFoods()
        fetchYesterdayMeal()
    }

    private func fetchSavedFoods() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        dailyLogService.fetchMyFoodItems(for: userID) { result in
            DispatchQueue.main.async {
                if case .success(let items) = result {
                    self.savedFoods = items
                }
            }
        }
    }

    private func fetchRecents() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        dailyLogService.fetchRecentFoodItems(for: userID) { result in
            DispatchQueue.main.async {
                if case .success(let items) = result {
                    self.recentFoods = items
                }
            }
        }
    }

    private func fetchRecommendedFoods() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        dailyLogService.fetchRecommendedFoods(for: userID, mealName: selectedMeal) { result in
            DispatchQueue.main.async {
                if case .success(let items) = result {
                    self.recommendedFoods = items
                }
            }
        }
    }

    private func fetchYesterdayMeal() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: dailyLogService.activelyViewedDate) else { return }

        isFetchingYesterday = true
        dailyLogService.fetchLogInternal(for: userID, date: yesterday) { result in
            DispatchQueue.main.async {
                self.isFetchingYesterday = false
                switch result {
                case .success(let log):
                    self.yesterdaysLog = log
                    if let meal = log.meals.first(where: { $0.name.lowercased() == self.selectedMeal.lowercased() }) {
                        self.yesterdaysMealItems = meal.foodItems
                    } else {
                        self.yesterdaysMealItems = []
                    }
                case .failure:
                    self.yesterdaysLog = nil
                    self.yesterdaysMealItems = []
                }
            }
        }
    }

    private func logYesterdayMeal() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        guard !yesterdaysMealItems.isEmpty else { return }

        var itemsToLog = yesterdaysMealItems
        for i in 0..<itemsToLog.count {
            itemsToLog[i].id = UUID().uuidString
            itemsToLog[i].timestamp = Date()
        }
        dailyLogService.addMealToLog(
            for: userID,
            date: dailyLogService.activelyViewedDate,
            mealName: selectedMeal,
            foodItems: itemsToLog,
            source: "repeat_yesterday_meal"
        )

        HapticManager.instance.feedback(.medium)
    }

    private func logYesterdayDay() {
        guard let userID = Auth.auth().currentUser?.uid,
              let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: dailyLogService.activelyViewedDate),
              !yesterdaysDayItems.isEmpty else {
            return
        }

        dailyLogService.repeatFoods(from: yesterday, to: dailyLogService.activelyViewedDate, for: userID)
        HapticManager.instance.feedback(.medium)
    }

    private func deleteRecent(food: FoodItem) {
        recentFoods.removeAll { $0.id == food.id }
    }

    private static func defaultMealName(for date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<11:
            return "Breakfast"
        case 11..<16:
            return "Lunch"
        case 16..<22:
            return "Dinner"
        default:
            return "Snacks"
        }
    }
}

private struct FoodSearchHeader: View {
    @Binding var searchText: String
    let placeholder: String
    let onClear: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.brandPrimary)

            TextField(placeholder, text: $searchText)
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .onSubmit(onSubmit)

            if !searchText.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color.backgroundSecondary.opacity(0.84), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct YesterdayLogActions: View {
    let selectedMeal: String
    let mealItemCount: Int
    let mealCalories: Double
    let dayItemCount: Int
    let dayCalories: Double
    let onLogMeal: () -> Void
    let onLogDay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Copy Yesterday")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(UIColor.secondaryLabel))

            HStack(spacing: 10) {
                yesterdayButton(
                    title: selectedMeal,
                    detail: detailText(count: mealItemCount, calories: mealCalories),
                    icon: "clock.arrow.circlepath",
                    isEnabled: mealItemCount > 0,
                    action: onLogMeal
                )

                yesterdayButton(
                    title: "Full Day",
                    detail: detailText(count: dayItemCount, calories: dayCalories),
                    icon: "calendar.badge.plus",
                    isEnabled: dayItemCount > 0,
                    action: onLogDay
                )
            }
        }
        .padding(14)
        .background(Color.backgroundSecondary.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func detailText(count: Int, calories: Double) -> String {
        guard count > 0 else { return "No items" }
        return "\(count) items • \(Int(calories.rounded())) cal"
    }

    private func yesterdayButton(title: String, detail: String, icon: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(isEnabled ? .brandPrimary : Color(UIColor.tertiaryLabel))
                    .frame(width: 30, height: 30)
                    .background((isEnabled ? Color.brandPrimary : Color(UIColor.tertiaryLabel)).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isEnabled ? .textPrimary : Color(UIColor.secondaryLabel))
                        .lineLimit(1)

                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .padding(12)
            .background(Color.backgroundPrimary.opacity(isEnabled ? 0.78 : 0.42), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct FoodSearchActionGrid: View {
    let manualAction: () -> Void
    let cameraAction: () -> Void
    let barcodeAction: () -> Void
    let textAction: () -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
            FoodSearchActionTile(title: "Manual", subtitle: "Type numbers", icon: "square.and.pencil", action: manualAction)
            FoodSearchActionTile(title: "Barcode", subtitle: "Scan package", icon: "barcode.viewfinder", action: barcodeAction)
            FoodSearchActionTile(title: "Camera", subtitle: "Snap meal", icon: "camera.fill", action: cameraAction)
            FoodSearchActionTile(title: "Describe", subtitle: "Use text", icon: "text.bubble.fill", action: textAction)
        }
    }
}

private struct FoodSearchActionTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.brandPrimary)
                    .frame(width: 34, height: 34)
                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .padding(12)
            .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct FoodSearchMealPicker: View {
    @Binding var selectedMeal: String
    let foodTypes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Log to")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(UIColor.secondaryLabel))

            HStack(spacing: 7) {
                ForEach(foodTypes, id: \.self) { meal in
                    Button {
                        selectedMeal = meal
                    } label: {
                        Text(meal)
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.74)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                selectedMeal == meal ? Color.brandPrimary.opacity(0.14) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .foregroundColor(selectedMeal == meal ? .brandPrimary : Color(UIColor.secondaryLabel))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
            .background(Color.backgroundSecondary.opacity(0.76), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
    }
}

private struct FoodSearchCompactMealPicker: View {
    @Binding var selectedMeal: String
    let foodTypes: [String]

    var body: some View {
        HStack(spacing: 10) {
            Text("Log to")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(UIColor.secondaryLabel))

            Menu {
                ForEach(foodTypes, id: \.self) { meal in
                    Button(meal) {
                        selectedMeal = meal
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedMeal)
                        .font(.system(size: 13, weight: .bold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.brandPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.brandPrimary.opacity(0.12), in: Capsule())
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.backgroundSecondary.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct FoodPickerSection: View {
    let title: String
    let subtitle: String
    let foods: [FoodItem]
    let quickLoggedFoodIDs: Set<String>
    let emptyTitle: String
    let emptyMessage: String
    let onSelect: (FoodItem) -> Void
    let onQuickLog: ((FoodItem) -> Void)?
    let onDelete: ((FoodItem) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }

            if foods.isEmpty {
                FoodSearchEmptyState(icon: "tray", title: emptyTitle, message: emptyMessage)
            } else {
                VStack(spacing: 9) {
                    ForEach(foods) { food in
                        FoodPickerRow(
                            food: food,
                            isQuickLogged: quickLoggedFoodIDs.contains(food.id),
                            onSelect: onSelect,
                            onQuickLog: onQuickLog,
                            onDelete: onDelete
                        )
                    }
                }
            }
        }
    }
}

private struct FoodPickerRow: View {
    let food: FoodItem
    let isQuickLogged: Bool
    let onSelect: (FoodItem) -> Void
    let onQuickLog: ((FoodItem) -> Void)?
    let onDelete: ((FoodItem) -> Void)?

    private var detailText: String {
        guard food.calories > 0 || food.protein > 0 || food.carbs > 0 || food.fats > 0 else {
            return "Tap to review nutrition"
        }

        var parts: [String] = []
        if food.calories > 0 { parts.append("\(Int(food.calories.rounded())) cal") }
        if food.protein > 0 { parts.append("P \(Int(food.protein.rounded()))g") }
        if food.carbs > 0 { parts.append("C \(Int(food.carbs.rounded()))g") }
        if food.fats > 0 { parts.append("F \(Int(food.fats.rounded()))g") }
        return parts.joined(separator: "  ")
    }

    private var servingText: String {
        food.servingSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Serving details" : food.servingSize
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { onSelect(food) }) {
                HStack(spacing: 12) {
                    Text(FoodEmojiMapper.getEmoji(for: food.name))
                        .font(.system(size: 23))
                        .frame(width: 42, height: 42)
                        .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(food.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.textPrimary)
                            .lineLimit(2)

                        Text(servingText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(UIColor.secondaryLabel))
                            .lineLimit(1)

                        Text(detailText)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.brandPrimary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let onQuickLog {
                Button(action: { onQuickLog(food) }) {
                    Image(systemName: isQuickLogged ? "checkmark" : "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(isQuickLogged ? Color.accentPositive : Color.brandPrimary, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isQuickLogged)
                .accessibilityLabel("Quick log \(food.name)")
            }

            if let onDelete {
                Button(role: .destructive, action: { onDelete(food) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(food.name) from recent foods")
            }
        }
        .padding(12)
        .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct FoodHorizontalScroller: View {
    let title: String
    let subtitle: String
    let foods: [FoodItem]
    let quickLoggedFoodIDs: Set<String>
    let emptyTitle: String
    let emptyMessage: String
    let onSelect: (FoodItem) -> Void
    let onQuickLog: ((FoodItem) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }

            if foods.isEmpty {
                FoodSearchEmptyState(icon: "tray", title: emptyTitle, message: emptyMessage)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(foods) { food in
                            FoodCard(
                                food: food,
                                isQuickLogged: quickLoggedFoodIDs.contains(food.id),
                                onSelect: onSelect,
                                onQuickLog: onQuickLog
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, -4)
            }
        }
    }
}

private struct FoodCard: View {
    let food: FoodItem
    let isQuickLogged: Bool
    let onSelect: (FoodItem) -> Void
    let onQuickLog: ((FoodItem) -> Void)?

    private var servingText: String {
        let trimmed = food.servingSize.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Usual serving" : trimmed
    }

    var body: some View {
        Button(action: { onSelect(food) }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text(FoodEmojiMapper.getEmoji(for: food.name))
                        .font(.system(size: 32))

                    Spacer()

                    if let onQuickLog = onQuickLog {
                        Button(action: {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            onQuickLog(food)
                        }) {
                            Image(systemName: isQuickLogged ? "checkmark.circle.fill" : "plus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(isQuickLogged ? .accentPositive : .brandPrimary)
                        }
                        .disabled(isQuickLogged)
                        .accessibilityLabel(isQuickLogged ? "\(food.name) logged" : "Quick log \(food.name)")
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(servingText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .lineLimit(1)

                    Text("\(Int(food.calories.rounded())) cal")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.brandPrimary)
                }
            }
            .padding(14)
            .frame(width: 146, height: 150)
            .background(Color.backgroundSecondary.opacity(0.8), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct FoodSearchLoadingState: View {
    let query: String

    var body: some View {
        VStack(spacing: 13) {
            ProgressView()
                .tint(.brandPrimary)

            Text("Searching foods")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.textPrimary)

            Text(query.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(UIColor.secondaryLabel))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(Color.backgroundSecondary.opacity(0.76), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct FoodSearchEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.brandPrimary)
                .frame(width: 48, height: 48)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.textPrimary)

                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 26)
        .background(Color.backgroundSecondary.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
