import XCTest
@testable import MyFitPlateCore

@MainActor
final class GroupServiceTests: XCTestCase {
    private var service: GroupService!
    private var mockRepo: MockGroupRepository!

    override func setUp() {
        super.setUp()
        mockRepo = MockGroupRepository()
        DIContainer.shared.groupRepository = mockRepo
        service = GroupService()
    }

    override func tearDown() {
        service = nil
        mockRepo = nil
        super.tearDown()
    }

    private func group(id: String, name: String = "Strength Club") -> CommunityGroup {
        CommunityGroup(id: id, name: name, description: "Train together", creatorID: "coach")
    }

    func testCreateGroupBuildsGroupAndPersistsIt() async throws {
        let finished = expectation(description: "create group")

        service.createGroup(name: "Runners", description: "Morning miles", creatorID: "user-1") { result in
            switch result {
            case .success(let created):
                XCTAssertEqual(created.name, "Runners")
                XCTAssertEqual(created.description, "Morning miles")
                XCTAssertEqual(created.creatorID, "user-1")
                XCTAssertEqual(created.isPreset, false)
                XCTAssertNotNil(created.id)
            case .failure:
                XCTFail("expected create success")
            }
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 1.0)
        let persisted = try XCTUnwrap(mockRepo.createdGroups.first)
        XCTAssertEqual(persisted.name, "Runners")
        XCTAssertEqual(persisted.creatorID, "user-1")
    }

    func testCreateGroupPropagatesRepositoryFailure() async {
        mockRepo.error = URLError(.cannotConnectToHost)
        let finished = expectation(description: "create group failure")

        service.createGroup(name: "Runners", description: "Morning miles", creatorID: "user-1") { result in
            if case .failure = result {} else {
                XCTFail("expected create failure")
            }
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 1.0)
        XCTAssertTrue(mockRepo.createdGroups.isEmpty)
    }

    func testFetchGroupsReturnsRepositoryGroupsInOrder() async {
        mockRepo.groupsToFetch = [group(id: "a", name: "A"), group(id: "b", name: "B")]
        let finished = expectation(description: "fetch groups")

        service.fetchGroups { result in
            switch result {
            case .success(let groups):
                XCTAssertEqual(groups.map(\.id), ["a", "b"])
                XCTAssertEqual(groups.map(\.name), ["A", "B"])
            case .failure:
                XCTFail("expected fetch success")
            }
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 1.0)
    }

    func testFetchGroupsPropagatesRepositoryFailure() async {
        mockRepo.error = URLError(.timedOut)
        let finished = expectation(description: "fetch groups failure")

        service.fetchGroups { result in
            if case .failure = result {} else {
                XCTFail("expected fetch failure")
            }
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 1.0)
    }

    func testJoinGroupRecordsMembershipJoin() async {
        let finished = expectation(description: "join group")

        service.joinGroup(userID: "user-1", groupID: "group-1") { error in
            XCTAssertNil(error)
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 1.0)
        XCTAssertEqual(mockRepo.joinedGroups.map(\.userID), ["user-1"])
        XCTAssertEqual(mockRepo.joinedGroups.map(\.groupID), ["group-1"])
    }

    func testJoinGroupPropagatesRepositoryFailure() async {
        mockRepo.error = URLError(.badServerResponse)
        let finished = expectation(description: "join group failure")

        service.joinGroup(userID: "user-1", groupID: "group-1") { error in
            XCTAssertNotNil(error)
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 1.0)
        XCTAssertTrue(mockRepo.joinedGroups.isEmpty)
    }

    func testLeaveGroupRecordsMembershipLeave() async {
        let finished = expectation(description: "leave group")

        service.leaveGroup(userID: "user-1", groupID: "group-1") { error in
            XCTAssertNil(error)
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 1.0)
        XCTAssertEqual(mockRepo.leftGroups.map(\.userID), ["user-1"])
        XCTAssertEqual(mockRepo.leftGroups.map(\.groupID), ["group-1"])
    }

    func testLeaveGroupPropagatesRepositoryFailure() async {
        mockRepo.error = URLError(.badURL)
        let finished = expectation(description: "leave group failure")

        service.leaveGroup(userID: "user-1", groupID: "group-1") { error in
            XCTAssertNotNil(error)
            finished.fulfill()
        }

        await fulfillment(of: [finished], timeout: 1.0)
        XCTAssertTrue(mockRepo.leftGroups.isEmpty)
    }
}
