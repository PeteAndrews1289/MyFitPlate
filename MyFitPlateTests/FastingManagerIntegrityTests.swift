import XCTest
import MyFitPlateCore
@testable import MyFitPlate

@MainActor
final class FastingManagerIntegrityTests: XCTestCase {
    private var directory: URL!
    private var originalAuth: AuthServiceProtocol!

    override func setUpWithError() throws {
        originalAuth = DIContainer.shared.authService
        DIContainer.shared.authService = MockAuthService()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        DIContainer.shared.authService = originalAuth
        try? FileManager.default.removeItem(at: directory)
    }

    func testLockScreenActionsAreRegisteredInTheContainingApp() throws {
        // iOS dispatches each LiveActivityIntent to the containing app when its button is tapped.
        let metadataURL = try XCTUnwrap(Bundle.main.url(forResource: "extract", withExtension: "actionsdata",
                                                       subdirectory: "Metadata.appintents"))
        let data = try Data(contentsOf: metadataURL)
        let metadata = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let actions = try XCTUnwrap(metadata["actions"] as? [String: Any])
        for identifier in ["EndFastIntent", "EndRestIntent"] {
            XCTAssertNotNil(actions[identifier], "The containing app must register \(identifier).")
        }
    }

    func testTimerStartsAndRecoversWhenLockScreenProjectionIsDisabled() throws {
        let store = FastingSessionStore(directory: directory)
        let first = FastingManager(store: store, projectsActivities: false)
        first.activateAccount("mock_user")
        XCTAssertTrue(first.startFast(hours: 16))
        let session = try XCTUnwrap(first.session)
        XCTAssertNotNil(first.projectionMessage)
        let relaunched = FastingManager(store: store, projectsActivities: false)
        relaunched.activateAccount("mock_user")
        XCTAssertEqual(relaunched.session, session)
        XCTAssertTrue(relaunched.endFast())
        let afterEnd = FastingManager(store: store, projectsActivities: false)
        afterEnd.activateAccount("mock_user")
        XCTAssertFalse(afterEnd.isFasting)
        XCTAssertEqual(afterEnd.lastEndedSession?.id, session.id)
    }

    func testExternalEndUpdatesForegroundOnRecoveryWithoutChangingIdentity() throws {
        let store = FastingSessionStore(directory: directory)
        let manager = FastingManager(store: store, projectsActivities: false)
        manager.activateAccount("mock_user")
        XCTAssertTrue(manager.startFast(hours: 12))
        let fast = try XCTUnwrap(manager.session)
        _ = try store.end(ownerScope: fast.ownerScope, sessionID: fast.id, expectedRevision: fast.revision)
        manager.recoverState()
        XCTAssertFalse(manager.isFasting)
        XCTAssertEqual(manager.lastEndedSession?.id, fast.id)
    }

    func testUnavailableDurableStorageDoesNotReportSuccess() {
        let manager = FastingManager(store: FastingSessionStore(directory: nil), projectsActivities: false)
        manager.activateAccount("mock_user")
        XCTAssertFalse(manager.startFast(hours: 16))
        XCTAssertFalse(manager.isFasting)
        XCTAssertNotNil(manager.errorMessage)
    }

    func testSignOutKeepsOriginalSessionRecoverableAndRejectsStaleStart() throws {
        let manager = FastingManager(store: FastingSessionStore(directory: directory), projectsActivities: false)
        manager.activateAccount("mock_user")
        XCTAssertTrue(manager.startFast(hours: 16))
        let original = manager.session
        manager.activateAccount(nil)
        XCTAssertFalse(manager.isFasting)
        XCTAssertFalse(manager.startFast(hours: 12))
        manager.activateAccount("mock_user")
        XCTAssertEqual(manager.session, original)
    }
}
