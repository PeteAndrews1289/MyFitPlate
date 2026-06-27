import SwiftUI
import FirebaseAuth

struct GroceryListView: View {
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @Environment(\.dismiss) var dismiss
    
    @State private var groceryList: [GroceryListItem] = []
    @State private var isLoading = true
    @State private var showingBarcodeScanner = false
    @State private var showingManualItemSheet = false
    @State private var isFetchingItemName = false
    @State private var showingClearConfirmation = false
    @State private var hideCompletedItems = false
    @State private var fetchError: (isShowing: Bool, message: String) = (false, "")
    @State private var editingItem: GroceryListItem?
    
    @AppStorage("groceryUnitSystem") private var unitSystem: GroceryUnitSystem = Locale.current.measurementSystem == .us ? .imperial : .metric
    
    private let foodAPIService = FatSecretFoodAPIService()
    private let usdaService = USDAFoodAPIService()

    private var displayedList: [GroceryListItem] {
        hideCompletedItems ? groceryList.filter { !$0.isCompleted } : groceryList
    }

    private var groupedList: [String: [GroceryListItem]] {
        Dictionary(grouping: displayedList, by: { $0.category })
    }
    
    private var shareText: String {
        let items = groceryList.filter { !$0.isCompleted }
        guard !items.isEmpty else { return "My Grocery List is empty!" }
        let grouped = Dictionary(grouping: items, by: { $0.category })
        var text = "🛒 Grocery List\n"
        for category in grouped.keys.sorted() {
            text += "\n\(category):\n"
            if let groupItems = grouped[category] {
                for item in groupItems.sorted(by: { $0.name < $1.name }) {
                    let formatter = NumberFormatter()
                    formatter.maximumFractionDigits = 2
                    let q = formatter.string(from: NSNumber(value: item.quantity)) ?? "\(item.quantity)"
                    let unit = item.unit == "item" ? "" : item.unit
                    text += "• \(item.name.capitalized) \(q) \(unit)\n"
                }
            }
        }
        return text
    }
    
    private var sortedCategories: [String] {
        let customOrder = [
            "Produce",
            "Meat & Seafood",
            "Dairy & Eggs",
            "Carbohydrates",
            "Pantry & Oils",
            "Spices & Seasonings",
            "Bakery",
            "Misc"
        ]
        
        return groupedList.keys.sorted { first, second in
            let index1 = customOrder.firstIndex(of: first) ?? 99
            let index2 = customOrder.firstIndex(of: second) ?? 99
            
            if index1 == index2 {
                return first < second
            }
            return index1 < index2
        }
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 16) {
                    if isLoading {
                        GroceryListLoadingState()
                    } else if !groceryList.isEmpty {
                        GrocerySummaryCard(
                            items: groceryList,
                            onScan: { showingBarcodeScanner = true },
                            onAddManual: { showingManualItemSheet = true }
                        )

                        GroceryListDisplayControls(
                            completedCount: groceryList.filter(\.isCompleted).count,
                            hideCompletedItems: $hideCompletedItems
                        )

                        if sortedCategories.isEmpty {
                            GroceryAllCompleteState {
                                hideCompletedItems = false
                            }
                        } else {
                            ForEach(sortedCategories, id: \.self) { category in
                                GroceryCategorySection(
                                    category: category,
                                    items: orderedItems(for: category),
                                    groceryList: $groceryList,
                                    onToggle: saveList,
                                    onEdit: { item in editingItem = item },
                                    onDelete: deleteItem
                                )
                            }
                        }
                    } else {
                        GroceryListEmptyState(
                            onScan: { showingBarcodeScanner = true },
                            onAddManual: { showingManualItemSheet = true }
                        )
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Grocery List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: { showingBarcodeScanner = true }) {
                            Image(systemName: "barcode.viewfinder")
                        }
                        .accessibilityLabel("Scan barcode")
                        
                        Button(action: { showingManualItemSheet = true }) {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add grocery item")

                        if !groceryList.isEmpty {
                            Menu {
                                ShareLink(item: shareText) {
                                    Label("Share List", systemImage: "square.and.arrow.up")
                                }
                                
                                Picker(selection: $unitSystem, label: Text("Units")) {
                                    Text("Imperial (lbs, oz)").tag(GroceryUnitSystem.imperial)
                                    Text("Metric (kg, g)").tag(GroceryUnitSystem.metric)
                                }
                                
                                if groceryList.contains(where: \.isCompleted) {
                                    Button(role: .destructive, action: clearCompleted) {
                                        Label("Clear Completed", systemImage: "checkmark.circle.badge.xmark")
                                    }
                                }
                                
                                Button(role: .destructive, action: { showingClearConfirmation = true }) {
                                    Label("Clear All", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingManualItemSheet) {
                ManualGroceryItemSheet { item in
                    addManualItem(item)
                }
            }
            .sheet(item: $editingItem) { itemToEdit in
                ManualGroceryItemSheet(initialItem: itemToEdit) { updatedItem in
                    updateManualItem(updatedItem)
                }
            }
            .sheet(isPresented: $showingBarcodeScanner) {
                BarcodeScannerView { barcode in
                    showingBarcodeScanner = false
                    isFetchingItemName = true
                    AnalyticsManager.log(.barcodeScanned)
                    Task { @MainActor in
                        if let item = await withCheckedContinuation({ cont in
                            foodAPIService.fetchFoodByBarcode(barcode: barcode) { cont.resume(returning: try? $0.get()) }
                        }) {
                            isFetchingItemName = false
                            addBarcodeItem(item)
                            saveList()
                            return
                        }
                        if let item = await usdaService.lookupBarcode(barcode) {
                            isFetchingItemName = false
                            addBarcodeItem(item)
                            saveList()
                            return
                        }
                        isFetchingItemName = false
                        fetchError = (true, "No food found for that barcode.")
                    }
                }
            }
            .alert("Barcode Error", isPresented: $fetchError.isShowing) {
                Button("OK") {}
            } message: {
                Text(fetchError.message)
            }
            .confirmationDialog(
                "Clear grocery list?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear List", role: .destructive, action: clearList)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes every item currently on your grocery list.")
            }
            .onAppear {
                Task {
                    await loadList()
                }
            }
            
            if isFetchingItemName {
                Color.black.opacity(0.36)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.brandPrimary)

                    VStack(spacing: 3) {
                        Text("Finding item")
                            .appFont(size: 17, weight: .bold)
                            .foregroundColor(.textPrimary)

                        Text("Looking up that barcode...")
                            .appFont(size: 13, weight: .medium)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                }
                .padding(24)
                .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
            }
        }
    }
    
    private func orderedItems(for category: String) -> [GroceryListItem] {
        (groupedList[category] ?? []).sorted { first, second in
            if first.isCompleted != second.isCompleted {
                return !first.isCompleted
            }
            return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
        }
    }

    private func deleteItem(_ item: GroceryListItem) {
        groceryList.removeAll { $0.id == item.id }
        saveList()
        HapticManager.instance.feedback(.light)
    }

    private func addBarcodeItem(_ foodItem: FoodItem) {
        if let existingIndex = groceryList.firstIndex(where: {
            $0.name.caseInsensitiveCompare(foodItem.name) == .orderedSame
        }) {
            groceryList[existingIndex].quantity += 1
            groceryList[existingIndex].isCompleted = false
        } else {
            let newItem = GroceryListItem(name: foodItem.name, quantity: 1, unit: "item", category: "Misc", source: "barcode")
            groceryList.append(newItem)
        }
        HapticManager.instance.feedback(.medium)
    }

    private func addManualItem(_ item: GroceryListItem) {
        if let existingIndex = groceryList.firstIndex(where: {
            $0.name.caseInsensitiveCompare(item.name) == .orderedSame &&
            $0.unit.caseInsensitiveCompare(item.unit) == .orderedSame
        }) {
            groceryList[existingIndex].quantity += item.quantity
            groceryList[existingIndex].isCompleted = false
        } else {
            groceryList.append(item)
        }
        saveList()
        HapticManager.instance.feedback(.medium)
    }

    private func updateManualItem(_ item: GroceryListItem) {
        if let existingIndex = groceryList.firstIndex(where: { $0.id == item.id }) {
            groceryList[existingIndex] = item
            saveList()
            HapticManager.instance.feedback(.medium)
        }
    }
    
    private func loadList() async {
        guard let userID = Auth.auth().currentUser?.uid else {
            self.isLoading = false
            return
        }
        self.groceryList = await mealPlannerService.fetchGroceryList(for: userID)
        self.isLoading = false
    }
    
    private func saveList() {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        mealPlannerService.saveGroceryList(groceryList, for: userID)
    }

    private func clearCompleted() {
        groceryList.removeAll { $0.isCompleted }
        saveList()
        HapticManager.instance.feedback(.medium)
    }

    private func clearList() {
        groceryList = []
        saveList()
        HapticManager.instance.feedback(.medium)
    }
}

private struct GrocerySummaryCard: View {
    let items: [GroceryListItem]
    let onScan: () -> Void
    let onAddManual: () -> Void

    private var totalCount: Int {
        items.count
    }

    private var completedCount: Int {
        items.filter(\.isCompleted).count
    }

    private var remainingCount: Int {
        max(totalCount - completedCount, 0)
    }

    private var categoryCount: Int {
        Set(items.map(\.category)).count
    }

    private var progress: CGFloat {
        guard totalCount > 0 else { return 0 }
        return CGFloat(Double(completedCount) / Double(totalCount))
    }

    private var categoryLabel: String {
        categoryCount == 1 ? "category" : "categories"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shopping Run")
                        .appFont(size: 24, weight: .bold)
                        .foregroundColor(.textPrimary)

                    Text("\(remainingCount) left across \(categoryCount) \(categoryLabel).")
                        .appFont(size: 13, weight: .medium)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: onAddManual) {
                        Image(systemName: "plus")
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.brandPrimary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add grocery item")

                    Button(action: onScan) {
                        Image(systemName: "barcode.viewfinder")
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(.brandPrimary)
                            .frame(width: 42, height: 42)
                            .background(Color.brandPrimary.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Scan barcode")
                }
            }

            HStack(spacing: 10) {
                GroceryMetricTile(title: "Items", value: "\(totalCount)", color: .brandPrimary)
                GroceryMetricTile(title: "Done", value: "\(completedCount)", color: .accentPositive)
                GroceryMetricTile(title: "Left", value: "\(remainingCount)", color: .orange)
            }

            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))

                        Capsule()
                            .fill(Color.accentPositive)
                            .frame(width: geometry.size.width * progress)
                    }
                }
                .frame(height: 8)

                Text(completedCount == totalCount ? "All set for this list." : "\(Int((progress * 100).rounded()))% checked off")
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
            }
        }
        .padding(.vertical, 2)
        .glassCard()
    }
}

private struct GroceryMetricTile: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .appFont(size: 21, weight: .bold)
                .foregroundColor(color)
                .lineLimit(1)

            Text(title)
                .appFont(size: 11, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct GroceryListDisplayControls: View {
    let completedCount: Int
    @Binding var hideCompletedItems: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button {
                hideCompletedItems.toggle()
                HapticManager.instance.feedback(.light)
            } label: {
                Label(
                    hideCompletedItems ? "Show Done" : "Hide Done",
                    systemImage: hideCompletedItems ? "eye.fill" : "eye.slash.fill"
                )
                .appFont(size: 13, weight: .bold)
                .foregroundColor(completedCount == 0 ? Color(UIColor.tertiaryLabel) : .brandPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.backgroundSecondary.opacity(0.76), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(completedCount == 0)

            Text("\(completedCount) checked")
                .appFont(size: 13, weight: .bold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.backgroundSecondary.opacity(0.76), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
    }
}

private struct GroceryAllCompleteState: View {
    let onShowCompleted: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .appFont(size: 30, weight: .bold)
                .foregroundColor(.accentPositive)
                .frame(width: 58, height: 58)
                .background(Color.accentPositive.opacity(0.12), in: Circle())

            VStack(spacing: 4) {
                Text("Everything visible is checked off")
                    .appFont(size: 17, weight: .bold)
                    .foregroundColor(.textPrimary)

                Text("Completed items are hidden for a cleaner shopping run.")
                    .appFont(size: 13, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.center)
            }

            Button("Show Checked Items", action: onShowCompleted)
                .buttonStyle(SecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .glassCard()
    }
}

private struct GroceryCategorySection: View {
    let category: String
    let items: [GroceryListItem]
    @Binding var groceryList: [GroceryListItem]
    let onToggle: () -> Void
    let onEdit: (GroceryListItem) -> Void
    let onDelete: (GroceryListItem) -> Void

    private var remainingCount: Int {
        items.filter { !$0.isCompleted }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(category)
                    .appFont(size: 19, weight: .bold)
                    .foregroundColor(.textPrimary)

                Spacer()

                Text("\(remainingCount) left")
                    .appFont(size: 12, weight: .bold)
                    .foregroundColor(remainingCount == 0 ? .accentPositive : Color(UIColor.secondaryLabel))
            }
            .padding(.horizontal, 2)

            VStack(spacing: 10) {
                ForEach(items) { item in
                    if let index = groceryList.firstIndex(where: { $0.id == item.id }) {
                        GroceryItemRow(
                            item: $groceryList[index],
                            onToggle: onToggle,
                            onEdit: { onEdit(item) },
                            onDelete: { onDelete(item) }
                        )
                    }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: groceryList)
        }
    }
}

private struct GroceryItemRow: View {
    @Binding var item: GroceryListItem
    var onToggle: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    
    private var quantityText: String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        
        if item.quantity == floor(item.quantity) {
             formatter.maximumFractionDigits = 0
        }

        let formattedQuantity = formatter.string(from: NSNumber(value: item.quantity)) ?? "\(item.quantity)"
        let unit = item.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUnit = unit.lowercased()
        
        if item.quantity <= 0 {
            return normalizedUnit == "to taste" ? "to taste" : nil
        }

        if normalizedUnit == "to taste" {
            return "to taste"
        }

        if normalizedUnit == "item" || unit.isEmpty {
            return item.quantity == 1 ? "1 item" : "\(formattedQuantity) items"
        }

        if normalizedUnit == "meal use" {
            return item.quantity == 1 ? "1 use" : "\(formattedQuantity) uses"
        }
        
        return "\(formattedQuantity) \(unit)"
    }

    private var sourceText: String? {
        if item.source == "manual" {
            return "Manual"
        }

        if item.source == "barcode" {
            return "Scanned"
        }

        if item.source == nil && item.unit.lowercased() == "item" && item.category == "Misc" {
            return "Scanned"
        }

        return nil
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    toggleCompleted()
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .appFont(size: 20, weight: .semibold)
                        .foregroundColor(item.isCompleted ? .accentPositive : Color(UIColor.tertiaryLabel))
                        .scaleEffect(item.isCompleted ? 1.15 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: item.isCompleted)

                    Text(FoodEmojiMapper.getEmoji(for: item.name))
                        .appFont(size: 24)
                        .frame(width: 44, height: 44)
                        .background(Color.brandPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .opacity(item.isCompleted ? 0.6 : 1.0)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name.capitalized)
                            .appFont(size: 15, weight: .bold)
                            .foregroundColor(item.isCompleted ? Color(UIColor.secondaryLabel) : .textPrimary)
                            .strikethrough(item.isCompleted, color: Color(UIColor.secondaryLabel))
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            if let quantityText {
                                Text(quantityText)
                                    .appFont(size: 12, weight: .bold)
                                    .foregroundColor(.brandPrimary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.brandPrimary.opacity(0.10), in: Capsule())
                            }

                            if let sourceText {
                                Text(sourceText)
                                    .appFont(size: 12, weight: .bold)
                                    .foregroundColor(.accentCarbs)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.accentCarbs.opacity(0.10), in: Capsule())
                            }
                        }
                    }

                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "Mark \(item.name) incomplete" : "Mark \(item.name) complete")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .appFont(size: 14, weight: .semibold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(item.name)")
        }
        .padding(12)
        .background(
            (item.isCompleted ? Color.backgroundSecondary.opacity(0.46) : Color.backgroundSecondary.opacity(0.78)),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(item.isCompleted ? Color.accentPositive.opacity(0.16) : Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private func toggleCompleted() {
        item.isCompleted.toggle()
        onToggle()
        HapticManager.instance.feedback(.light)
    }
}

private struct GroceryListLoadingState: View {
    var body: some View {
        VStack(spacing: 13) {
            ProgressView()
                .tint(.brandPrimary)

            Text("Loading grocery list")
                .appFont(size: 17, weight: .bold)
                .foregroundColor(.textPrimary)

            Text("Pulling together your planned ingredients.")
                .appFont(size: 13, weight: .medium)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }
}

private struct GroceryListEmptyState: View {
    let onScan: () -> Void
    let onAddManual: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cart.fill")
                .appFont(size: 39, weight: .bold)
                .foregroundColor(.brandPrimary)
                .frame(width: 76, height: 76)
                .background(Color.brandPrimary.opacity(0.12), in: Circle())

            VStack(spacing: 5) {
                Text("No grocery list yet")
                    .appFont(size: 22, weight: .bold)
                    .foregroundColor(.textPrimary)

                Text("Generate a meal plan to build one automatically, add an item, or scan as you shop.")
                    .appFont(size: 14, weight: .medium)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Button(action: onAddManual) {
                    Label("Add Item", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(action: onScan) {
                    Label("Scan Barcode", systemImage: "barcode.viewfinder")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 40)
        .glassCard()
    }
}

private struct ManualGroceryItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var quantity = "1"
    @State private var unit = "item"
    @State private var category = "Misc"

    var initialItem: GroceryListItem? = nil
    let onAdd: (GroceryListItem) -> Void

    private let categories = ["Produce", "Protein", "Carbohydrates", "Dairy", "Pantry", "Misc"]
    private let units = ["item", "meal use", "oz", "lb", "g", "cup", "tbsp", "tsp", "serving"]

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var quantityValue: Double {
        let normalized = quantity.replacingOccurrences(of: ",", with: ".")
        return max(Double(normalized) ?? 1, 0)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "cart.badge.plus")
                                .appFont(size: 18, weight: .bold)
                                .foregroundColor(.brandPrimary)
                                .frame(width: 42, height: 42)
                                .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(initialItem == nil ? "Add Grocery Item" : "Edit Grocery Item")
                                    .appFont(size: 24, weight: .bold)
                                    .foregroundColor(.textPrimary)

                                Text(initialItem == nil ? "Add anything you need outside the generated meal plan." : "Update this item's details.")
                                    .appFont(size: 13, weight: .medium)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                            }
                        }
                    }
                    .padding(18)
                    .background(Color.backgroundSecondary.opacity(0.84), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Item")
                            .appFont(size: 15, weight: .bold)
                            .foregroundColor(.textPrimary)

                        TextField("Chicken breast, blueberries, paper towels...", text: $name)
                            .textInputAutocapitalization(.words)
                            .padding(14)
                            .background(Color.backgroundPrimary.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        HStack(spacing: 10) {
                            TextField("Qty", text: $quantity)
                                .keyboardType(.decimalPad)
                                .padding(14)
                                .background(Color.backgroundPrimary.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .frame(maxWidth: 100)

                            Picker("Unit", selection: $unit) {
                                ForEach(units, id: \.self) { unit in
                                    Text(unit).tag(unit)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.backgroundPrimary.opacity(0.64), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .padding(16)
                    .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Category")
                            .appFont(size: 15, weight: .bold)
                            .foregroundColor(.textPrimary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(categories, id: \.self) { option in
                                Button {
                                    category = option
                                    HapticManager.instance.feedback(.light)
                                } label: {
                                    Text(option)
                                        .appFont(size: 13, weight: .bold)
                                        .foregroundColor(category == option ? .brandPrimary : Color(UIColor.secondaryLabel))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(
                                            category == option ? Color.brandPrimary.opacity(0.14) : Color.backgroundPrimary.opacity(0.58),
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.backgroundSecondary.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .padding(16)
                .padding(.bottom, 86)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Manual Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(initialItem == nil ? "Add Item" : "Save Changes") {
                    var newItem = initialItem ?? GroceryListItem(
                        name: trimmedName,
                        quantity: quantityValue,
                        unit: unit,
                        category: category,
                        source: "manual"
                    )
                    if initialItem != nil {
                        newItem.name = trimmedName
                        newItem.quantity = quantityValue
                        newItem.unit = unit
                        newItem.category = category
                    }
                    onAdd(newItem)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSave)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .background(Color.backgroundPrimary.opacity(0.98).ignoresSafeArea(edges: .bottom))
            }
        }
        .onAppear {
            if let item = initialItem {
                name = item.name
                let formatter = NumberFormatter()
                formatter.maximumFractionDigits = 2
                if item.quantity == floor(item.quantity) {
                    formatter.maximumFractionDigits = 0
                }
                quantity = formatter.string(from: NSNumber(value: item.quantity)) ?? "\(item.quantity)"
                unit = item.unit
                category = item.category
            }
        }
    }
}
