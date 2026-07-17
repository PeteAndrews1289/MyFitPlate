import MyFitPlateCore
import SwiftUI

@MainActor
final class MyFoodsLibraryViewModel: ObservableObject {
    @Published var query = ""
    @Published var filter: MyFoodsLibraryFilter = .all
    @Published var sort: MyFoodsLibrarySort = .name
    @Published private(set) var savedFoods: [FoodItem]
    @Published private(set) var recentFoods: [FoodItem]
    @Published private(set) var isLoading: Bool
    @Published private(set) var loadError: String?
    @Published private(set) var activeMutationID: String?
    @Published var editingFood: FoodItem?
    @Published var confirmation: MyFoodsLibraryConfirmation?

    private var loadGeneration = UUID()
    private var loadedUserID: String?

    init(
        initialFoods: [FoodItem] = [],
        recentFoods: [FoodItem] = [],
        startsLoading: Bool = true
    ) {
        self.savedFoods = initialFoods
        self.recentFoods = recentFoods
        self.isLoading = startsLoading && initialFoods.isEmpty
    }

    var entries: [MyFoodsLibraryEntry] {
        MyFoodsLibraryRules.entries(savedFoods: savedFoods, recentFoods: recentFoods)
    }

    var visibleEntries: [MyFoodsLibraryEntry] {
        MyFoodsLibraryRules.visibleEntries(
            entries,
            query: query,
            filter: filter,
            sort: sort
        )
    }

    var duplicateGroups: [MyFoodsDuplicateGroup] {
        MyFoodsLibraryRules.duplicateGroups(from: entries)
    }

    func count(for filter: MyFoodsLibraryFilter) -> Int {
        MyFoodsLibraryRules.visibleEntries(
            entries,
            query: "",
            filter: filter,
            sort: .name
        ).count
    }

    func load(using service: DailyLogService) {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            loadGeneration = UUID()
            loadedUserID = nil
            savedFoods = []
            recentFoods = []
            isLoading = false
            loadError = "Sign in to manage My Foods."
            return
        }

        let generation = UUID()
        loadGeneration = generation
        if loadedUserID != userID {
            savedFoods = []
            recentFoods = []
        }
        loadedUserID = userID
        if savedFoods.isEmpty {
            isLoading = true
        }
        loadError = nil

        service.fetchRecentFoodItems(for: userID) { [weak self] result in
            Task { @MainActor in
                guard let self,
                      self.loadGeneration == generation,
                      self.loadedUserID == userID,
                      DIContainer.shared.authService.currentUserID == userID else { return }
                if case .success(let items) = result {
                    self.recentFoods = items
                }
            }
        }

        service.customFoodStore.fetchMyFoodItems(for: userID) { [weak self] result in
            Task { @MainActor in
                guard let self,
                      self.loadGeneration == generation,
                      self.loadedUserID == userID,
                      DIContainer.shared.authService.currentUserID == userID else { return }
                self.isLoading = false
                switch result {
                case .success(let items):
                    self.savedFoods = items
                    self.loadError = nil
                case .failure:
                    self.loadError = "My Foods could not refresh. Your saved foods were not changed."
                }
            }
        }
    }

    func saveEditedFood(
        _ food: FoodItem,
        using store: CustomFoodStore,
        completion: @escaping (Bool) -> Void
    ) {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            completion(false)
            return
        }
        activeMutationID = food.id
        store.saveCustomFood(for: userID, foodItem: food) { [weak self] success in
            guard let self else { return }
            guard DIContainer.shared.authService.currentUserID == userID else {
                completion(false)
                return
            }
            self.activeMutationID = nil
            if success, let index = self.savedFoods.firstIndex(where: { $0.id == food.id }) {
                self.savedFoods[index] = food
            }
            completion(success)
        }
    }

    func deleteFood(
        _ food: FoodItem,
        using store: CustomFoodStore,
        completion: @escaping (Bool) -> Void
    ) {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            completion(false)
            return
        }
        activeMutationID = food.id
        store.deleteCustomFood(for: userID, foodItemID: food.id) { [weak self] success in
            guard let self else { return }
            guard DIContainer.shared.authService.currentUserID == userID else {
                completion(false)
                return
            }
            self.activeMutationID = nil
            if success {
                self.savedFoods.removeAll { $0.id == food.id }
            }
            completion(success)
        }
    }

    func removeBarcodeAssociation(
        from food: FoodItem,
        using store: CustomFoodStore,
        completion: @escaping (Bool) -> Void
    ) {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            completion(false)
            return
        }
        activeMutationID = food.id
        store.removeBarcodeAssociation(for: userID, foodItemID: food.id) { [weak self] success in
            guard let self else { return }
            guard DIContainer.shared.authService.currentUserID == userID else {
                completion(false)
                return
            }
            self.activeMutationID = nil
            if success, let index = self.savedFoods.firstIndex(where: { $0.id == food.id }) {
                self.savedFoods[index] = MyFoodsLibraryRules.removingBarcodeAssociation(from: food)
            }
            completion(success)
        }
    }

    func mergeDuplicates(
        _ group: MyFoodsDuplicateGroup,
        using store: CustomFoodStore,
        completion: @escaping (Bool) -> Void
    ) {
        guard let userID = DIContainer.shared.authService.currentUserID else {
            completion(false)
            return
        }
        let removingIDs = group.duplicates.map(\.id)
        guard !removingIDs.isEmpty else {
            completion(true)
            return
        }

        activeMutationID = "merge:\(group.id)"
        store.mergeCustomFoods(
            for: userID,
            keepingFoodID: group.keeper.id,
            removingFoodIDs: removingIDs
        ) { [weak self] success in
            guard let self else { return }
            guard DIContainer.shared.authService.currentUserID == userID else {
                completion(false)
                return
            }
            self.activeMutationID = nil
            if success {
                let removed = Set(removingIDs)
                self.savedFoods.removeAll { removed.contains($0.id) }
            }
            completion(success)
        }
    }
}

enum MyFoodsLibraryConfirmation: Identifiable {
    case delete(FoodItem)
    case removeBarcode(FoodItem)
    case merge(MyFoodsDuplicateGroup)

    var id: String {
        switch self {
        case .delete(let food): return "delete:\(food.id)"
        case .removeBarcode(let food): return "barcode:\(food.id)"
        case .merge(let group): return "merge:\(group.id)"
        }
    }
}

struct MyFoodsLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var dailyLogService: DailyLogService
    @EnvironmentObject private var bannerService: BannerService
    @StateObject private var viewModel: MyFoodsLibraryViewModel
    @State private var editingLog: DailyLog?

    private let loadsRemoteData: Bool
    private let onLibraryChanged: () -> Void

    init(
        initialFoods: [FoodItem] = [],
        recentFoods: [FoodItem] = [],
        loadsRemoteData: Bool = true,
        onLibraryChanged: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(
            wrappedValue: MyFoodsLibraryViewModel(
                initialFoods: initialFoods,
                recentFoods: recentFoods,
                startsLoading: loadsRemoteData
            )
        )
        self.loadsRemoteData = loadsRemoteData
        self.onLibraryChanged = onLibraryChanged
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading My Foods")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    libraryContent
                }
            }
            .background(AppPalette.canvas.ignoresSafeArea())
            .navigationTitle("My Foods")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.query, prompt: "Search saved foods")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable {
                guard loadsRemoteData else { return }
                viewModel.load(using: dailyLogService)
            }
        }
        .task {
            guard loadsRemoteData else { return }
            viewModel.load(using: dailyLogService)
            logLibraryOpened()
        }
        .sheet(item: $viewModel.editingFood) { food in
            NavigationStack {
                AddFoodView(
                    initialFoodItem: food,
                    dailyLog: $editingLog,
                    date: dailyLogService.activelyViewedDate,
                    source: "my_foods_edit",
                    onLogUpdated: {},
                    onUpdate: saveEditedFood,
                    showsSavedControl: false
                )
            }
        }
        .alert(item: $viewModel.confirmation, content: confirmationAlert)
    }

    private var libraryContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.section) {
                libraryControls

                if let loadError = viewModel.loadError {
                    inlineError(loadError)
                }

                if !viewModel.duplicateGroups.isEmpty {
                    duplicateSection
                }

                if viewModel.visibleEntries.isEmpty {
                    emptyState
                } else {
                    savedFoodsSection
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.group)
            .padding(.bottom, AppSpacing.section)
        }
        .accessibilityIdentifier("my_foods_library")
    }

    private var libraryControls: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppMetricStrip(items: [
                AppMetricItem(label: "Saved", value: viewModel.entries.count.formatted()),
                AppMetricItem(
                    label: "Barcode",
                    value: viewModel.count(for: .barcodeCorrections).formatted(),
                    accent: AppPalette.effort
                ),
                AppMetricItem(
                    label: "Review",
                    value: viewModel.count(for: .needsReview).formatted(),
                    accent: viewModel.count(for: .needsReview) > 0 ? AppPalette.caution : .accentPositive
                )
            ])
            .appSurface(.emphasized)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        selectionSummary
                        controlMenus
                    }
                } else {
                    HStack(spacing: AppSpacing.row) {
                        selectionSummary
                        Spacer(minLength: 0)
                        controlMenus
                    }
                }
            }
        }
    }

    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.filter.title)
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
            Text("\(visibleCountText) · \(viewModel.sort.title)")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var controlMenus: some View {
        HStack(spacing: AppSpacing.compact) {
            Menu {
                ForEach(MyFoodsLibraryFilter.allCases, id: \.self) { filter in
                    Button {
                        viewModel.filter = filter
                        logFilterSelected(filter)
                    } label: {
                        Label(
                            "\(filter.title) (\(viewModel.count(for: filter)))",
                            systemImage: viewModel.filter == filter ? "checkmark" : filter.systemImage
                        )
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .buttonStyle(AppIconButtonStyle(.neutral))
            .accessibilityLabel("Filter My Foods")
            .accessibilityValue(viewModel.filter.title)

            Menu {
                ForEach(MyFoodsLibrarySort.allCases, id: \.self) { sort in
                    Button {
                        viewModel.sort = sort
                    } label: {
                        Label(
                            sort.title,
                            systemImage: viewModel.sort == sort ? "checkmark" : sort.systemImage
                        )
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .buttonStyle(AppIconButtonStyle(.neutral))
            .accessibilityLabel("Sort My Foods")
            .accessibilityValue(viewModel.sort.title)
        }
    }

    private var savedFoodsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Saved foods",
                subtitle: viewModel.query.isEmpty ? nil : "Results for \(viewModel.query)"
            )

            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.visibleEntries.enumerated()), id: \.element.id) { index, entry in
                    MyFoodsLibraryRow(
                        entry: entry,
                        isWorking: viewModel.activeMutationID == entry.id,
                        editAction: { viewModel.editingFood = entry.item },
                        removeBarcodeAction: {
                            viewModel.confirmation = .removeBarcode(entry.item)
                        },
                        deleteAction: {
                            viewModel.confirmation = .delete(entry.item)
                        }
                    )

                    if index < viewModel.visibleEntries.count - 1 {
                        Divider()
                            .padding(.leading, 66)
                    }
                }
            }
            .appSurface(.quiet, padding: 0)
            .accessibilityIdentifier("my_foods_list")
        }
    }

    private var duplicateSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            AppSectionHeader(
                title: "Duplicate copies",
                subtitle: "\(viewModel.duplicateGroups.count) group\(viewModel.duplicateGroups.count == 1 ? "" : "s") found"
            )

            VStack(spacing: 0) {
                ForEach(Array(viewModel.duplicateGroups.enumerated()), id: \.element.id) { index, group in
                    Button {
                        viewModel.confirmation = .merge(group)
                    } label: {
                        AppListRow(
                            icon: "square.on.square",
                            iconColor: AppPalette.caution,
                            title: group.keeper.item.name,
                            subtitle: "\(group.itemCount) identical saved copies"
                        ) {
                            Text("Review")
                                .appTextRole(.caption)
                                .foregroundStyle(AppPalette.caution)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.activeMutationID == "merge:\(group.id)")

                    if index < viewModel.duplicateGroups.count - 1 {
                        Divider()
                    }
                }
            }
            .appSurface(.quiet, padding: 0)
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.row) {
            Image(systemName: viewModel.savedFoods.isEmpty ? "folder" : "line.3.horizontal.decrease.circle")
                .appTextRole(.sectionTitle)
                .foregroundStyle(.secondary)
            Text(viewModel.savedFoods.isEmpty ? "No saved foods yet" : "No foods match")
                .appTextRole(.control)
                .foregroundStyle(AppPalette.text)
            Text(viewModel.savedFoods.isEmpty
                 ? "Star a food or save a correction and it will appear here."
                 : "Try another search or filter.")
                .appTextRole(.secondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .appSurface(.quiet)
    }

    private func inlineError(_ message: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(AppPalette.caution)
                .accessibilityHidden(true)
            Text(message)
                .appTextRole(.secondary)
                .foregroundStyle(AppPalette.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if loadsRemoteData {
                Button("Retry") { viewModel.load(using: dailyLogService) }
                    .appTextRole(.caption)
            }
        }
        .appSurface(.quiet)
    }

    private func confirmationAlert(_ confirmation: MyFoodsLibraryConfirmation) -> Alert {
        switch confirmation {
        case .delete(let food):
            return Alert(
                title: Text("Delete \(food.name)?"),
                message: Text("This removes your saved copy and its personal barcode association. Foods already in your diary and public database matches will not change."),
                primaryButton: .destructive(Text("Delete")) { deleteFood(food) },
                secondaryButton: .cancel()
            )
        case .removeBarcode(let food):
            return Alert(
                title: Text("Stop using this barcode?"),
                message: Text("The food stays in My Foods, but future scans will no longer prefer this saved copy. Diary history and public database matches will not change."),
                primaryButton: .destructive(Text("Remove barcode")) { removeBarcode(from: food) },
                secondaryButton: .cancel()
            )
        case .merge(let group):
            return Alert(
                title: Text("Merge \(group.itemCount) identical copies?"),
                message: Text("MyFitPlate will keep the most recently used copy when known and remove only identical duplicates from My Foods. Diary history will not change."),
                primaryButton: .destructive(Text("Merge copies")) { merge(group) },
                secondaryButton: .cancel()
            )
        }
    }

    private func saveEditedFood(_ food: FoodItem) {
        viewModel.saveEditedFood(food, using: dailyLogService.customFoodStore) { success in
            showResult(
                success: success,
                title: success ? "Food updated" : "Update failed",
                message: success ? "Your saved food now uses the reviewed values." : "The saved food was not changed."
            )
            logMutation(action: "edit", success: success, itemCount: 1)
        }
    }

    private func deleteFood(_ food: FoodItem) {
        viewModel.deleteFood(food, using: dailyLogService.customFoodStore) { success in
            showResult(
                success: success,
                title: success ? "Food deleted" : "Delete failed",
                message: success ? "Diary history was left unchanged." : "The saved food was not changed."
            )
            logMutation(action: "delete", success: success, itemCount: 1)
        }
    }

    private func removeBarcode(from food: FoodItem) {
        viewModel.removeBarcodeAssociation(from: food, using: dailyLogService.customFoodStore) { success in
            showResult(
                success: success,
                title: success ? "Barcode removed" : "Update failed",
                message: success ? "Future scans will no longer prefer this saved copy." : "The barcode association was not changed."
            )
            logMutation(action: "remove_barcode", success: success, itemCount: 1)
        }
    }

    private func merge(_ group: MyFoodsDuplicateGroup) {
        viewModel.mergeDuplicates(group, using: dailyLogService.customFoodStore) { success in
            showResult(
                success: success,
                title: success ? "Copies merged" : "Merge failed",
                message: success ? "One saved copy remains. Diary history was left unchanged." : "No duplicate copies were changed."
            )
            logMutation(action: "merge", success: success, itemCount: group.itemCount)
        }
    }

    private func showResult(success: Bool, title: String, message: String) {
        if success {
            HapticManager.instance.notification(.success)
            onLibraryChanged()
            bannerService.showBanner(title: title, message: message)
        } else {
            HapticManager.instance.notification(.error)
            bannerService.showBanner(
                title: title,
                message: message,
                iconName: "xmark.circle.fill",
                iconColor: AppPalette.critical
            )
        }
    }

    private var visibleCountText: String {
        let visibleCount = viewModel.visibleEntries.count
        let totalCount = viewModel.entries.count
        return visibleCount == totalCount
            ? "\(totalCount) saved"
            : "\(visibleCount) of \(totalCount)"
    }

    private func logLibraryOpened() {
        DIContainer.shared.analyticsManager?.logEvent(ProductAnalytics.Event.myFoodsLibraryViewed.rawValue, parameters: [
            "saved_count": viewModel.entries.count,
            "personal_match_count": viewModel.count(for: .barcodeCorrections),
            "needs_review_count": viewModel.count(for: .needsReview),
            "duplicate_group_count": viewModel.duplicateGroups.count
        ])
    }

    private func logFilterSelected(_ filter: MyFoodsLibraryFilter) {
        DIContainer.shared.analyticsManager?.logEvent(ProductAnalytics.Event.myFoodsLibraryFilter.rawValue, parameters: [
            "filter": filter.rawValue
        ])
    }

    private func logMutation(action: String, success: Bool, itemCount: Int) {
        DIContainer.shared.analyticsManager?.logEvent(ProductAnalytics.Event.myFoodsLibraryAction.rawValue, parameters: [
            "action": action,
            "success": success,
            "item_count": itemCount
        ])
    }
}

private struct MyFoodsLibraryRow: View {
    let entry: MyFoodsLibraryEntry
    let isWorking: Bool
    let editAction: () -> Void
    let removeBarcodeAction: () -> Void
    let deleteAction: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.row) {
            foodGlyph

            Button(action: editAction) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.item.name)
                        .appTextRole(.control)
                        .foregroundStyle(AppPalette.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(entry.item.servingSize.isEmpty ? "Serving details unavailable" : entry.item.servingSize)
                        .appTextRole(.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    usageAndTrustMetadata

                    if let barcode = normalizedBarcode {
                        Label("Future scans: \(barcode)", systemImage: "barcode")
                            .appTextRole(.caption)
                            .foregroundStyle(AppPalette.effort)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the editor for this saved food.")

            if isWorking {
                ProgressView()
                    .frame(width: 36, height: 36)
            } else {
                Menu {
                    Button(action: editAction) {
                        Label("Edit", systemImage: "pencil")
                    }
                    if entry.hasBarcodeAssociation {
                        Button(role: .destructive, action: removeBarcodeAction) {
                            Label("Remove barcode", systemImage: "barcode.viewfinder")
                        }
                    }
                    Button(role: .destructive, action: deleteAction) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(AppIconButtonStyle(.plain))
                .accessibilityLabel("Actions for \(entry.item.name)")
            }
        }
        .padding(.horizontal, AppSpacing.group)
        .padding(.vertical, AppSpacing.row)
        .accessibilityIdentifier("my_foods_row_\(entry.id)")
    }

    @ViewBuilder
    private var foodGlyph: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Image(systemName: "fork.knife")
                .appTextRole(.control)
                .foregroundStyle(.secondary)
                .frame(width: 42, height: 42)
                .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .accessibilityHidden(true)
        } else {
            Text(FoodEmojiMapper.getEmoji(for: entry.item.name))
                .font(.system(size: 23))
                .frame(width: 42, height: 42)
                .background(AppPalette.canvas, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private var normalizedBarcode: String? {
        let barcode = BarcodeCorrectionRules.normalizedBarcode(entry.item.sourceMetadata?.barcode ?? "")
        return barcode.isEmpty ? nil : barcode
    }

    @ViewBuilder
    private var usageAndTrustMetadata: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 3) {
                trustLabel
                lastUsedLabel
            }
        } else {
            HStack(spacing: 8) {
                trustLabel
                lastUsedLabel
            }
        }
    }

    private var trustLabel: some View {
        Label(entry.trust.label, systemImage: trustIcon)
            .appTextRole(.caption)
            .foregroundStyle(trustTint)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var lastUsedLabel: some View {
        if let lastUsedAt = entry.lastUsedAt {
            Text("Last used \(lastUsedAt.formatted(date: .abbreviated, time: .omitted))")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Not used recently")
                .appTextRole(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trustIcon: String {
        switch entry.trust.level {
        case .excellent, .strong: return "checkmark.seal.fill"
        case .review: return "exclamationmark.circle.fill"
        case .low: return entry.trust.requiresCorrection ? "exclamationmark.triangle.fill" : "info.circle.fill"
        }
    }

    private var trustTint: Color {
        switch entry.trust.level {
        case .excellent, .strong: return .accentPositiveText
        case .review: return AppPalette.caution
        case .low: return entry.trust.requiresCorrection ? AppPalette.critical : AppPalette.caution
        }
    }
}

private extension MyFoodsLibraryFilter {
    var title: String {
        switch self {
        case .all: return "All foods"
        case .barcodeCorrections: return "Barcode corrections"
        case .manual: return "Manual foods"
        case .recipes: return "Recipes"
        case .recent: return "Used recently"
        case .needsReview: return "Needs review"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .barcodeCorrections: return "barcode.viewfinder"
        case .manual: return "square.and.pencil"
        case .recipes: return "book.closed"
        case .recent: return "clock"
        case .needsReview: return "exclamationmark.triangle"
        }
    }
}

private extension MyFoodsLibrarySort {
    var title: String {
        switch self {
        case .name: return "Name"
        case .lastUsed: return "Last used"
        case .trust: return "Trust"
        }
    }

    var systemImage: String {
        switch self {
        case .name: return "textformat"
        case .lastUsed: return "clock"
        case .trust: return "checkmark.seal"
        }
    }
}
