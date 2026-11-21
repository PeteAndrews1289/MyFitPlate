import MyFitPlateCore
import SwiftUI
import UIKit

@MainActor
struct RestaurantValueRadarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var dailyLogService: DailyLogService
    @StateObject private var viewModel: RestaurantValueRadarViewModel
    @State private var showingImagePicker = false
    @State private var imageSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var itemToReview: RestaurantValueRadarItem?
    @State private var priceToReview: RestaurantComparisonRow?
    @State private var showingSavedScans = false
    private let loggingDate: Date
    private let loggingMeal: String

    init(date: Date, mealName: String) {
        loggingDate = date
        loggingMeal = mealName
        _viewModel = StateObject(wrappedValue: RestaurantValueRadarViewModel())
    }

    init(viewModel: RestaurantValueRadarViewModel, date: Date = Date(), mealName: String = "Dinner") {
        loggingDate = date
        loggingMeal = mealName
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        AppSheetScaffold(
            title: "Value Radar",
            subtitle: "Compare printed menu prices with reviewable nutrition estimates",
            dismiss: { dismiss() }
        ) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                    scanActions

                    if viewModel.isDemoMode {
                        regionSelector
                    } else if !viewModel.comparison.rows.isEmpty {
                        comparisonControls
                    }

                    resultContent
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.section)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppPalette.canvas)
        }
        .background(AppPalette.canvas.ignoresSafeArea())
        .tint(AppPalette.brand)
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(sourceType: imageSourceType) { image in
                viewModel.analyzeMenuImage(image)
            }
        }
        .sheet(item: $itemToReview) { item in
            AISummaryView(
                estimatedItems: [item.food],
                mealName: loggingMeal,
                date: loggingDate,
                source: "value_radar",
                isAIEstimate: true,
                reviewTitle: "Review Menu Estimate"
            )
            .environmentObject(dailyLogService)
        }
        .sheet(item: $priceToReview) { row in RestaurantPriceReviewView(row: row, sourceImage: viewModel.sourceImage) { viewModel.updateRow($0) } }
        .sheet(isPresented: $showingSavedScans) { savedComparisons }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("value_radar_screen")
    }

    @ViewBuilder
    private var scanActions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: AppSpacing.row) {
                scanMenuButton
                demoMenuButton
            }
        } else {
            HStack(spacing: AppSpacing.row) {
                scanMenuButton
                demoMenuButton
            }
        }
    }

    private var scanMenuButton: some View {
        Button {
            imageSourceType = UIImagePickerController.isSourceTypeAvailable(.camera)
                ? .camera
                : .photoLibrary
            showingImagePicker = true
        } label: {
            Label(
                viewModel.items.isEmpty ? "Scan Menu" : "Scan Another Menu",
                systemImage: "camera.viewfinder"
            )
        }
        .buttonStyle(AppActionButtonStyle(viewModel.items.isEmpty ? .primary : .secondary))
        .disabled(viewModel.isAnalyzing)
        .accessibilityIdentifier("value_radar_scan_button")
    }

    private var demoMenuButton: some View {
        Button {
            viewModel.loadDemoMenu()
        } label: {
            Label("View Demo", systemImage: "sparkles")
        }
        .buttonStyle(AppActionButtonStyle(.secondary))
        .disabled(viewModel.isAnalyzing)
        .accessibilityIdentifier("value_radar_demo_button")
    }

    private var regionSelector: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Demo Pricing Region",
                subtitle: "Regional adjustments apply only to demo prices. Scans use the price printed on the menu."
            )

            Menu {
                ForEach(AYCECityIndex.pickerOptions) { city in
                    Button {
                        viewModel.selectCity(city)
                    } label: {
                        Text(city.name)
                    }
                }
            } label: {
                AppListRow(
                    icon: "mappin.and.ellipse",
                    iconColor: AppPalette.brand,
                    title: viewModel.selectedCity.name,
                    subtitle: viewModel.regionComparisonText,
                    hidesTextFromAccessibility: true
                ) {
                    Image(systemName: "chevron.up.chevron.down")
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .appSurface(.quiet, padding: 0)
            .accessibilityLabel("Demo pricing region, \(viewModel.selectedCity.name)")
            .accessibilityHint("Changes the regional adjustment used for demo prices")
            .accessibilityIdentifier("value_radar_region")
        }
    }

    @ViewBuilder
    private var resultContent: some View {
        if viewModel.isAnalyzing {
            loadingState
        } else if let error = viewModel.errorMessage {
            errorState(error)
        } else if viewModel.items.isEmpty && viewModel.comparison.rows.isEmpty {
            emptyState
        } else {
            if viewModel.isDemoMode {
                demoNotice
            }
            topValue
            rankedItems
        }
    }

    private var loadingState: some View {
        VStack(spacing: AppSpacing.group) {
            ProgressView()
                .controlSize(.large)
                .tint(AppPalette.brand)
            Text("Reading Menu")
                .appTextRole(.control)
            Text("Matching visible prices with estimated nutrition.")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("value_radar_loading")
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: AppSpacing.group) {
            Image(systemName: "exclamationmark.triangle.fill")
                .appFont(size: 30, weight: .semibold)
                .foregroundStyle(AppPalette.caution)
                .accessibilityHidden(true)
            Text("Menu Could Not Be Ranked")
                .appTextRole(.sectionTitle)
            Text(message)
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.section)
        .appSurface(.emphasized)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("value_radar_error")
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.group) {
            Image(systemName: "doc.text.viewfinder")
                .appFont(size: 34, weight: .semibold)
                .foregroundStyle(AppPalette.brandText)
                .frame(width: 64, height: 64)
                .background(
                    AppPalette.brand.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: AppRadius.surface)
                )
                .accessibilityHidden(true)
            Text("Scan a Restaurant Menu")
                .appTextRole(.sectionTitle)
            Text("Printed prices stay exact. Calories and macros remain estimates until you review them.")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.section)
        .appSurface(.emphasized)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("value_radar_empty_state")
    }

    private var demoNotice: some View {
        AppListRow(
            icon: "eye.fill",
            iconColor: AppPalette.caution,
            title: "Demo Results",
            subtitle: "Prices and nutrition are fictional examples. Demo dishes cannot be logged."
        )
        .appSurface(.quiet, padding: 0)
        .accessibilityIdentifier("value_radar_demo_notice")
    }

    @ViewBuilder
    private var topValue: some View {
        if let item = viewModel.items.first {
            VStack(alignment: .leading, spacing: AppSpacing.group) {
                AppSectionHeader(
                    title: "First for your preference",
                    subtitle: viewModel.isDemoMode ? "Fictional demo comparison" : viewModel.comparison.objective.title
                ) {
                    Image(systemName: "medal.fill")
                        .appFont(size: 20, weight: .semibold)
                        .foregroundStyle(item.tierColor)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.food.name)
                        .appTextRole(.sectionTitle)
                        .foregroundStyle(AppPalette.text)
                    Text(item.nutritionSummary)
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                AppMetricStrip(items: item.metricItems)

                if item.canLog {
                    Button {
                        beginReview(item)
                    } label: {
                        Label("Review Before Logging", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .accessibilityIdentifier("value_radar_top_review")
                } else {
                    Label("Demo only", systemImage: "eye.fill")
                        .appTextRole(.control)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .appSurface(.emphasized)
            .accessibilityIdentifier("value_radar_summary")
        }
    }

    private var rankedItems: some View {
        VStack(alignment: .leading, spacing: AppSpacing.group) {
            AppSectionHeader(
                title: "Menu Ranking",
                subtitle: viewModel.isDemoMode ? "Fictional protein-value examples" : viewModel.comparison.objective.explanation
            )

            VStack(spacing: 0) {
                if !viewModel.isDemoMode {
                    ForEach(viewModel.comparison.ranked(currency: viewModel.rankingCurrency)) { row in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(row.food.name).appTextRole(.control)
                            Text("\(Int(row.food.calories.rounded())) cal · \(Int(row.food.protein.rounded())) g protein · Nutrition estimate")
                                .font(.caption).foregroundStyle(.secondary)
                            if row.currency == viewModel.rankingCurrency, let price = row.validPrice {
                                Text("\(price.formatted(.currency(code: row.currency))) · \((row.food.protein / price).formatted(.number.precision(.fractionLength(1)))) g protein / \(row.currency) 1")
                            } else { Text(row.currency != viewModel.rankingCurrency ? "Different currency — not ranked together" : "Price needs review — not ranked").foregroundStyle(AppPalette.caution) }
                            if !row.priceNote.isEmpty { Text(row.priceNote).font(.caption) }
                            Button("Review price and serving") { priceToReview = row }.frame(minHeight: 44)
                                .accessibilityIdentifier("value_radar_edit_price_\(row.id)")
                            Button("Review nutrition before logging") {
                                guard !viewModel.comparison.isDemo else { return }
                                itemToReview = RestaurantValueRadarItem(food: row.food, basePrice: row.validPrice ?? 1,
                                    cityMultiplier: 1, appliesCityMultiplier: false, canLog: true)
                            }.frame(minHeight: 44)
                        }.padding().accessibilityElement(children: .contain)
                    }
                } else { ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                    RestaurantValueRadarRow(item: item, onReview: { beginReview(item) })
                    if index < viewModel.items.count - 1 {
                        Divider().padding(.leading, 68)
                    }
                } }
            }
            .appSurface(.quiet, padding: 0)
        }
        .accessibilityIdentifier("value_radar_ranked_list")
    }

    private var comparisonControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Restaurant (optional)", text: Binding(get: { viewModel.comparison.restaurantName }, set: { viewModel.setRestaurant($0) }))
                .textFieldStyle(.roundedBorder)
            Text("Scanned \(viewModel.comparison.scannedAt.formatted(date: .abbreviated, time: .shortened)). Prices may have changed. Confirm printed amounts, currency, ranges and add-ons before comparing.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Compare by", selection: Binding(get: { viewModel.comparison.objective }, set: { viewModel.setObjective($0) })) {
                ForEach(RestaurantRankingObjective.allCases) { objective in Text(objective.title).tag(objective) }
            }.accessibilityIdentifier("value_radar_objective")
            Picker("Comparison currency", selection: $viewModel.rankingCurrency) {
                ForEach(Array(Set(viewModel.comparison.rows.map(\.currency))).sorted(), id: \.self) { Text($0).tag($0) }
            }
            if viewModel.comparison.objective == .calorieBudget {
                TextField("Calorie budget", value: Binding(get: { viewModel.comparison.calorieBudget }, set: { viewModel.setCalorieBudget($0) }), format: .number)
                    .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
            }
            Button("Save private comparison on this device") { viewModel.saveComparison() }.frame(minHeight: 44)
            Button("Saved comparisons (\(viewModel.workspace.saved.count))") { showingSavedScans = true }.frame(minHeight: 44)
            if let storageMessage = viewModel.storageMessage { Text(storageMessage).font(.caption).foregroundStyle(AppPalette.caution) }
        }.appSurface(.quiet)
    }

    private var savedComparisons: some View {
        NavigationStack {
            List {
                Section("Private snapshots · this device") {
                    ForEach(viewModel.workspace.saved) { saved in
                        Button { viewModel.openComparison(saved); showingSavedScans = false } label: {
                            VStack(alignment: .leading) {
                                Text(saved.restaurantName.isEmpty ? "Menu comparison" : saved.restaurantName)
                                Text("\(saved.scannedAt.formatted()) · \(saved.rows.count) dishes · Prices may have changed").font(.caption)
                            }
                        }
                    }
                }
            }.appFormStyle().buttonStyle(AppListButtonStyle()).navigationTitle("Saved comparisons")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showingSavedScans = false } } }
        }
    }

    private func beginReview(_ item: RestaurantValueRadarItem) {
        guard item.canLog, !viewModel.isDemoMode else { return }
        guard DIContainer.shared.authService.currentUserID != nil else {
            ToastManager.shared.showToast(
                message: "Sign in before reviewing this estimate for your diary."
            )
            return
        }
        itemToReview = item
    }
}

private struct RestaurantValueRadarRow: View {
    let item: RestaurantValueRadarItem
    let onReview: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.row) {
                    identity
                    metrics
                    reviewControl
                }
            } else {
                HStack(alignment: .center, spacing: AppSpacing.row) {
                    identity
                    Spacer(minLength: AppSpacing.compact)
                    metrics
                    reviewControl
                }
            }
        }
        .padding(.horizontal, AppSpacing.group)
        .padding(.vertical, AppSpacing.row)
        .accessibilityIdentifier("value_radar_item_\(item.id)")
    }

    private var identity: some View {
        HStack(spacing: AppSpacing.row) {
            Image(systemName: item.tierIcon)
                .appFont(size: 18, weight: .semibold)
                .foregroundStyle(item.tierColor)
                .frame(width: 40, height: 40)
                .background(
                    item.tierColor.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: AppRadius.control)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.food.name)
                    .appTextRole(.control)
                    .foregroundStyle(AppPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.nutritionSummary)
                    .appTextRole(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metrics: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
            Text(AYCERules.money(item.adjustedPrice))
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
                .monospacedDigit()
            Text("\(item.proteinPerDollar.formatted(.number.precision(.fractionLength(1)))) g protein / $1")
                .appTextRole(.caption)
                .foregroundStyle(item.tierColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var reviewControl: some View {
        if item.canLog {
            Button(action: onReview) {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(AppIconButtonStyle(.brand))
            .accessibilityLabel("Review \(item.food.name)")
            .accessibilityHint("Edit the nutrition estimate before logging")
        } else if dynamicTypeSize.isAccessibilitySize {
            Text("Demo only")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct RestaurantValueRadarItem: Identifiable {
    let id: String
    let food: FoodItem
    let basePrice: Double
    let cityMultiplier: Double
    let appliesCityMultiplier: Bool
    let canLog: Bool
    let score: RestaurantValueRadarRules.Score
    let currency: String

    init?(
        food: FoodItem,
        basePrice: Double,
        cityMultiplier: Double,
        appliesCityMultiplier: Bool,
        canLog: Bool,
        currency: String = "USD"
    ) {
        let multiplier = appliesCityMultiplier ? cityMultiplier : 1
        guard let score = RestaurantValueRadarRules.score(
            protein: food.protein,
            calories: food.calories,
            listedPrice: basePrice,
            priceMultiplier: multiplier
        ) else {
            return nil
        }

        self.id = food.id
        self.food = food
        self.basePrice = basePrice
        self.cityMultiplier = cityMultiplier
        self.appliesCityMultiplier = appliesCityMultiplier
        self.canLog = canLog
        self.score = score
        self.currency = currency
    }

    var adjustedPrice: Double { score.adjustedPrice }
    var proteinPerDollar: Double { score.proteinPerDollar }
    var proteinPer100Calories: Double { score.proteinPer100Calories }
    var tier: RestaurantValueRadarRules.Tier { score.tier }

    var tierColor: Color {
        switch tier {
        case .highProteinValue: AppPalette.brand
        case .balancedValue: AppPalette.effort
        case .lowerProteinValue: AppPalette.caution
        }
    }

    var tierIcon: String {
        switch tier {
        case .highProteinValue: "chart.line.uptrend.xyaxis"
        case .balancedValue: "equal.circle.fill"
        case .lowerProteinValue: "info.circle.fill"
        }
    }

    var nutritionSummary: String {
        "\(Int(food.calories.rounded()).formatted()) cal · "
            + "\(Int(food.protein.rounded()).formatted()) g protein"
    }

    var metricItems: [AppMetricItem] {
        [
            AppMetricItem(label: "Reviewed Price", value: adjustedPrice.formatted(.currency(code: currency)), accent: AppPalette.brand),
            AppMetricItem(
                label: "Protein / \(currency) 1",
                value: "\(proteinPerDollar.formatted(.number.precision(.fractionLength(1)))) g",
                accent: tierColor
            ),
            AppMetricItem(
                label: "Protein / 100 Cal",
                value: "\(proteinPer100Calories.formatted(.number.precision(.fractionLength(1)))) g",
                accent: AppPalette.protein
            )
        ]
    }
}

protocol RestaurantMenuAnalyzing {
    func estimateMenuItemsWithListedPrices(
        image: UIImage,
        completion: @escaping (Result<[ScannedMenuValueItem], Error>) -> Void
    )
}

extension MLImageModel: RestaurantMenuAnalyzing {}

@MainActor
final class RestaurantValueRadarViewModel: ObservableObject {
    @Published var items: [RestaurantValueRadarItem]
    @Published var isAnalyzing = false
    @Published var errorMessage: String?
    @Published var selectedCity: AYCECity
    @Published var isDemoMode: Bool
    @Published private(set) var comparison = RestaurantComparison()
    @Published private(set) var workspace = RestaurantComparisonWorkspace()
    @Published var rankingCurrency = "USD" { didSet { renderComparison() } }
    @Published private(set) var storageMessage: String?
    @Published private(set) var sourceImage: UIImage?
    private let accountID: String?

    private let imageModel: RestaurantMenuAnalyzing
    private var activeRequestID: UUID?

    init(
        imageModel: RestaurantMenuAnalyzing = MLImageModel(),
        initialItems: [RestaurantValueRadarItem] = [],
        selectedCity: AYCECity? = nil,
        isDemoMode: Bool = false
    ) {
        let savedSlug = UserDefaults.standard.string(forKey: "ayceCitySlug")
            ?? AYCECityIndex.national.slug
        self.imageModel = imageModel
        self.selectedCity = selectedCity ?? AYCECityIndex.city(slug: savedSlug)
        self.items = initialItems
        self.isDemoMode = isDemoMode
        accountID = DIContainer.shared.authService.currentUserID
        if initialItems.isEmpty, !isDemoMode, let accountID {
            do {
                workspace = try RestaurantComparisonStore(userID: accountID).load()
                if let draft = workspace.draft { comparison = draft; renderComparison() }
            } catch { storageMessage = "Saved comparisons could not be read. Their stored data is kept." }
        }
    }

    var regionComparisonText: String {
        let percentage = Int(((selectedCity.restaurantMultiplier - 1) * 100).rounded())
        if percentage == 0 { return "National mid-range baseline" }
        return "\(percentage > 0 ? "+" : "")\(percentage)% vs. national demo pricing"
    }

    func selectCity(_ city: AYCECity) {
        selectedCity = city
        UserDefaults.standard.set(city.slug, forKey: "ayceCitySlug")
        recomputePrices()
    }

    func loadDemoMenu(delay: TimeInterval = 0.35) {
        let requestID = UUID()
        activeRequestID = requestID
        errorMessage = nil
        isDemoMode = true
        isAnalyzing = true

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.activeRequestID == requestID else { return }
            self.items = Self.makeDemoItems(city: self.selectedCity)
            self.isAnalyzing = false
            self.activeRequestID = nil
        }
    }

    func analyzeMenuImage(_ image: UIImage) {
        let requestID = UUID()
        activeRequestID = requestID
        isAnalyzing = true
        errorMessage = nil
        isDemoMode = false
        sourceImage = image

        imageModel.estimateMenuItemsWithListedPrices(image: image) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.activeRequestID == requestID,
                      self.accountID == DIContainer.shared.authService.currentUserID else { return }
                self.isAnalyzing = false
                self.activeRequestID = nil

                switch result {
                case .success(let scannedItems) where !scannedItems.isEmpty:
                    var comparison = RestaurantComparison()
                    comparison.rows = scannedItems.map { item in
                        RestaurantComparisonRow(food: item.food, listedPrice: item.listedPrice > 0 ? item.listedPrice : nil,
                            currency: item.currency?.uppercased() ?? "USD",
                            priceNote: (item.priceText ?? "") + (item.currency == nil ? " · Currency unconfirmed; USD is only an editable starting value." : "") +
                                (item.listedPrice > 0 ? " · Confirm serving and included add-ons" : " · No exact printed price extracted"))
                    }
                    self.comparison = comparison
                    self.renderComparison(); self.keepDraft()
                case .success:
                    self.items = []
                    self.errorMessage = "No dishes with visible prices were found. Try a clearer photo that includes names and printed prices."
                case .failure:
                    self.items = []
                    self.errorMessage = "The menu scan did not go through. Check your connection and try again."
                }
            }
        }
    }

    func updateRow(_ row: RestaurantComparisonRow) {
        guard !isDemoMode, let index = comparison.rows.firstIndex(where: { $0.id == row.id }) else { return }
        comparison.rows[index] = row; renderComparison(); keepDraft()
    }
    func setRestaurant(_ name: String) { comparison.restaurantName = String(name.prefix(200)); keepDraft() }
    func setObjective(_ value: RestaurantRankingObjective) { comparison.objective = value; renderComparison(); keepDraft() }
    func setCalorieBudget(_ value: Double) {
        guard value.isFinite, value > 0, value <= 100_000 else { return }
        comparison.calorieBudget = value; renderComparison(); keepDraft()
    }
    func openComparison(_ value: RestaurantComparison) {
        activeRequestID = nil; isAnalyzing = false; sourceImage = nil; comparison = value; isDemoMode = value.isDemo
        renderComparison(); keepDraft()
    }
    func saveComparison() {
        guard !isDemoMode else { return }
        updateWorkspace { value in value.saved.removeAll { $0.id == comparison.id }; value.saved.insert(comparison, at: 0) }
    }
    private func renderComparison() {
        guard !isDemoMode else { return }
        items = comparison.ranked(currency: rankingCurrency).compactMap { row in
            guard row.currency == rankingCurrency, let price = row.validPrice else { return nil }
            return RestaurantValueRadarItem(food: row.food, basePrice: price, cityMultiplier: 1,
                appliesCityMultiplier: false, canLog: !comparison.isDemo, currency: row.currency)
        }
    }
    private func keepDraft() {
        guard !isDemoMode else { return }
        updateWorkspace { $0.draft = comparison }
    }
    private func updateWorkspace(_ change: (inout RestaurantComparisonWorkspace) -> Void) {
        guard let accountID, accountID == DIContainer.shared.authService.currentUserID else { return }
        do {
            var next = workspace; change(&next)
            try RestaurantComparisonStore(userID: accountID).save(next, replacing: workspace)
            workspace = next; storageMessage = "Private comparison kept on this device."
        } catch { storageMessage = "Could not keep this comparison change. Reopen to load the latest stored copy." }
    }

    static func makeDemoItems(city: AYCECity) -> [RestaurantValueRadarItem] {
        demoDishes.compactMap { dish in
            let food = FoodItem(
                id: dish.id,
                name: dish.name,
                calories: dish.calories,
                protein: dish.protein,
                carbs: dish.carbs,
                fats: dish.fats,
                servingSize: "1 entree"
            ).withAIEstimateSource(.aiMenu, sourceName: "Value Radar Demo")
            return RestaurantValueRadarItem(
                food: food,
                basePrice: dish.price,
                cityMultiplier: city.restaurantMultiplier,
                appliesCityMultiplier: true,
                canLog: false
            )
        }
        .sorted { $0.proteinPerDollar > $1.proteinPerDollar }
    }

    private func recomputePrices() {
        items = items.compactMap { item in
            RestaurantValueRadarItem(
                food: item.food,
                basePrice: item.basePrice,
                cityMultiplier: selectedCity.restaurantMultiplier,
                appliesCityMultiplier: item.appliesCityMultiplier,
                canLog: item.canLog
            )
        }
        .sorted { $0.proteinPerDollar > $1.proteinPerDollar }
    }

    private struct DemoDish {
        let id: String
        let name: String
        let calories: Double
        let protein: Double
        let carbs: Double
        let fats: Double
        let price: Double
    }

    private static let demoDishes: [DemoDish] = [
        DemoDish(
            id: "value-demo-ribeye",
            name: "Ribeye Steak and Asparagus",
            calories: 680,
            protein: 62,
            carbs: 8,
            fats: 44,
            price: 32
        ),
        DemoDish(
            id: "value-demo-salmon",
            name: "Grilled Salmon and Quinoa",
            calories: 540,
            protein: 46,
            carbs: 32,
            fats: 24,
            price: 26
        ),
        DemoDish(
            id: "value-demo-chicken",
            name: "Chicken Breast Piccata",
            calories: 480,
            protein: 52,
            carbs: 12,
            fats: 22,
            price: 22
        ),
        DemoDish(
            id: "value-demo-carbonara",
            name: "Spaghetti Carbonara",
            calories: 820,
            protein: 24,
            carbs: 88,
            fats: 42,
            price: 21
        ),
        DemoDish(
            id: "value-demo-shrimp",
            name: "Caesar Salad with Grilled Shrimp",
            calories: 420,
            protein: 34,
            carbs: 14,
            fats: 26,
            price: 18
        )
    ]
}

#if DEBUG
@MainActor
struct RestaurantValueRadarDemoView: View {
    @StateObject private var viewModel: RestaurantValueRadarViewModel

    init() {
        let city = AYCECityIndex.city(slug: "nyc")
        _viewModel = StateObject(
            wrappedValue: RestaurantValueRadarViewModel(
                initialItems: RestaurantValueRadarViewModel.makeDemoItems(city: city),
                selectedCity: city,
                isDemoMode: true
            )
        )
    }

    var body: some View {
        RestaurantValueRadarView(viewModel: viewModel)
    }
}
#endif

@MainActor
private struct RestaurantPriceReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let row: RestaurantComparisonRow
    let onSave: (RestaurantComparisonRow) -> Void
    let sourceImage: UIImage?
    @State private var price: String
    @State private var currency: String
    @State private var notes: String
    @State private var calories: String
    @State private var protein: String
    @State private var confirmed = false
    @State private var noExactPrice = false
    init(row: RestaurantComparisonRow, sourceImage: UIImage?, onSave: @escaping (RestaurantComparisonRow) -> Void) {
        self.row = row; self.onSave = onSave; self.sourceImage = sourceImage
        _price = State(initialValue: row.listedPrice.map { String($0) } ?? "")
        _currency = State(initialValue: row.currency); _notes = State(initialValue: row.priceNote)
        _calories = State(initialValue: String(row.food.calories)); _protein = State(initialValue: String(row.food.protein))
        _noExactPrice = State(initialValue: row.listedPrice == nil)
    }
    private var reviewed: RestaurantComparisonRow? {
        let normalizedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let calories = AYCESessionInputRules.decimal(from: calories), calories >= 0, calories <= 100_000,
              let protein = AYCESessionInputRules.decimal(from: protein), protein >= 0, protein <= 10_000,
              normalizedCurrency.count == 3, normalizedCurrency.unicodeScalars.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) }) else { return nil }
        let amount = AYCESessionInputRules.decimal(from: price)
        guard noExactPrice || amount.map({ $0 > 0 && $0 < 1_000_000 }) == true else { return nil }
        var value = row; value.food.calories = calories; value.food.protein = protein
        value.listedPrice = noExactPrice ? nil : amount; value.currency = normalizedCurrency
        value.priceNote = String(notes.prefix(1000)); value.priceConfirmed = confirmed && !noExactPrice
        return value
    }
    var body: some View {
        NavigationStack {
            Form {
                if let sourceImage {
                    Section("Source image · kept only while this screen is open") {
                        Image(uiImage: sourceImage).resizable().scaledToFit().accessibilityLabel("Original menu image for price review")
                    }
                } else { Text("No image is retained in saved comparisons. Check the original menu before trusting an old price.").font(.caption) }
                Section(row.food.name) {
                    Text("Serving: \(row.food.servingSize). Review the price for this exact amount. Shared dishes, optional extras and ranges must be resolved explicitly; no exchange rates are applied.")
                    Toggle("No single exact price (range / market price / missing)", isOn: $noExactPrice)
                    if !noExactPrice { TextField("Printed price", text: $price).keyboardType(.decimalPad) }
                    TextField("Currency code, e.g. USD", text: $currency).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    TextField("Included items, add-ons or price evidence", text: $notes, axis: .vertical)
                }
                Section("Nutrition estimate for that serving") {
                    TextField("Calories", text: $calories).keyboardType(.decimalPad)
                    TextField("Protein, grams", text: $protein).keyboardType(.decimalPad)
                    Text("These remain estimates. Price confirmation does not verify the nutrition.").font(.caption)
                }
                Toggle("I reviewed the printed amount, currency and serving", isOn: $confirmed)
                Button("Use reviewed comparison") {
                    guard let reviewed else { return }; onSave(reviewed); dismiss()
                }.disabled(!confirmed || reviewed == nil).frame(minHeight: 44).accessibilityIdentifier("value_radar_confirm_price")
            }.appFormStyle().buttonStyle(AppListButtonStyle()).scrollDismissesKeyboard(.interactively).navigationTitle("Review price")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("value_radar_price_review")
    }
}
