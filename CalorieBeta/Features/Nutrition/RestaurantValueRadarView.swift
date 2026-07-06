import SwiftUI
import MyFitPlateCore

struct RestaurantValueRadarView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var dailyLogService: DailyLogService
    @AppStorage("userID") var userID = "defaultUser"
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
                        citySelectorCard

                        if viewModel.isAnalyzing {
                            loadingView
                        } else if let error = viewModel.errorMessage {
                            errorView(error)
                        } else if viewModel.items.isEmpty {
                            emptyStateView
                        } else {
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
            Text("AI scanner that ranks menu dishes by Protein-to-Dollar and Macro Value adjusted for local dining costs.")
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

                    Button {
                        viewModel.logDish(topDish.food, service: dailyLogService, userID: userID)
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Log Top Pick")
                        }
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.brandPrimary)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
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

                Button {
                    viewModel.logDish(item.food, service: dailyLogService, userID: userID)
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Text("Log")
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
        .asCard()
    }
}

struct RestaurantValueRadarItem: Identifiable {
    let id = UUID()
    let food: FoodItem
    let basePrice: Double
    let cityMultiplier: Double

    var adjustedPrice: Double {
        max(1.0, basePrice * cityMultiplier)
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
            RestaurantValueRadarItem(food: item.food, basePrice: item.basePrice, cityMultiplier: selectedCity.restaurantMultiplier)
        }.sorted(by: { $0.proteinPerDollar > $1.proteinPerDollar })
    }

    func loadDemoMenu() {
        self.errorMessage = nil
        self.isAnalyzing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let demoDishes: [(String, Double, Double, Double, Double, Double)] = [
                ("12oz Ribeye Steak & Asparagus", 680, 62, 8, 44, 32.0),
                ("Grilled Salmon & Quinoa", 540, 46, 32, 24, 26.0),
                ("Chicken Breast Piccata", 480, 52, 12, 22, 22.0),
                ("Spaghetti Carbonara", 820, 24, 88, 42, 21.0),
                ("Caesar Salad with Grilled Shrimp", 420, 34, 14, 26, 18.0),
                ("Margherita Pizza (1/2 Pie)", 650, 22, 74, 28, 17.0)
            ]

            let newItems = demoDishes.map { name, cal, p, c, f, price in
                let food = FoodItem(name: name, calories: cal, protein: p, carbs: c, fats: f, servingSize: "1 entree")
                return RestaurantValueRadarItem(food: food, basePrice: price, cityMultiplier: self.selectedCity.restaurantMultiplier)
            }.sorted(by: { $0.proteinPerDollar > $1.proteinPerDollar })

            self.items = newItems
            self.isAnalyzing = false
        }
    }

    func analyzeMenuImage(_ image: UIImage) {
        self.isAnalyzing = true
        self.errorMessage = nil
        imageModel.estimateMenuFromImage(image: image) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isAnalyzing = false
                switch result {
                case .success(let foods) where !foods.isEmpty:
                    // Menu photos don't reliably carry prices, so the base price is an
                    // estimate from the dish's own macros — the value score is a heuristic,
                    // not a real receipt.
                    let newItems = foods.map { food in
                        let estimatedBasePrice = max(12.0, (food.protein * 0.35) + (food.calories * 0.015))
                        return RestaurantValueRadarItem(food: food, basePrice: estimatedBasePrice, cityMultiplier: self.selectedCity.restaurantMultiplier)
                    }.sorted(by: { $0.proteinPerDollar > $1.proteinPerDollar })
                    self.items = newItems
                case .success:
                    // Never substitute fabricated demo dishes for a real scan — the user
                    // could log food they never ate. Be honest that nothing was read.
                    self.errorMessage = "Couldn't read any dishes from that photo. Try a clearer shot of the menu, or use Demo Menu to see how it works."
                case .failure:
                    self.errorMessage = "Menu scan didn't go through. Check your connection and try again."
                }
            }
        }
    }

    func logDish(_ food: FoodItem, service: DailyLogService, userID: String) {
        let mealName = UserDefaults.standard.string(forKey: "lastLoggedMeal") ?? "Dinner"
        service.addFoodToLog(for: userID, date: Date(), mealName: mealName, foodItem: food, source: "ValueRadar")
    }
}
