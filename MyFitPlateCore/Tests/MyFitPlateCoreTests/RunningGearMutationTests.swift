import XCTest
@testable import MyFitPlateCore

final class RunningGearMutationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var auth: MockAuthService!
    private var store: RunningShoeStore!
    private let date = Date(timeIntervalSince1970: 1_800_000_000)
    override func setUp() {
        super.setUp()
        suite = "RunningGearMutationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        auth = MockAuthService(); auth.currentUserID = "a"
        store = RunningShoeStore(userDefaults: defaults, authService: auth)
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite); super.tearDown() }
    private func recordedRun(_ id: String, distance: Double = 5000) -> Run {
        Run(id: id, source: .recorded, startDate: date, endDate: date.addingTimeInterval(1500), distanceMeters: distance, movingSeconds: 1500, recordingID: "recording-\(id)")
    }

    func testShoeEditsPreserveTagsAndInitialMileageCorrectionHistoryAndRejectStaleReview() throws {
        let shoe = RunningShoe(id: "pair", name: "Trainer", brand: "Brand", initialMeters: 1000, isDefault: true)
        let first = try store.saveReviewed(shoe, replacing: nil, operationID: "add", userID: "a")
        let run = recordedRun("health")
        _ = try store.commitAssignment(store.reviewAssignment(runs: [run], shoeID: shoe.id, userID: "a"))
        var edited = shoe; edited.initialMeters = 2000; edited.nickname = "Daily pair"
        _ = try store.saveReviewed(edited, replacing: shoe, operationID: "edit", userID: "a")
        XCTAssertEqual(try store.saveReviewed(shoe, replacing: nil, operationID: "add", userID: "a"), first)
        XCTAssertEqual(store.shoe(for: shoe.id)?.nickname, "Daily pair")
        XCTAssertEqual(store.totalMeters(for: shoe.id, across: [run]), 7000)
        XCTAssertEqual(store.revisions(for: shoe.id).last?.before?.initialMeters, 1000)
        XCTAssertThrowsError(try store.saveReviewed(shoe, replacing: shoe, operationID: "stale", userID: "a"))
        XCTAssertThrowsError(try store.removeUnusedShoe(edited, across: [run], userID: "a"))
        store.retireShoe(id: shoe.id)
        XCTAssertNil(store.defaultShoe())
        XCTAssertEqual(store.explicitShoeID(for: run), shoe.id)
    }

    func testReviewedBatchRetryAliasUndoAndNewerConflictAreOneAtomicAssignment() throws {
        let a = RunningShoe(id: "a", name: "First", brand: "Brand")
        let b = RunningShoe(id: "b", name: "Second", brand: "Brand")
        store.addShoe(a); store.addShoe(b)
        let run1 = recordedRun("one"), run2 = recordedRun("two", distance: 7000)
        let review = try store.reviewAssignment(runs: [run1, run2], shoeID: a.id, userID: "a", operationID: "batch")
        let receipt = try store.commitAssignment(review)
        let reloaded = RunningShoeStore(userDefaults: defaults, authService: auth)
        XCTAssertEqual(try reloaded.commitAssignment(review), receipt)
        XCTAssertEqual(reloaded.totalMeters(for: a.id, across: [run1, run1.reidentified(as: "alias"), run2]), 12000)
        XCTAssertEqual(reloaded.contributingRuns(for: a.id, across: [run1, run2]).count, 2)
        try reloaded.undoAssignment(receipt)
        try reloaded.undoAssignment(receipt)
        XCTAssertNil(reloaded.explicitShoeID(for: run1.reidentified(as: "alias")))
        XCTAssertNil(reloaded.explicitShoeID(for: run2))
        let changed = try reloaded.commitAssignment(reloaded.reviewAssignment(runs: [run1], shoeID: a.id, userID: "a"))
        reloaded.tagRun(runID: run1.id, withShoeID: b.id)
        XCTAssertThrowsError(try reloaded.undoAssignment(changed), "Known Health aliases cannot bypass Undo conflict checks")
        XCTAssertEqual(reloaded.explicitShoeID(for: run1), b.id)
    }

    func testAccountSwitchAndConcurrentBatchFailurePreserveAllAssignments() throws {
        let shoe = RunningShoe(id: "pair", name: "Trainer", brand: "Brand")
        store.addShoe(shoe)
        let one = recordedRun("one"), two = recordedRun("two")
        let review = try store.reviewAssignment(runs: [one, two], shoeID: shoe.id, userID: "a")
        store.tagRun(one, withShoeID: shoe.id)
        XCTAssertThrowsError(try store.commitAssignment(review))
        XCTAssertNil(store.explicitShoeID(for: two), "A stale batch cannot partly write its other rows")
        auth.currentUserID = "b"
        XCTAssertThrowsError(try store.commitAssignment(review))
        XCTAssertTrue(store.shoes.isEmpty)
        auth.currentUserID = "a"
        XCTAssertEqual(store.explicitShoeID(for: one), shoe.id)
    }

    func testLegacyPlaceholderDoesNotClaimOwnershipOrDefaultAndUnknownSchemaIsPreserved() throws {
        var placeholder = RunningShoe(id: "old-placeholder", name: "Road Trainer", brand: "Default", isDefault: true)
        placeholder.ownershipConfirmed = nil
        let key = try XCTUnwrap(AccountScopedStorageKey.make(prefix: "myfitplate.running_shoes", userID: "a"))
        defaults.set(try JSONEncoder().encode([placeholder]), forKey: key)
        let legacy = RunningShoeStore(userDefaults: defaults, authService: auth)
        XCTAssertEqual(legacy.shoes.first?.id, placeholder.id)
        XCTAssertTrue(legacy.shoes.first?.isUnconfirmedPlaceholder == true)
        XCTAssertNil(legacy.defaultShoe())
        var confirmed = placeholder; confirmed.brand = "Actual brand"; confirmed.ownershipConfirmed = true
        _ = try legacy.saveReviewed(confirmed, replacing: placeholder, operationID: "confirm", userID: "a")
        XCTAssertEqual(legacy.defaultShoe()?.id, placeholder.id)
        let corrupt = Data("{\"schema\":99}".utf8)
        defaults.set(corrupt, forKey: key)
        legacy.tagRun(runID: "run", withShoeID: placeholder.id)
        XCTAssertEqual(defaults.data(forKey: key), corrupt)
        XCTAssertNotNil(legacy.lastError)
    }
}
