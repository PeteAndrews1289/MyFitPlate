import SwiftUI

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
    @State private var pendingMissedBarcode: String?
    @State private var fetchError: (isShowing: Bool, message: String) = (false, "")
    @State private var editingItem: GroceryListItem?
    
    @AppStorage("groceryUnitSystem") private var unitSystem: GroceryUnitSystem = Locale.current.measurementSystem == .us ? .imperial : .metric
    
    private let barcodeLookupService = BarcodeFoodLookupService()

    private var displayedList: [GroceryListItem] {
        hideCompletedItems ? groceryList.filter { !$0.isCompleted } : groceryList
    }

    private var groupedList: [String: [GroceryListItem]] {
        Dictionary(grouping: displayedList, by: { $0.category })
    }
    
    private var shareText: String {
        let items = groceryList.filter { !$0.isCompleted }
        guard !items.isEmpty else { return "My grocery list is empty." }
        let grouped = Dictionary(grouping: items, by: { $0.category })
        var text = "Grocery list\n"
        for category in grouped.keys.sorted() {
            text += "\n\(category):\n"
            if let groupItems = grouped[category] {
                for item in groupItems.sorted(by: { $0.name < $1.name }) {
                    let formatter = NumberFormatter()
                    formatter.maximumFractionDigits = 2
                    let q = formatter.string(from: NSNumber(value: item.quantity)) ?? "\(item.quantity)"
                    let unit = item.unit == "item" ? "" : item.unit
                    text += "- \(item.name.capitalized) \(q) \(unit)\n"
                }
            }
        }
        return text
    }
    
    private var sortedCategories: [String] {
        let customOrder = GroceryListBuilder.standardCategories

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
                LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                    mainContent
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.section)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("grocery_list")
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("Grocery List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .tint(AppPalette.brand)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    trailingToolbarItems
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
                    let normalizedBarcode = BarcodeCorrectionRules.normalizedBarcode(barcode)
                    showingBarcodeScanner = false
                    isFetchingItemName = true
                    pendingMissedBarcode = normalizedBarcode.isEmpty ? nil : normalizedBarcode
                    DIContainer.shared.analyticsManager.log(.barcodeScanned, [:])
                    Task { @MainActor in
                        if let result = await barcodeLookupService.lookup(barcode) {
                            isFetchingItemName = false
                            pendingMissedBarcode = nil
                            showBarcodeResultFeedback(result)
                            addBarcodeItem(result.item)
                            saveList()
                            return
                        }
                        isFetchingItemName = false
                        fetchError = (true, "No food or supplement label matched this barcode. Add it manually and MyFitPlate will remember it next time.")
                    }
                }
            }
            .alert("Barcode error", isPresented: $fetchError.isShowing) {
                Button("Add manually") {
                    DIContainer.shared.analyticsManager.barcodeMissRecovery(
                        .selected(action: "grocery_add_manually", barcode: pendingMissedBarcode)
                    )
                    pendingMissedBarcode = nil
                    showingManualItemSheet = true
                }
                Button("OK", role: .cancel) {
                    DIContainer.shared.analyticsManager.barcodeMissRecovery(
                        .selected(action: "grocery_dismissed", barcode: pendingMissedBarcode)
                    )
                    pendingMissedBarcode = nil
                }
            } message: {
                Text(fetchError.message)
            }
            .confirmationDialog(
                "Clear grocery list?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear list", role: .destructive, action: clearList)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes every item currently on your grocery list.")
            }
            .refreshable {
                await loadList()
            }
            .task {
                await loadList()
            }
            .onChange(of: unitSystem) { _, newSystem in
                convertList(to: newSystem)
            }

            if isFetchingItemName {
                Color.black.opacity(0.36)
                    .ignoresSafeArea()

                VStack(spacing: AppSpacing.row) {
                    ProgressView()
                        .tint(AppPalette.brand)

                    VStack(spacing: 3) {
                        Text("Finding Item")
                            .appTextRole(.control)
                            .foregroundStyle(AppPalette.text)

                        Text("Looking up that barcode")
                            .appTextRole(.secondary)
                            .foregroundStyle(.secondary)
                    }
                }
                .appSurface(.emphasized)
                .accessibilityIdentifier("grocery_barcode_loading")
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

    private func showBarcodeResultFeedback(_ result: BarcodeFoodLookupResult) {
        if result.source == "custom_barcode" {
            ToastManager.shared.showToast(message: "Matched from My Foods.")
        } else if result.usedRelatedBarcode {
            ToastManager.shared.showToast(message: "Found a related barcode match.")
        }
    }

    private func addManualItem(_ item: GroceryListItem) {
        pendingMissedBarcode = nil
        var normalizedItem = item
        normalizedItem.category = GroceryListBuilder.normalizedCategory(item.category)
        if let existingIndex = groceryList.firstIndex(where: {
            $0.name.caseInsensitiveCompare(normalizedItem.name) == .orderedSame &&
            $0.unit.caseInsensitiveCompare(normalizedItem.unit) == .orderedSame
        }) {
            groceryList[existingIndex].quantity += normalizedItem.quantity
            groceryList[existingIndex].isCompleted = false
        } else {
            groceryList.append(normalizedItem)
        }
        saveList()
        HapticManager.instance.feedback(.medium)
    }

    private func updateManualItem(_ item: GroceryListItem) {
        if let existingIndex = groceryList.firstIndex(where: { $0.id == item.id }) {
            var normalizedItem = item
            normalizedItem.category = GroceryListBuilder.normalizedCategory(item.category)
            groceryList[existingIndex] = normalizedItem
            saveList()
            HapticManager.instance.feedback(.medium)
        }
    }
    
    private func loadList() async {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            self.isLoading = false
            return
        }
        let fetchedList = await mealPlannerService.fetchSynchronizedGroceryList(for: userID)
        let preparedList = fetchedList.map { item -> GroceryListItem in
            var prepared = GroceryListBuilder.applyUnitSystem(item, system: unitSystem)
            prepared.category = GroceryListBuilder.normalizedCategory(prepared.category)
            return prepared
        }
        self.groceryList = preparedList
        self.isLoading = false
        if preparedList != fetchedList {
            saveList()
        }
    }
    
    private func saveList() {
        guard let userID = DIContainer.shared.authService.currentUserID else { return }
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

    @ViewBuilder
    private var trailingToolbarItems: some View {
        if !groceryList.isEmpty {
            Menu {
                ShareLink(item: shareText) {
                    Label("Share List", systemImage: "square.and.arrow.up")
                }

                Picker(selection: $unitSystem, label: Text("Units")) {
                    Text("Imperial (lb, oz)").tag(GroceryUnitSystem.imperial)
                    Text("Metric (kg, g)").tag(GroceryUnitSystem.metric)
                }

                if groceryList.contains(where: \.isCompleted) {
                    Button(role: .destructive, action: clearCompleted) {
                        Label("Clear Checked", systemImage: "checkmark.circle.badge.xmark")
                    }
                }

                Button(role: .destructive, action: { showingClearConfirmation = true }) {
                    Label("Clear All", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Grocery list options")
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if isLoading {
            GroceryListLoadingState()
        } else if !groceryList.isEmpty {
            GrocerySummaryCard(
                items: groceryList,
                onScan: { showingBarcodeScanner = true },
                onAddManual: { showingManualItemSheet = true }
            )

            Label(
                groceryList.contains(where: { $0.source == "mealPlan" })
                    ? "Synced to the next seven days of your meal plan"
                    : "This list contains only items you added",
                systemImage: groceryList.contains(where: { $0.source == "mealPlan" })
                    ? "arrow.triangle.2.circlepath"
                    : "person.fill"
            )
            .appTextRole(.secondary)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("grocery_plan_sync_status")

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

    private func convertList(to system: GroceryUnitSystem) {
        guard !groceryList.isEmpty else { return }
        let converted = groceryList.map {
            GroceryListBuilder.applyUnitSystem($0, system: system)
        }
        guard converted != groceryList else { return }
        groceryList = converted
        saveList()
        HapticManager.instance.feedback(.light)
    }
}
