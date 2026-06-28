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

