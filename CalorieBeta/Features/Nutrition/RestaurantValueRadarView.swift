import SwiftUI
import MyFitPlateCore

struct RestaurantValueRadarView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var dailyLogService: DailyLogService
    @StateObject private var viewModel = RestaurantValueRadarViewModel()
    @State private var showingImagePicker = false
    @State private var imageSourceType: UIImagePickerController.SourceType = .photoLibrary

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        headerCard
                        if viewModel.items.isEmpty || viewModel.isDemoMode {
                            citySelectorCard
                        }

                        if viewModel.isAnalyzing {
                            loadingView
                        } else if let error = viewModel.errorMessage {
                            errorView(error)
                        } else if viewModel.items.isEmpty {
                            emptyStateView
                        } else {
                            if viewModel.isDemoMode {
                                Text("Demo data only. Prices and nutrition are fictional examples, and logging is disabled.")
                                    .appFont(size: 13, weight: .semibold)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(Color.accentSignal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            }
                            topValueHighlight
                            rankedListSection
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Value Radar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { presentationMode.wrappedValue.dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(sourceType: imageSourceType) { image in
                    viewModel.analyzeMenuImage(image)
                }
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .appFont(size: 30, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))
            Text(message)
                .appFont(size: 14)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .foregroundColor(.brandPrimary)
                    .appFont(size: 24, weight: .bold)
                Text("Restaurant Value Radar")
                    .appFont(size: 20, weight: .bold)
                    .foregroundColor(.textPrimary)
                Spacer()
            }
            Text("Ranks dishes using prices visibly printed on the menu. Nutrition remains an AI estimate and should be reviewed.")
                .appFont(size: 14)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button {
                    imageSourceType = .camera
                    showingImagePicker = true
                } label: {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Scan Menu")
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.brandPrimary)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.loadDemoMenu()
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Demo Menu")
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.backgroundSecondary)
                    .foregroundColor(.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.brandPrimary.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .asCard()
    }

    private var citySelectorCard: some View {
        HStack {
            Image(systemName: "mappin.and.ellipse")
                .foregroundColor(.accentProtein)
            VStack(alignment: .leading, spacing: 2) {
                Text("City Cost Index")
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(.secondary)
                Text("Based on local restaurant pricing index (\(viewModel.selectedCity.restaurantMultiplier > 1.0 ? "+" : "")\(Int((viewModel.selectedCity.restaurantMultiplier - 1.0) * 100))% vs national avg)")
                    .appFont(size: 12)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Menu {
                ForEach(AYCECityIndex.pickerOptions) { city in
                    Button {
                        viewModel.selectCity(city)
                    } label: {
                        HStack {
                            Text(city.name)
                            Spacer()
                            Text("\(String(format: "%.2fx", city.restaurantMultiplier))")
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Change")
                        .appFont(size: 14, weight: .semibold)
                    Image(systemName: "chevron.up.chevron.down")
                        .appFont(size: 12, weight: .bold)
                }
                .foregroundColor(.brandPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.brandPrimary.opacity(0.1), in: Capsule())
            }
        }
        .asCard()
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)
            Text("Analyzing menu & computing local value scores...")
                .appFont(size: 15, weight: .semibold)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .asCard()
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.viewfinder")
                .appFont(size: 40)
                .foregroundColor(.secondary.opacity(0.6))
            Text("No Menu Analyzed Yet")
                .appFont(size: 16, weight: .bold)
                .foregroundColor(.textPrimary)
            Text("Tap 'Scan Menu' to photograph a restaurant menu or try 'Demo Menu' to see instant AI value rankings.")
                .appFont(size: 13)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .asCard()
    }

    private var topValueHighlight: some View {
        Group {
            if let topDish = viewModel.items.first {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("👑 TOP VALUE RECOMMENDATION")
                            .appFont(size: 12, weight: .heavy)
                            .foregroundColor(.accentCarbs)
                        Spacer()
                        Text(topDish.tierBadge)
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(topDish.tierColor.opacity(0.2))
                            .foregroundColor(topDish.tierColor)
                            .clipShape(Capsule())
                    }

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(topDish.food.name)
                                .appFont(size: 20, weight: .bold)
                                .foregroundColor(.textPrimary)
                            Text("\(Int(topDish.food.calories)) cal • \(Int(topDish.food.protein))g P • \(Int(topDish.food.carbs))g C • \(Int(topDish.food.fats))g F")
                                .appFont(size: 14)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "$%.2f", topDish.adjustedPrice))
                                .appFont(size: 20, weight: .heavy)
                                .foregroundColor(.brandPrimary)
                            Text("\(String(format: "%.1f", topDish.proteinPerDollar))g P / $")
                                .appFont(size: 12, weight: .bold)
                                .foregroundColor(.accentProtein)
                        }
                    }

                    if topDish.canLog {
                        Button {
                            logDish(topDish.food)
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Review & Log Top Pick")
                            }
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.brandPrimary)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    } else {
                        Label("Demo only", systemImage: "eye.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
                .background(
                    LinearGradient(colors: [Color.brandPrimary.opacity(0.15), Color.backgroundSecondary], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.brandPrimary.opacity(0.4), lineWidth: 1.5)
                )
            }
        }
    }

    private var rankedListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All Menu Items Ranked by Protein / Dollar")
                .appFont(size: 16, weight: .bold)
                .foregroundColor(.textPrimary)

            ForEach(viewModel.items) { item in
                dishRowCard(item)
            }
        }
    }

    private func dishRowCard(_ item: RestaurantValueRadarItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(item.food.name)
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text(item.tierBadge)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(item.tierColor.opacity(0.15))
                            .foregroundColor(item.tierColor)
                            .clipShape(Capsule())
                    }
                    Text("\(Int(item.food.calories)) kcal • \(Int(item.food.protein))g P • $\(String(format: "%.2f", item.adjustedPrice))")
                        .appFont(size: 13)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Value Score")
                        .appFont(size: 11)
                        .foregroundColor(.secondary)
                    Text("\(String(format: "%.1f", item.proteinPerDollar))g P / $")
                        .appFont(size: 15, weight: .bold)
                        .foregroundColor(item.tierColor)
                }

                if item.canLog {
                    Button {
                        logDish(item.food)
                    } label: {
                        Text("Review")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.brandPrimary)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 8)
                }
            }
        }
        .asCard()
    }

    private func logDish(_ food: FoodItem) {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            viewModel.errorMessage = "Sign in again before logging this item."
            return
        }
        viewModel.logDish(food, service: dailyLogService, userID: userID)
        presentationMode.wrappedValue.dismiss()
    }
}

struct RestaurantValueRadarItem: Identifiable {
    let id = UUID()
    let food: FoodItem
    let basePrice: Double
    let cityMultiplier: Double
    let appliesCityMultiplier: Bool
    let canLog: Bool

    var adjustedPrice: Double {
        max(1.0, basePrice * (appliesCityMultiplier ? cityMultiplier : 1))
    }

    var proteinPerDollar: Double {
        food.protein / adjustedPrice
    }

    var tierBadge: String {
        if proteinPerDollar >= 2.2 { return "🔥 Elite Anabolic" }
        if proteinPerDollar >= 1.5 { return "✅ Great Balance" }
        return "🍝 Low Protein / $"
    }

    var tierColor: Color {
        if proteinPerDollar >= 2.2 { return .brandPrimary }
        if proteinPerDollar >= 1.5 { return .accentProtein }
        return .accentSignal
    }
}

@MainActor
class RestaurantValueRadarViewModel: ObservableObject {
    @Published var items: [RestaurantValueRadarItem] = []
    @Published var isAnalyzing = false
    @Published var errorMessage: String?
    @Published var selectedCity: AYCECity = AYCECityIndex.national
    @Published var isDemoMode = false

    private let imageModel = MLImageModel()

    init() {
        let savedSlug = UserDefaults.standard.string(forKey: "ayceCitySlug") ?? "us_average"
        self.selectedCity = AYCECityIndex.city(slug: savedSlug)
    }

    func selectCity(_ city: AYCECity) {
        self.selectedCity = city
        UserDefaults.standard.set(city.slug, forKey: "ayceCitySlug")
        recomputePrices()
    }

    private func recomputePrices() {
        self.items = self.items.map { item in
            RestaurantValueRadarItem(
                food: item.food,
                basePrice: item.basePrice,
                cityMultiplier: selectedCity.restaurantMultiplier,
                appliesCityMultiplier: item.appliesCityMultiplier,
                canLog: item.canLog
            )
        }.sorted(by: { $0.proteinPerDollar > $1.proteinPerDollar })
    }

    func loadDemoMenu() {
        self.errorMessage = nil
        self.isDemoMode = true
        self.isAnalyzing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            struct DemoDish {
                let name: String
                let cal: Double
                let p: Double
                let c: Double
                let f: Double
                let price: Double
            }

            let demoDishes: [DemoDish] = [
                DemoDish(name: "12oz Ribeye Steak & Asparagus", cal: 680, p: 62, c: 8, f: 44, price: 32.0),
                DemoDish(name: "Grilled Salmon & Quinoa", cal: 540, p: 46, c: 32, f: 24, price: 26.0),
                DemoDish(name: "Chicken Breast Piccata", cal: 480, p: 52, c: 12, f: 22, price: 22.0),
                DemoDish(name: "Spaghetti Carbonara", cal: 820, p: 24, c: 88, f: 42, price: 21.0),
                DemoDish(name: "Caesar Salad with Grilled Shrimp", cal: 420, p: 34, c: 14, f: 26, price: 18.0),
                DemoDish(name: "Margherita Pizza (1/2 Pie)", cal: 650, p: 22, c: 74, f: 28, price: 17.0)
            ]

            let newItems = demoDishes.map { dish in
                let food = FoodItem(name: dish.name, calories: dish.cal, protein: dish.p, carbs: dish.c, fats: dish.f, servingSize: "1 entree")
                return RestaurantValueRadarItem(
                    food: food,
                    basePrice: dish.price,
                    cityMultiplier: self.selectedCity.restaurantMultiplier,
                    appliesCityMultiplier: true,
                    canLog: false
                )
            }.sorted(by: { $0.proteinPerDollar > $1.proteinPerDollar })

            self.items = newItems
            self.isAnalyzing = false
        }
    }

    func analyzeMenuImage(_ image: UIImage) {
        self.isAnalyzing = true
        self.errorMessage = nil
        self.isDemoMode = false
        imageModel.estimateMenuItemsWithListedPrices(image: image) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isAnalyzing = false
                switch result {
                case .success(let scannedItems) where !scannedItems.isEmpty:
                    let newItems = scannedItems.map { item in
                        RestaurantValueRadarItem(
                            food: item.food,
                            basePrice: item.listedPrice,
                            cityMultiplier: 1,
                            appliesCityMultiplier: false,
                            canLog: true
                        )
                    }.sorted(by: { $0.proteinPerDollar > $1.proteinPerDollar })
                    self.items = newItems
                case .success:
                    // Never substitute fabricated demo dishes for a real scan — the user
                    // could log food they never ate. Be honest that nothing was read.
                    self.errorMessage = "Couldn't read dishes with visible prices. Try a clearer photo that includes item names and printed prices."
                case .failure:
                    self.errorMessage = "Menu scan didn't go through. Check your connection and try again."
                }
            }
        }
    }

    func logDish(_ food: FoodItem, service: DailyLogService, userID: String) {
        service.addFoodToLog(
            for: userID,
            date: Date(),
            mealName: DailyLogRules.determineMealType(),
            foodItem: food,
            source: "value_radar"
        )
    }
}
