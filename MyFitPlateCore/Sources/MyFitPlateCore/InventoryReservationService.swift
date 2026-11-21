import Combine
import Foundation

@MainActor
public final class InventoryReservationService: ObservableObject {
    @Published private var storedSnapshot: InventoryReservationSnapshot?
    @Published public private(set) var isLoading = false
    @Published public private(set) var isFresh = false
    @Published public private(set) var errorMessage: String?
    public let userID: String?
    private let drafts: EditorDraftStore
    private let auth: AuthServiceProtocol?
    private var observer: Any?
    private var generation = UUID()
    private let scope = "inventory-planned-reservations"
    public var snapshot: InventoryReservationSnapshot? { active ? storedSnapshot : nil }
    private var active: Bool { userID != nil && auth?.currentUserID == userID }

    public init(userID: String? = nil, drafts: EditorDraftStore = EditorDraftStore(), auth: AuthServiceProtocol? = nil) {
        self.auth = auth ?? DIContainer.shared.authService
        self.userID = userID ?? self.auth?.currentUserID; self.drafts = drafts
        if let owner = self.userID {
            do { storedSnapshot = try drafts.load(InventoryReservationSnapshot.self, userID: owner, scope: scope)?.value } catch { errorMessage = "The previous reservation display could not be read. Its stored data is kept; refresh to inspect current saved plans." }
        }
        observer = self.auth?.observeAuthState { [weak self] id in
            Task { @MainActor [weak self] in
                guard let self, id != self.userID else { return }
                self.generation = UUID(); self.storedSnapshot = nil; self.isFresh = false; self.isLoading = false
            }
        }
    }
    deinit { if let observer { auth?.removeObserver(observer) } }

    @discardableResult
    public func refresh(using repository: NutritionRepositoryProtocol, includingBatchID: String? = nil, now: Date = Date()) async -> Bool {
        guard active, let userID else { return false }
        guard let referenceDayID = DiaryDayContext.dayKey(for: now) else {
            errorMessage = "The reservation date could not be established. Existing data is kept."; return false
        }
        let request = UUID(); generation = request; isLoading = true; isFresh = false
        do {
            async let physical = repository.fetchInventory(userID: userID)
            async let plans = repository.fetchMealPlansForStockReservations(userID: userID)
            let result = try await InventoryReservationRules.snapshot(plans: plans, stock: physical,
                referenceDayID: referenceDayID, now: now, includingBatchID: includingBatchID)
            guard active, generation == request else { return false }
            storedSnapshot = result; isFresh = true; isLoading = false; errorMessage = nil
            if includingBatchID == nil {
                do {
                    let existing = try drafts.load(InventoryReservationSnapshot.self, userID: userID, scope: scope)?.value
                    if existing.map({ $0.generatedAt <= result.generatedAt }) != false { try drafts.save(result, userID: userID, scope: scope) }
                } catch { errorMessage = "Current reservations are shown, but their offline display could not be saved. Existing stored data is kept." }
            }
            return true
        } catch {
            guard active, generation == request else { return false }
            isLoading = false; errorMessage = "Current reservations are unavailable. Any previous display is stale; it must not be treated as free stock. " + error.localizedDescription
            return false
        }
    }
}
