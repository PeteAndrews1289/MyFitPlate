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

    init() {
        _viewModel = StateObject(wrappedValue: RestaurantValueRadarViewModel())
    }

    init(viewModel: RestaurantValueRadarViewModel) {
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
                mealName: item.food.name,
                source: "value_radar",
                isAIEstimate: true,
                reviewTitle: "Review Menu Estimate"
            )
            .environmentObject(dailyLogService)
        }
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
        } else if viewModel.items.isEmpty {
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
                .foregroundStyle(.orange)
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
                .foregroundStyle(AppPalette.brand)
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
            iconColor: .orange,
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
                    title: "Top Protein Value",
                    subtitle: item.tier.label
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
                subtitle: "Sorted by estimated grams of protein per printed-price dollar"
            )

            VStack(spacing: 0) {
                ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                    RestaurantValueRadarRow(item: item, onReview: { beginReview(item) })
                    if index < viewModel.items.count - 1 {
                        Divider().padding(.leading, 68)
                    }
                }
            }
            .appSurface(.quiet, padding: 0)
        }
        .accessibilityIdentifier("value_radar_ranked_list")
    }

    private func beginReview(_ item: RestaurantValueRadarItem) {
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

    init?(
        food: FoodItem,
        basePrice: Double,
        cityMultiplier: Double,
        appliesCityMultiplier: Bool,
        canLog: Bool
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
    }

    var adjustedPrice: Double { score.adjustedPrice }
    var proteinPerDollar: Double { score.proteinPerDollar }
    var proteinPer100Calories: Double { score.proteinPer100Calories }
    var tier: RestaurantValueRadarRules.Tier { score.tier }

    var tierColor: Color {
        switch tier {
        case .highProteinValue: AppPalette.brand
        case .balancedValue: .blue
        case .lowerProteinValue: .orange
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
            AppMetricItem(label: "Printed Price", value: AYCERules.money(adjustedPrice), accent: AppPalette.brand),
            AppMetricItem(
                label: "Protein / $1",
                value: "\(proteinPerDollar.formatted(.number.precision(.fractionLength(1)))) g",
                accent: tierColor
            ),
            AppMetricItem(
                label: "Protein / 100 Cal",
                value: "\(proteinPer100Calories.formatted(.number.precision(.fractionLength(1)))) g",
                accent: .orange
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

        imageModel.estimateMenuItemsWithListedPrices(image: image) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.activeRequestID == requestID else { return }
                self.isAnalyzing = false
                self.activeRequestID = nil

                switch result {
                case .success(let scannedItems) where !scannedItems.isEmpty:
                    self.items = scannedItems.compactMap { item in
                        RestaurantValueRadarItem(
                            food: item.food,
                            basePrice: item.listedPrice,
                            cityMultiplier: 1,
                            appliesCityMultiplier: false,
                            canLog: true
                        )
                    }
                    .sorted { $0.proteinPerDollar > $1.proteinPerDollar }
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
