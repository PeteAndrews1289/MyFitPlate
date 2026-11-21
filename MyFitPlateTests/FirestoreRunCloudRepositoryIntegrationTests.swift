import XCTest
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseAppCheck
import MyFitPlateCore
@testable import MyFitPlate

private final class RunCloudEmulatorCheck: NSObject, AppCheckProvider {
    func getToken(completion: @escaping (AppCheckToken?, Error?) -> Void) {
        completion(AppCheckToken(token: "local-emulator-only", expirationDate: Date().addingTimeInterval(3_600)), nil)
    }
}
private final class RunCloudEmulatorCheckFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        app.name.hasPrefix("run-cloud-test-") ? RunCloudEmulatorCheck() : nil
    }
}

/// Opt-in transport tests against synthetic named Firebase apps and localhost
/// emulators. No production app, real account, or device history is used.
final class RunCloudRepositoryIntegrationTests: XCTestCase {
    private struct Client {
        let app: FirebaseApp
        let auth: Auth
        let db: Firestore
    }
    private var clients: [Client] = []
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MYFITPLATE_EMULATOR_TESTS"] == "YES", "Local emulator integration test")
        AppCheck.setAppCheckProviderFactory(RunCloudEmulatorCheckFactory())
    }
    override func tearDown() async throws {
        let ownedClients = clients
        clients.removeAll()
        var failures: [String] = []
        // Wait for each SDK's resource shutdown before deleting its app container.
        // Fire-and-forget deletion can overlap the following native test's startup.
        for client in ownedClients.reversed() {
            do {
                try await client.db.terminate()
                // The SDK permits persistence cleanup after termination. These are
                // unique emulator fixtures; no default app or owner cache is touched.
                try await client.db.clearPersistence()
            } catch { failures.append("Firestore cleanup for \(client.app.name): \(error.localizedDescription)") }
            do { try client.auth.signOut() } catch { failures.append("Auth cleanup for \(client.app.name): \(error.localizedDescription)") }
            let deleted: Bool = await withCheckedContinuation { continuation in
                client.app.delete { continuation.resume(returning: $0) }
            }
            if !deleted { failures.append("Firebase app deletion failed for \(client.app.name)") }
        }
        // There is no public getter for the prior process-global App Check factory.
        // Do not guess a restore value or reconfigure the host/default app here.
        try await super.tearDown()
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }
    private func client() -> (auth: Auth, db: Firestore) {
        let options = FirebaseOptions(googleAppID: "1:1234567890:ios:0123456789abcdef0123456789abcdef", gcmSenderID: "1234567890")
        options.projectID = "myfitplate-test-project"
        options.apiKey = "A" + String(repeating: "0", count: 38)
        let name = "run-cloud-test-\(UUID())"
        FirebaseApp.configure(name: name, options: options)
        let app = FirebaseApp.app(name: name)!
        // Prevent this synthetic app from leaving a periodic token-refresh timer.
        AppCheck.appCheck(app: app)?.isTokenAutoRefreshEnabled = false
        let auth = Auth.auth(app: app)
        auth.useEmulator(withHost: "127.0.0.1", port: 9099)
        let db = Firestore.firestore(app: app)
        db.useEmulator(withHost: "127.0.0.1", port: 8080)
        let settings = db.settings; settings.isSSLEnabled = false; db.settings = settings
        clients.append(Client(app: app, auth: auth, db: db))
        return (auth, db)
    }
    private func revision(_ owner: String, scope: RunCloudScope = .workouts, key: String = "plan/shared", parents: [String] = [], text: String) throws -> RunCloudRevision {
        try RunCloudRevision(ownerID: owner, scope: scope, key: key, parents: parents, payload: Data(text.utf8))
    }
    private func heads(db: Firestore, owner: String, scope: RunCloudScope, key: String) async throws -> Set<String> {
        let id = try PlanFingerprint.make([scope.rawValue, key])
        let snapshot = try await db.collection("users").document(owner).collection("runLibraryHeads").document(id).getDocument(source: .server)
        let data = try XCTUnwrap(snapshot.data())
        XCTAssertEqual(data["ownerID"] as? String, owner)
        XCTAssertEqual(data["scope"] as? String, scope.rawValue)
        XCTAssertEqual(data["key"] as? String, key)
        return Set(try XCTUnwrap(data["heads"] as? [String]))
    }

    func testConcurrentSameItemBranchesKeepBothHeadsAndExactAncestorRetriesNeverResurrectThem() async throws {
        let one = client(), two = client()
        // A generated credential belongs only to this local Auth emulator fixture.
        let email = "run-cloud-\(UUID().uuidString.lowercased())@example.invalid"
        let password = "Local-emulator-\(UUID().uuidString)"
        let owner = try await one.auth.createUser(withEmail: email, password: password).user.uid
        let secondOwner = try await two.auth.signIn(withEmail: email, password: password).user.uid
        XCTAssertEqual(secondOwner, owner)
        let first = FirestoreRunCloudRepository(db: one.db, currentOwner: { one.auth.currentUser?.uid })
        let second = FirestoreRunCloudRepository(db: two.db, currentOwner: { two.auth.currentUser?.uid })
        let root = try revision(owner, text: "original workout")
        try await first.publish(root)
        let a = try revision(owner, parents: [root.id], text: "first device edit")
        let b = try revision(owner, parents: [root.id], text: "second device edit")
        async let publishA: Void = first.publish(a)
        async let publishB: Void = second.publish(b)
        _ = try await (publishA, publishB)
        let concurrent = try await heads(db: one.db, owner: owner, scope: .workouts, key: root.key)
        XCTAssertEqual(concurrent, Set([a.id, b.id]))
        try await first.publish(root)
        try await second.publish(a)
        let retried = try await heads(db: two.db, owner: owner, scope: .workouts, key: root.key)
        XCTAssertEqual(retried, concurrent, "Lost acknowledgements cannot make an ancestor current again")
        let merge = try revision(owner, parents: [a.id, b.id], text: "reviewed combined workout")
        try await first.publish(merge)
        try await second.publish(root); try await second.publish(b); try await first.publish(merge)
        let finalHeads = try await heads(db: one.db, owner: owner, scope: .workouts, key: root.key)
        XCTAssertEqual(finalHeads, [merge.id])
        let all = try await second.fetch(userID: owner, scope: .workouts)
        XCTAssertEqual(Set(all.map(\.id)), Set([root.id, a.id, b.id, merge.id]))
        let graph = try RunCloudGraph.validated(all, ownerID: owner, scope: .workouts)
        XCTAssertEqual(RunCloudGraph.heads(graph)[root.key]?.map(\.id), [merge.id])
        XCTAssertEqual(graph[root.id], root); XCTAssertEqual(graph[a.id], a); XCTAssertEqual(graph[b.id], b)
    }

    func testFetchPaginatesTheCompleteGraphAndSeparatesScopeAndAccount() async throws {
        let one = client(), other = client()
        let owner = try await one.auth.signInAnonymously().user.uid
        let otherOwner = try await other.auth.signInAnonymously().user.uid
        let repository = FirestoreRunCloudRepository(db: one.db, currentOwner: { one.auth.currentUser?.uid })
        let otherRepository = FirestoreRunCloudRepository(db: other.db, currentOwner: { other.auth.currentUser?.uid })
        var chain: [RunCloudRevision] = []
        for index in 0..<305 {
            chain.append(try revision(owner, key: "plan/paged", parents: chain.last.map { [$0.id] } ?? [], text: "revision \(index)"))
        }
        // Seed valid immutable graph documents in one emulator-only batch. Their
        // hashed IDs scramble ancestry across the repository's 300-item pages.
        let batch = one.db.batch()
        for item in chain {
            batch.setData(try Firestore.Encoder().encode(item), forDocument: one.db.collection("users").document(owner).collection("runLibraryRevisions").document(item.id))
        }
        try await batch.commit()
        let block = try revision(owner, scope: .blocks, key: "block/private", text: "own block")
        let stranger = try revision(otherOwner, key: "plan/private", text: "other account")
        try await repository.publish(block); try await otherRepository.publish(stranger)
        let fetched = try await repository.fetch(userID: owner, scope: .workouts)
        XCTAssertEqual(fetched.count, chain.count)
        XCTAssertEqual(Set(fetched.map(\.id)), Set(chain.map(\.id)))
        XCTAssertTrue(fetched.allSatisfy { $0.ownerID == owner && $0.scope == .workouts })
        let graph = try RunCloudGraph.validated(fetched, ownerID: owner, scope: .workouts)
        XCTAssertEqual(RunCloudGraph.heads(graph)["plan/paged"]?.map(\.id), [chain.last!.id])
        let ownBlocks = try await repository.fetch(userID: owner, scope: .blocks)
        XCTAssertEqual(ownBlocks, [block])
        let otherWorkouts = try await otherRepository.fetch(userID: otherOwner, scope: .workouts)
        XCTAssertEqual(otherWorkouts, [stranger])
    }

    func testWrongOwnerFetchAndPublishAreRejectedWithoutCreatingAnyDocuments() async throws {
        let one = client(), other = client()
        let owner = try await one.auth.signInAnonymously().user.uid
        let otherOwner = try await other.auth.signInAnonymously().user.uid
        let repository = FirestoreRunCloudRepository(db: one.db, currentOwner: { one.auth.currentUser?.uid })
        let forbidden = try revision(otherOwner, text: "must not be written")
        do { try await repository.publish(forbidden); XCTFail("Wrong-owner publish must fail before transport") } catch RunCloudError.accountChanged { }
        do { _ = try await repository.fetch(userID: otherOwner, scope: .workouts); XCTFail("Wrong-owner read must fail") } catch RunCloudError.accountChanged { }
        let untouched = try await other.db.collection("users").document(otherOwner).collection("runLibraryRevisions").getDocuments(source: .server)
        XCTAssertTrue(untouched.documents.isEmpty)
        try one.auth.signOut()
        do { _ = try await repository.fetch(userID: owner, scope: .workouts); XCTFail("A signed-out repository must not use its prior owner") } catch RunCloudError.accountChanged { }
    }

    func testRunPublicationAndRetryLeavePHULProgressAndExistingFoodAndWorkoutLogsIdentical() async throws {
        let client = client()
        let owner = try await client.auth.signInAnonymously().user.uid
        let user = client.db.collection("users").document(owner)
        let phul = user.collection("workoutPrograms").document("existing-phul")
        let diary = user.collection("dailyLogs").document("2026-11-04")
        let workout = user.collection("workoutSessionLogs").document("existing-strength-session")
        try await user.setData(["activeWorkoutProgramID": "existing-phul", "activeWorkoutProgramCleared": false,
            "goals": ["calories": 2_137, "protein": 160, "waterGoal": 93], "unrelated": "keep"])
        try await phul.setData(["id": "existing-phul", "name": "PHUL", "isActive": true, "currentProgressIndex": 39,
            "progressEpoch": "accepted-phul-epoch", "skippedIndices": [8, 17],
            "slotCompletionProofs": ["38": "accepted-strength-proof"], "routines": ["Lower Power", "Upper Power", "Lower Hypertrophy", "Upper Hypertrophy"]])
        try await diary.setData(["date": Timestamp(date: Date(timeIntervalSince1970: 1_793_750_400)),
            "meals": [["id": "saved-lunch", "name": "Lunch", "foodItems": [["id": "saved-rice", "name": "Rice", "calories": 300, "protein": 6]]]],
            "waterTracker": ["totalOunces": 72, "goalOunces": 93], "nutritionDayStatus": "partial"])
        try await workout.setData(["id": "existing-strength-session", "programID": "existing-phul", "programProgressIndex": 38,
            "exercises": [["exerciseID": "bench", "sets": [["weight": 135, "reps": 10, "completed": true]]]]])
        let references = [user, phul, diary, workout]
        var before: [NSDictionary] = []
        for reference in references {
            let snapshot = try await reference.getDocument(source: .server)
            before.append(try XCTUnwrap(snapshot.data()) as NSDictionary)
        }
        let repository = FirestoreRunCloudRepository(db: client.db, currentOwner: { client.auth.currentUser?.uid })
        for scope in RunCloudScope.allCases {
            let first = try revision(owner, scope: scope, key: "plan/\(scope.rawValue)", text: "saved running record")
            let next = try revision(owner, scope: scope, key: first.key, parents: [first.id], text: "reviewed running edit")
            try await repository.publish(first); try await repository.publish(next); try await repository.publish(first)
            let fetched = try await repository.fetch(userID: owner, scope: scope)
            XCTAssertEqual(Set(fetched.map(\.id)), [first.id, next.id])
        }
        for (index, reference) in references.enumerated() {
            let snapshot = try await reference.getDocument(source: .server)
            let after = try XCTUnwrap(snapshot.data()) as NSDictionary
            XCTAssertEqual(after, before[index], "Running sync must not change \(reference.path)")
        }
    }

    func testMissingParentsAndRewrittenAcceptedReceiptNeverCommitARevisionOrHead() async throws {
        let client = client(), owner = try await client.auth.signInAnonymously().user.uid
        let repository = FirestoreRunCloudRepository(db: client.db, currentOwner: { client.auth.currentUser?.uid })
        let missing = try revision(owner, parents: ["missing-parent"], text: "unrelated")
        do { try await repository.publish(missing); XCTFail("Missing parent must fail transactionally") } catch { }
        let accepted = try revision(owner, scope: .reviews, key: "receipt/accepted", text: "accepted facts")
        try await repository.publish(accepted)
        let rewritten = try revision(owner, scope: .reviews, key: accepted.key, parents: [accepted.id], text: "rewritten facts")
        do { try await repository.publish(rewritten); XCTFail("Accepted evidence must be immutable") } catch { }
        let reviews = try await repository.fetch(userID: owner, scope: .reviews)
        XCTAssertEqual(reviews, [accepted])
        let reviewHeads = try await heads(db: client.db, owner: owner, scope: .reviews, key: accepted.key)
        XCTAssertEqual(reviewHeads, [accepted.id])
        let workouts = try await repository.fetch(userID: owner, scope: .workouts)
        XCTAssertTrue(workouts.isEmpty)
    }
}
