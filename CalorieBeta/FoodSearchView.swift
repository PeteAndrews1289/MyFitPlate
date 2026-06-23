import SwiftUI
import FirebaseAuth

struct FoodSearchView: View {
    @Binding var dailyLog: DailyLog?
    var onFoodItemLogged: (() -> Void)?
    var onFoodItemSelected: ((FoodItem) -> Void)?
    var searchContext: String

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dailyLogService: DailyLogService

    @StateObject private var viewModel = FoodSearchViewModel()

    @State private var showingAddFoodManually = false
    @State private var showingQuickAddMacros = false
    @State private var showingBarcodeScanner = false
    @State private var showingImagePicker = false
    @State private var showingMenuImagePicker = false
    @State private var showingAITextLog = false

    @State private var selectedFoodItem: FoodItem? = nil
    @State private var selectedFoodSource: String = "search_result"

    @State private var isProcessingImage = false
    @State private var isSearchingAfterScan = false
    @State private var estimatedFoodItemsWrapper: IdentifiableFoodItems? = nil
    @State private var estimatedMenuWrapper: IdentifiableFoodItems? = nil
    @State private var scannedFoodItem: FoodItem? = nil
    @State private var scanError: (Bool, String) = (false, "")

    private let foodAPIService = FatSecretFoodAPIService()
    private let usdaService = USDAFoodAPIService()
    private let imageModel = MLImageModel()

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        mainActionContent
                        searchOrSavedContent
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
                .onAppear {
                    viewModel.setup(dailyLogService: dailyLogService)
                    viewModel.fetchData()
                }
                .onChange(of: viewModel.selectedMeal) { _, _ in
                    if let userID = Auth.auth().currentUser?.uid {
                        viewModel.fetchRecommendedFoods(userID: userID)
                        viewModel.fetchYesterdayMeal(userID: userID)
                    }
                }
                .sheet(isPresented: $showingAddFoodManually) {
                    AddFoodView(
                        initialFoodItem: FoodItem(id: UUID().uuidString, name: "", calories: 0, protein: 0, carbs: 0, fats: 0, servingSize: "", servingWeight: 0),
                        dailyLog: $dailyLogService.currentDailyLog,
                        date: dailyLogService.activelyViewedDate,
                        source: "manual_add",
                        targetMealName: viewModel.selectedMeal,
                        onLogUpdated: {
                            showingAddFoodManually = false
                            onFoodItemLogged?()
                        }
                    )
                }
                .sheet(isPresented: $showingQuickAddMacros) {
                    QuickAddMacrosView(
                        selectedMealType: viewModel.selectedMeal,
                        targetDate: dailyLogService.activelyViewedDate
                    )
                }
                .sheet(isPresented: $showingBarcodeScanner) {
                    BarcodeScannerView { barcode in
                        self.showingBarcodeScanner = false
                        self.isSearchingAfterScan = true
                        AnalyticsManager.log(.barcodeScanned)
                        Task { @MainActor in
                            if let item = await withCheckedContinuation({ cont in
                                foodAPIService.fetchFoodByBarcode(barcode: barcode) { cont.resume(returning: try? $0.get()) }
                            }) {
                                self.isSearchingAfterScan = false
                                self.scannedFoodItem = item
                                return
                            }
                            if let item = await usdaService.lookupBarcode(barcode) {
                                self.isSearchingAfterScan = false
                                self.scannedFoodItem = item
                                return
                            }
                            self.isSearchingAfterScan = false
                            self.scanError = (true, "No food found for this barcode.")
                        }
                    }
                }
                .sheet(isPresented: $showingImagePicker) {
                    ImagePicker(sourceType: .camera) { image in
                        self.isProcessingImage = true
                        AnalyticsManager.aiFeatureUsed(.mealPhoto)
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
                .sheet(isPresented: $showingMenuImagePicker) {
                    ImagePicker(sourceType: .camera) { image in
                        self.isProcessingImage = true
                        AnalyticsManager.aiFeatureUsed(.menuPhoto)
                        imageModel.estimateMenuFromImage(image: image) { result in
                            self.isProcessingImage = false
                            switch result {
                            case .success(let foodItems):
                                self.estimatedMenuWrapper = IdentifiableFoodItems(items: foodItems)
                            case .failure(let error):
                                self.scanError = (true, "Could not analyze the menu. Error: \(error.localizedDescription)")
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
                        targetMealName: viewModel.selectedMeal,
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
                        source: foodItem.id.hasPrefix("usda_") ? "usda_barcode" : "barcode_result",
                        targetMealName: viewModel.selectedMeal,
                        onLogUpdated: {
                            self.scannedFoodItem = nil
                            onFoodItemLogged?()
                        }
                    )
                }
                .sheet(item: $estimatedFoodItemsWrapper) { wrapper in
                     AISummaryView(estimatedItems: .constant(wrapper.items))
                }
                .sheet(item: $estimatedMenuWrapper) { wrapper in
                     AIMenuSelectionView(estimatedItems: .constant(wrapper.items))
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

    @ViewBuilder
    private var smartHistoryContent: some View {
        if onFoodItemSelected == nil && !viewModel.isSearching && !viewModel.recommendedFoods.isEmpty {
            FoodHorizontalScroller(
                title: "Smart History",
                subtitle: "Based on \(viewModel.selectedMeal) and past logging.",
                foods: viewModel.recommendedFoods,
                quickLoggedFoodIDs: viewModel.quickLoggedFoodIDs,
                emptyTitle: "",
                emptyMessage: "",
                onSelect: { handleSelection(food: $0, source: "recent_tap") },
                onQuickLog: onFoodItemSelected == nil ? { viewModel.quickLog(food: $0) } : nil
            )
        }
    }

    @ViewBuilder
    private var searchHeaderContent: some View {
        FoodSearchHeader(
            searchText: $viewModel.searchText,
            placeholder: onFoodItemSelected == nil ? "Search foods, meals, brands..." : "Search ingredients...",
            onClear: {
                viewModel.searchText = ""
                viewModel.handleSearchQueryChange("")
            },
            onSubmit: hideKeyboard
        )
        .onChange(of: viewModel.searchText) { _, newValue in
            viewModel.handleSearchQueryChange(newValue)
        }
    }

    @ViewBuilder
    private var compactMealPickerContent: some View {
        if onFoodItemSelected == nil && viewModel.isSearching {
            FoodSearchCompactMealPicker(selectedMeal: $viewModel.selectedMeal, foodTypes: ["Breakfast", "Lunch", "Dinner", "Snacks"])
        }
    }

    @ViewBuilder
    private var actionGridContent: some View {
        if onFoodItemSelected == nil && !viewModel.isSearching {
            FoodSearchActionGrid(
                manualAction: { showingAddFoodManually = true },
                quickAddAction: { showingQuickAddMacros = true },
                cameraAction: { showingImagePicker = true },
                menuAction: { showingMenuImagePicker = true },
                barcodeAction: { showingBarcodeScanner = true },
                textAction: { showingAITextLog = true }
            )

            FoodSearchMealPicker(selectedMeal: $viewModel.selectedMeal, foodTypes: ["Breakfast", "Lunch", "Dinner", "Snacks"])

            if viewModel.hasYesterdayFoods {
                YesterdayLogActions(
                    selectedMeal: viewModel.selectedMeal,
                    mealItemCount: viewModel.yesterdaysMealItems.count,
                    mealCalories: viewModel.yesterdaysMealItems.reduce(0.0) { $0 + $1.calories },
                    dayItemCount: viewModel.yesterdaysDayItems.count,
                    dayCalories: viewModel.yesterdaysDayItems.reduce(0.0) { $0 + $1.calories },
                    onLogMeal: { viewModel.logYesterdayMeal() },
                    onLogDay: { viewModel.logYesterdayDay() }
                )
            }
        }
    }

    @ViewBuilder
    private var mainActionContent: some View {
        smartHistoryContent
        searchHeaderContent
        compactMealPickerContent
        actionGridContent
    }

    @ViewBuilder
    private var searchingStateContent: some View {
        if viewModel.isLoading {
            FoodSearchLoadingState(query: viewModel.searchText)
        } else if let searchErrorMessage = viewModel.searchErrorMessage {
            FoodSearchEmptyState(
                icon: "wifi.exclamationmark",
                title: "Search could not load",
                message: searchErrorMessage
            )
        } else if viewModel.searchResults.isEmpty {
            FoodSearchEmptyState(
                icon: "magnifyingglass",
                title: "No foods found",
                message: "Try a simpler search like \"chicken breast\", or add it manually."
            )
        } else {
            FoodPickerSection(
                title: "Search Results",
                subtitle: "Tap a food to review servings before logging to \(viewModel.selectedMeal).",
                foods: viewModel.searchResults,
                quickLoggedFoodIDs: viewModel.quickLoggedFoodIDs,
                emptyTitle: "",
                emptyMessage: "",
                onSelect: { handleSelection(food: $0, source: "search_result") },
                onQuickLog: onFoodItemSelected == nil ? { viewModel.quickLog(food: $0) } : nil,
                onDelete: nil
            )
        }
    }

    @ViewBuilder
    private var savedAndRecentFoodsContent: some View {
        FoodHorizontalScroller(
            title: "My Foods",
            subtitle: "Saved foods with your usual serving.",
            foods: viewModel.savedFoods,
            quickLoggedFoodIDs: viewModel.quickLoggedFoodIDs,
            emptyTitle: "No saved foods yet",
            emptyMessage: "Star foods from detail screens and they will appear here.",
            onSelect: { handleSelection(food: $0, source: "custom_food") },
            onQuickLog: onFoodItemSelected == nil ? { viewModel.quickLog(food: $0) } : nil
        )

        FoodHorizontalScroller(
            title: "Recent Foods",
            subtitle: "Your fastest path for repeat meals.",
            foods: viewModel.recentFoods,
            quickLoggedFoodIDs: viewModel.quickLoggedFoodIDs,
            emptyTitle: "No recent foods",
            emptyMessage: "Foods you log will appear here for one-tap reuse.",
            onSelect: { handleSelection(food: $0, source: "recent_tap") },
            onQuickLog: onFoodItemSelected == nil ? { viewModel.quickLog(food: $0) } : nil
        )
    }

    @ViewBuilder
    private var searchOrSavedContent: some View {
        if viewModel.isSearching {
            searchingStateContent
        } else {
            savedAndRecentFoodsContent
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

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func deleteRecent(food: FoodItem) {
        viewModel.recentFoods.removeAll { $0.id == food.id }
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
    let quickAddAction: () -> Void
    let cameraAction: () -> Void
    let menuAction: () -> Void
    let barcodeAction: () -> Void
    let textAction: () -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
            FoodSearchActionTile(title: "Quick Macros", subtitle: "Instant numbers", icon: "bolt.fill", action: quickAddAction)
            FoodSearchActionTile(title: "Manual Food", subtitle: "Custom entries", icon: "square.and.pencil", action: manualAction)
            FoodSearchActionTile(title: "Barcode", subtitle: "Scan package", icon: "barcode.viewfinder", action: barcodeAction)
            FoodSearchActionTile(title: "Camera", subtitle: "Snap meal", icon: "camera.fill", action: cameraAction)
            FoodSearchActionTile(title: "Menu", subtitle: "Scan menu", icon: "list.bullet.rectangle.portrait.fill", action: menuAction)
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

    @State private var offset: CGFloat = 0
    @State private var isSwipedRight: Bool = false
    @State private var isSwipedLeft: Bool = false

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
        ZStack(alignment: offset > 0 ? .leading : .trailing) {
            if isSwipedRight && onQuickLog != nil {
                HStack {
                    Button {
                        withAnimation(.easeInOut) {
                            if !isQuickLogged { onQuickLog?(food) }
                            offset = 0
                            isSwipedRight = false
                        }
                    } label: {
                        Image(systemName: isQuickLogged ? "checkmark" : "plus")
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60, alignment: .center)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .background(isQuickLogged ? Color.accentPositive : Color.brandPrimary)
                    .contentShape(Rectangle())
                    .cornerRadius(18)
                    Spacer()
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            } else if isSwipedLeft && onDelete != nil {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut) {
                            onDelete?(food)
                            offset = 0
                            isSwipedLeft = false
                        }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60, alignment: .center)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .background(Color.red)
                    .contentShape(Rectangle())
                    .cornerRadius(18)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            HStack(spacing: 10) {
                Button(action: {
                    if isSwipedRight || isSwipedLeft {
                        withAnimation(.easeInOut) {
                            offset = 0
                            isSwipedRight = false
                            isSwipedLeft = false
                        }
                    } else {
                        onSelect(food)
                    }
                }) {
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
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.width > 0 && onQuickLog != nil {
                            if !isSwipedLeft {
                                offset = min(value.translation.width, 70)
                            } else {
                                offset = -70 + value.translation.width
                            }
                        } else if value.translation.width < 0 && onDelete != nil {
                            if !isSwipedRight {
                                offset = max(value.translation.width, -70)
                            } else {
                                offset = 70 + value.translation.width
                            }
                        }
                    }
                    .onEnded { value in
                        withAnimation(.easeInOut) {
                            if value.translation.width > 50 && onQuickLog != nil {
                                offset = 70
                                isSwipedRight = true
                                isSwipedLeft = false
                            } else if value.translation.width < -50 && onDelete != nil {
                                offset = -70
                                isSwipedLeft = true
                                isSwipedRight = false
                            } else {
                                offset = 0
                                isSwipedRight = false
                                isSwipedLeft = false
                            }
                        }
                    }
            )
        }
    }
}
