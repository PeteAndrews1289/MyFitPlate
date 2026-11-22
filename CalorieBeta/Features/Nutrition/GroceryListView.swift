import MyFitPlateCore
import SwiftUI

struct GroceryListView: View {
    var planStartDate: Date = Date()
    var embedded = false
    var onOpenPantry: (() -> Void)?
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @Environment(\.dismiss) var dismiss
    
    @State private var groceryList: [GroceryListItem] = []
    @State private var stock: [PantryItem] = []
    @State private var stockError: String?
    @State private var stockLoaded = false
    @State private var transferItem: GroceryListItem?
    @State private var showingSharePreview = false
    @State private var showingChangeHistory = false
    @State private var showingPendingReview = false
    @State private var pendingProduct: GroceryProductSnapshot?
    @State private var barcodeRequestID: UUID?
    @State private var barcodeScannerDismissed = true
    @State private var hasManualDraft = false
    @State private var isLoading = true
    @State private var didFailToLoad = false
    @State private var isRefreshing = false
    @State private var showingBarcodeScanner = false
    @State private var showingManualItemSheet = false
    @State private var isFetchingItemName = false
    @State private var showingClearConfirmation = false
    @State private var hideCompletedItems = false
    @State private var pendingMissedBarcode: String?
    @State private var fetchError: (isShowing: Bool, message: String) = (false, "")
    @State private var editingItem: GroceryListItem?
    @State private var recentlyDeletedItem: GroceryListItem?
    @State private var recentlyDeletedIndex = 0
    @State private var undoExpiryTask: Task<Void, Never>?
    @State private var loadRequestID = UUID()
    @State private var localEditRevision = 0
    @State private var confirmingReloadAccountList = false
    @StateObject private var checklist: GroceryChecklistSession
    
    @AppStorage("groceryUnitSystem") private var unitSystem: GroceryUnitSystem = Locale.current.measurementSystem == .us ? .imperial : .metric
    
    private let barcodeLookupService = BarcodeFoodLookupService()

    init(planStartDate: Date = Date(), embedded: Bool = false, onOpenPantry: (() -> Void)? = nil) {
        self.planStartDate = planStartDate
        self.embedded = embedded
        self.onOpenPantry = onOpenPantry
        let session = GroceryChecklistSession(userID: DIContainer.shared.authService.currentUserID)
        _checklist = StateObject(wrappedValue: session)
        let key = session.userID.flatMap { AccountScopedStorageKey.make(prefix: "groceryUnitSystem", userID: $0) } ?? "groceryUnitSystem"
        let selection = GroceryListBuilder.currentUnitSystem(userID: session.userID)
        _unitSystem = AppStorage(wrappedValue: selection, key)
        _groceryList = State(initialValue: session.items.map { GroceryListBuilder.applyUnitSystem($0, system: selection) })
        _hideCompletedItems = State(initialValue: session.checkpoint.hideCompleted ?? false)
    }

    private var displayedList: [GroceryListItem] {
        hideCompletedItems ? groceryList.filter { !$0.isCompleted || checklist.pendingItemIDs.contains($0.id) } : groceryList
    }

    private var groupedList: [String: [GroceryListItem]] {
        Dictionary(grouping: displayedList, by: { $0.category })
    }
    
    private var sortedCategories: [String] {
        let customOrder = GroceryListBuilder.standardCategories

        return groupedList.keys.sorted { first, second in
            let firstNeedsAttention = groupedList[first]?.contains { !$0.isCompleted || checklist.pendingItemIDs.contains($0.id) } == true
            let secondNeedsAttention = groupedList[second]?.contains { !$0.isCompleted || checklist.pendingItemIDs.contains($0.id) } == true
            if firstNeedsAttention != secondNeedsAttention { return firstNeedsAttention }
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
                // The grouped list has a bounded number of sections. Eager placement
                // avoids a lazy-section layout loop when its footer enters the viewport.
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    if embedded { workspaceHeading }
                    mainContent
                        .disabled(isRefreshing || checklist.isCancelling)
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.group)
                .padding(.bottom, AppSpacing.section)
                .frame(maxWidth: .infinity)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("grocery_list")
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle(embedded ? "" : "Grocery List")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if checklist.pendingCount > 0 || checklist.errorMessage != nil {
                    grocerySaveStatus
                        .padding(.horizontal, AppSpacing.screenHorizontal)
                        .padding(.vertical, AppSpacing.compact)
                        .background(AppPalette.canvas)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !embedded {
                        Button("Done") { dismiss() }
                            .tint(AppPalette.brand)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !embedded {
                        trailingToolbarItems
                            .disabled(isRefreshing)
                    }
                }
            }
            .sheet(isPresented: $showingManualItemSheet, onDismiss: {
                pendingMissedBarcode = nil
                pendingProduct = nil
                hasManualDraft = (try? GroceryManualDraftStore(userID: checklist.userID).load()) != nil
            }) {
                ManualGroceryItemSheet(initialBarcode: pendingMissedBarcode, initialProduct: pendingProduct,
                    initialShoppingStartDate: planStartDate, onReviewedSave: acceptManualReview) { _ in }
            }
            .sheet(isPresented: $showingSharePreview) {
                GroceryExportPreviewView(items: groceryList, stock: stock, starting: planStartDate,
                    pendingChanges: checklist.pendingCount > 0, stockCoverageAvailable: stockLoaded && stockError == nil)
            }
            .sheet(isPresented: $showingChangeHistory) {
                GroceryChangeHistoryView(checklist: checklist, starting: planStartDate) { groceryList = projected(checklist.items) }
            }
            .sheet(isPresented: $showingPendingReview) {
                GroceryPendingReviewView(checklist: checklist) { groceryList = projected(checklist.items) }
            }
            .sheet(item: $transferItem, onDismiss: { Task { await loadList(); await loadStock() } }) { item in
                GroceryStockTransferView(item: item) { Task { await loadList(); await loadStock() } }
            }
            .task { await loadStock() }
            .sheet(item: $editingItem, onDismiss: {
                hasManualDraft = (try? GroceryManualDraftStore(userID: checklist.userID).load()) != nil
            }) { itemToEdit in
                ManualGroceryItemSheet(initialItem: itemToEdit, initialShoppingStartDate: planStartDate,
                    onReviewedSave: acceptManualReview) { _ in }
            }
            .sheet(isPresented: $showingBarcodeScanner, onDismiss: {
                barcodeScannerDismissed = true
                presentProductReviewIfReady()
            }) {
                BarcodeScannerView(onClose: { showingBarcodeScanner = false }) { barcode in
                    let normalizedBarcode = BarcodeCorrectionRules.normalizedBarcode(barcode)
                    guard barcodeRequestID == nil, checklist.userID == DIContainer.shared.authService.currentUserID else { return }
                    let requestID = UUID(); barcodeRequestID = requestID; barcodeScannerDismissed = false
                    showingBarcodeScanner = false
                    isFetchingItemName = true
                    pendingMissedBarcode = normalizedBarcode.isEmpty ? nil : normalizedBarcode
                    DIContainer.shared.analyticsManager.log(.barcodeScanned, [:])
                    Task { @MainActor in
                        if let result = await barcodeLookupService.lookup(barcode) {
                            guard barcodeRequestID == requestID, checklist.userID == DIContainer.shared.authService.currentUserID else { return }
                            barcodeRequestID = nil
                            isFetchingItemName = false
                            showBarcodeResultFeedback(result)
                            pendingProduct = GroceryProductSnapshot(food: result.item, barcode: normalizedBarcode)
                            presentProductReviewIfReady()
                            return
                        }
                        guard barcodeRequestID == requestID, checklist.userID == DIContainer.shared.authService.currentUserID else { return }
                        barcodeRequestID = nil
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
                "Clear this shopping view?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove manual rows and skip planned needs", role: .destructive, action: clearList)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(groceryList.filter { $0.source != "mealPlan" }.count) manual rows are removed; planned needs are kept as explicit skips for this period. Purchases remain in history. Review Undo in Shopping changes to restore them.")
            }
            .confirmationDialog("Resolve ALL pending grocery changes?", isPresented: $confirmingReloadAccountList, titleVisibility: .visible) {
                Button("Cancel all unaccepted changes", role: .destructive) {
                    Task {
                        if await checklist.cancelAllPending(using: DIContainer.shared.nutritionRepository) {
                            groceryList = projected(checklist.items)
                        }
                    }
                }
            } message: { Text("This resolves every pending shopping command on this device for this account, across shopping periods. Accepted writes stay accepted. Each unaccepted command is permanently fenced; its desired values remain under Shopping changes for an explicit new review. Later dependent reviews are kept too.") }
            .refreshable {
                await loadList(reloadPlanDays: true)
            }
            .task {
                hasManualDraft = (try? GroceryManualDraftStore(userID: checklist.userID).load()) != nil
                await loadList()
            }
            .onReceive(NotificationCenter.default.publisher(for: .mealPlanChanged)) { note in
                guard note.object as? String == DIContainer.shared.authService.currentUserID else { return }
                Task { await loadList() }
            }
            .safeAreaInset(edge: .bottom) {
                if let recentlyDeletedItem {
                    GroceryUndoBanner(itemName: recentlyDeletedItem.name, onUndo: undoDeletion)
                        .padding(.horizontal, AppSpacing.screenHorizontal)
                        .padding(.bottom, AppSpacing.compact)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(AppMotion.visibility, value: recentlyDeletedItem?.id)
            .onChange(of: unitSystem) { _, newSystem in
                convertList(to: newSystem)
            }
            .onChange(of: hideCompletedItems) { _, value in
                if !checklist.setHideCompleted(value) { hideCompletedItems = checklist.checkpoint.hideCompleted ?? false }
            }
            .onDisappear {
                undoExpiryTask?.cancel()
                undoExpiryTask = nil
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

    private var workspaceHeading: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            HStack(alignment: .firstTextBaseline) {
                Text("Week of \(planStartDate.formatted(date: .abbreviated, time: .omitted))")
                    .appTextRole(.sectionTitle)
                    .accessibilityIdentifier("grocery_week_heading")
                Spacer()
                if let onOpenPantry {
                    Button(action: onOpenPantry) {
                        Label("Pantry", systemImage: "refrigerator").frame(minHeight: 44)
                    }
                    .appTextRole(.secondary)
                    .accessibilityLabel("Review pantry")
                    .accessibilityIdentifier("planner_shop_pantry")
                }
                trailingToolbarItems.disabled(isRefreshing)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planner_shop_heading")
    }
    
    private func loadStock() async {
        guard let owner = DIContainer.shared.authService.currentUserID else { stock = []; return }
        do {
            let loaded = try await DIContainer.shared.nutritionRepository.fetchInventory(userID: owner)
            guard DIContainer.shared.authService.currentUserID == owner else { return }
            stock = loaded; stockLoaded = true; stockError = nil
        } catch { stockLoaded = false; stockError = "Pantry coverage unavailable. The full shopping requirements stay visible." }
    }

    private func toggleSkip(_ item: GroceryListItem) {
        guard let index = groceryList.firstIndex(where: { $0.id == item.id }) else { return }
        groceryList[index].skippedForPlan = item.skippedForPlan != true
        saveList(title: item.skippedForPlan == true ? "Include planned need again" : "Skip buying planned need")
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
        if item.source == "mealPlan" {
            if item.skippedForPlan != true { toggleSkip(item) }
            return
        }
        guard let index = groceryList.firstIndex(where: { $0.id == item.id }) else { return }
        undoExpiryTask?.cancel()
        recentlyDeletedIndex = index
        recentlyDeletedItem = groceryList.remove(at: index)
        saveList(title: "Remove manual shopping item")
        HapticManager.instance.feedback(.light)

        undoExpiryTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(6))
                recentlyDeletedItem = nil
                undoExpiryTask = nil
            } catch {
                return
            }
        }
    }

    private func presentProductReviewIfReady() {
        guard barcodeScannerDismissed, pendingProduct != nil, checklist.userID == DIContainer.shared.authService.currentUserID else { return }
        showingManualItemSheet = true
    }
    private func acceptManualReview(_ item: GroceryListItem, original: GroceryListItem?, operationID: UUID) -> Bool {
        guard !isRefreshing, checklist.userID == DIContainer.shared.authService.currentUserID else { return false }
        let before = original.map { GroceryPresentationRules.canonicalized([$0], against: checklist.items) } ?? []
        let updated = GroceryPresentationRules.canonicalized([item], against: before)
        let operation = GroceryListMutation(id: operationID, before: before, upserts: updated, removedIDs: [],
            title: original == nil ? "Add manual or product need" : "Edit shopping amount or override",
            shoppingStartDate: item.sourcePlanStart ?? Calendar.current.startOfDay(for: planStartDate))
        guard checklist.stage(operation) else { return false }
        localEditRevision += 1; groceryList = projected(checklist.items); hasManualDraft = false
        Task {
            await checklist.retry(using: DIContainer.shared.nutritionRepository)
            guard checklist.userID == DIContainer.shared.authService.currentUserID else { return }
            groceryList = projected(checklist.items)
        }
        return true
    }

    private func showBarcodeResultFeedback(_ result: BarcodeFoodLookupResult) {
        if result.source == "custom_barcode" {
            ToastManager.shared.showToast(message: "Matched from My Foods.")
        } else if result.usedRelatedBarcode {
            ToastManager.shared.showToast(message: "Found a related barcode match.")
        }
    }

    private func addManualItem(_ item: GroceryListItem) {
        var normalizedItem = item
        normalizedItem.category = GroceryListBuilder.normalizedCategory(item.category)
        guard !groceryList.contains(where: { $0.id == normalizedItem.id }) else { return }
        normalizedItem.sourcePlanStart = normalizedItem.sourcePlanStart ?? Calendar.current.startOfDay(for: planStartDate)
        groceryList.append(normalizedItem)
        saveList(title: "Add manual or product need")
        HapticManager.instance.feedback(.medium)
    }

    private func undoDeletion() {
        guard let item = recentlyDeletedItem else { return }
        guard !groceryList.contains(where: { $0.id == item.id }) else { recentlyDeletedItem = nil; return }
        undoExpiryTask?.cancel()
        let index = min(max(recentlyDeletedIndex, 0), groceryList.count)
        groceryList.insert(item, at: index)
        recentlyDeletedItem = nil
        undoExpiryTask = nil
        saveList(title: "Restore removed shopping item")
        HapticManager.instance.feedback(.medium)
    }

    private func updateManualItem(_ item: GroceryListItem) {
        if let existingIndex = groceryList.firstIndex(where: { $0.id == item.id }) {
            var normalizedItem = item
            normalizedItem.category = GroceryListBuilder.normalizedCategory(item.category)
            groceryList[existingIndex] = normalizedItem
            saveList(title: "Edit shopping amount or override")
            HapticManager.instance.feedback(.medium)
        }
    }
    
    private func loadList(reloadPlanDays: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let requestID = UUID()
        loadRequestID = requestID
        let revision = localEditRevision
        guard let userID = DIContainer.shared.authService.currentUserID else {
            groceryList = []
            didFailToLoad = false
            self.isLoading = false
            return
        }
        guard checklist.userID == userID else { groceryList = []; isLoading = false; return }
        func requestIsCurrent() -> Bool {
            loadRequestID == requestID && localEditRevision == revision && DIContainer.shared.authService.currentUserID == userID
        }
        if checklist.pendingCount > 0 {
            await checklist.retry(using: DIContainer.shared.nutritionRepository)
            guard requestIsCurrent() else { return }
            groceryList = projected(checklist.items)
            if checklist.pendingCount > 0 { isLoading = false; return }
        }
        if groceryList.isEmpty { isLoading = true }
        let result = await mealPlannerService.refreshGroceryListResult(for: userID, starting: planStartDate, reloadPlanDays: reloadPlanDays)
        guard requestIsCurrent() else { return }
        let fetchedList: [GroceryListItem]
        switch result {
        case .success(let refreshed):
            fetchedList = refreshed
            didFailToLoad = false
        case .failure:
            let saved = await mealPlannerService.fetchGroceryListResult(for: userID)
            guard requestIsCurrent() else { return }
            didFailToLoad = true
            guard case .success(let items) = saved else { isLoading = false; return }
            fetchedList = items
        }
        let preparedList = fetchedList.map { item -> GroceryListItem in
            var prepared = GroceryListBuilder.applyUnitSystem(item, system: unitSystem)
            prepared.category = GroceryListBuilder.normalizedCategory(prepared.category)
            return prepared
        }
        if checklist.installRemote(fetchedList) { self.groceryList = preparedList }
        self.isLoading = false
    }
    
    private func saveList(title: String = "Update shopping checklist") {
        guard !isRefreshing else { groceryList = projected(checklist.items); return }
        localEditRevision += 1
        let canonical = GroceryPresentationRules.canonicalized(groceryList, against: checklist.items)
        guard checklist.stage(canonical, title: title, shoppingStartDate: Calendar.current.startOfDay(for: planStartDate)) else { groceryList = projected(checklist.items); return }
        Task {
            await checklist.retry(using: DIContainer.shared.nutritionRepository)
            guard checklist.userID == DIContainer.shared.authService.currentUserID else { return }
            groceryList = projected(checklist.items)
        }
    }

    private func clearCompleted() {
        hideCompletedItems = true
        HapticManager.instance.feedback(.medium)
    }

    private func clearList() {
        recentlyDeletedItem = nil
        groceryList = groceryList.filter { $0.source == "mealPlan" }.map { item in
            var skipped = item; skipped.skippedForPlan = true; return skipped
        }
        saveList(title: "Clear manual rows and skip planned needs")
        HapticManager.instance.feedback(.medium)
    }

    @ViewBuilder
    private var trailingToolbarItems: some View {
        Group {
            Menu {
                Button(hasManualDraft ? "Resume unfinished item" : "Add a manual item", systemImage: "square.and.pencil") { showingManualItemSheet = true }
                    .accessibilityIdentifier("grocery_resume_item")
                Button("Shopping changes / restore", systemImage: "clock.arrow.circlepath") { showingChangeHistory = true }
                    .accessibilityIdentifier("grocery_history_action")
                Button { showingSharePreview = true } label: {
                    Label("Preview / share list", systemImage: "square.and.arrow.up")
                }.accessibilityIdentifier("grocery_share_action")

                Picker(selection: $unitSystem, label: Text("Units")) {
                    Text("Imperial (lb, oz)").tag(GroceryUnitSystem.imperial)
                    Text("Metric (kg, g)").tag(GroceryUnitSystem.metric)
                }

                if groceryList.contains(where: \.isCompleted) {
                    Button(action: clearCompleted) {
                        Label("Hide checked from this view", systemImage: "eye.slash")
                    }
                }

                Button(role: .destructive, action: { showingClearConfirmation = true }) {
                    Label("Clear All", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Grocery list options")
        }
    }

    private var grocerySaveStatus: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            Text(checklist.errorMessage ?? "\(checklist.pendingCount) grocery changes saved on this device · waiting for account acknowledgement")
                .appTextRole(.secondary).foregroundStyle(AppPalette.caution)
            Button("Review saved shopping changes") { showingPendingReview = true }
                .frame(minHeight: 44).accessibilityIdentifier("grocery_pending_review")
        }
        .appSurface(.quiet)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("grocery_save_status")
    }

    @ViewBuilder
    private var mainContent: some View {
        if isLoading {
            GroceryListLoadingState()
        } else if didFailToLoad && groceryList.isEmpty {
            GroceryListLoadErrorState {
                Task { await loadList(reloadPlanDays: true) }
            }
        } else if !groceryList.isEmpty {
            if didFailToLoad {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    Label("Showing your saved list. Planned quantities couldn't refresh.", systemImage: "exclamationmark.icloud")
                        .appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                        .accessibilityIdentifier("grocery_refresh_warning")
                    Button("Retry plan update") { Task { await loadList(reloadPlanDays: true) } }
                        .frame(minHeight: 44)
                }.appSurface(.quiet)
            }
            GrocerySummaryCard(
                items: groceryList,
                onScan: { showingBarcodeScanner = true },
                onAddManual: { showingManualItemSheet = true }
            )

            if let stockError {
                Text(stockError).appTextRole(.secondary).foregroundStyle(AppPalette.caution)
            } else if !stockLoaded {
                Text("Checking pantry… showing full requirements for now.")
                    .appTextRole(.secondary).foregroundStyle(.secondary)
            }
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
                        onToggle: { saveList() },
                        onEdit: { item in editingItem = item },
                        onDelete: deleteItem,
                        coverage: stockLoaded && stockError == nil ? Dictionary(uniqueKeysWithValues: InventoryPlanningRules.coverage(items: groceryList, stock: stock).map { ($0.id, $0) }) : [:],
                        onTransfer: { item in transferItem = checklist.items.first { $0.id == item.id } ?? item },
                        onSkip: toggleSkip
                    )
                }
            }
            shoppingDetails
        } else {
            GroceryListEmptyState(
                onScan: { showingBarcodeScanner = true },
                onAddManual: { showingManualItemSheet = true }
            )
        }
    }

    private var shoppingDetails: some View {
        DisclosureGroup("How this list is calculated") {
            VStack(alignment: .leading, spacing: AppSpacing.row) {
                Label(
                    groceryList.contains(where: { $0.source == "mealPlan" })
                        ? "Plan ingredients for seven days from \(planStartDate.formatted(date: .abbreviated, time: .omitted))"
                        : "This list contains only items you added",
                    systemImage: "list.bullet.clipboard"
                )
                .accessibilityIdentifier("grocery_plan_sync_status")
                Text("Have / buy uses confirmed, compatible, unexpired ingredient stock once across this list. Counts and unknown units are never assumed to be grams. Your pantry is not deducted by planning or checking.")
            }
            .appTextRole(.secondary).foregroundStyle(.secondary)
            .padding(.top, AppSpacing.row)
        }
        .appTextRole(.secondary)
        .accessibilityIdentifier("grocery_calculation_details")
    }

    private func projected(_ items: [GroceryListItem]) -> [GroceryListItem] {
        items.map { GroceryListBuilder.applyUnitSystem($0, system: unitSystem) }
    }

    private func convertList(to system: GroceryUnitSystem) {
        groceryList = checklist.items.map { GroceryListBuilder.applyUnitSystem($0, system: system) }
        HapticManager.instance.feedback(.light)
    }
}
