import XCTest
@testable import MyFitPlateCore

final class MilestoneGeneratorTests: XCTestCase {
    func testLosingWeightMilestonesTrackCompletedAndCurrentSegmentProgress() {
        let milestones = MilestoneGenerator.makeMilestones(
            initialWeight: 220,
            currentWeight: 205,
            targetWeight: 170,
            numberOfMilestones: 5,
            useMetric: false
        )

        XCTAssertEqual(milestones.count, 5)
        XCTAssertEqual(milestones.map(\.targetWeightForMilestone), [210, 200, 190, 180, 170])
        XCTAssertEqual(milestones.map(\.isCompleted), [true, false, false, false, false])
        XCTAssertEqual(milestones[1].progressToNextMilestone, 0.5, accuracy: 0.001)
        XCTAssertEqual(milestones[0].displayLabel, "-10.0 lbs")
    }

    func testGainingWeightMilestonesTrackCompletedAndCurrentSegmentProgress() {
        let milestones = MilestoneGenerator.makeMilestones(
            initialWeight: 150,
            currentWeight: 163,
            targetWeight: 180,
            numberOfMilestones: 3,
            useMetric: false
        )

        XCTAssertEqual(milestones.count, 3)
        XCTAssertEqual(milestones.map(\.targetWeightForMilestone), [160, 170, 180])
        XCTAssertEqual(milestones.map(\.isCompleted), [true, false, false])
        XCTAssertEqual(milestones[1].progressToNextMilestone, 0.3, accuracy: 0.001)
        XCTAssertEqual(milestones[0].displayLabel, "+10.0 lbs")
    }

    func testNoMilestonesWhenInitialAndTargetWeightsMatch() {
        let milestones = MilestoneGenerator.makeMilestones(
            initialWeight: 180,
            currentWeight: 180,
            targetWeight: 180,
            useMetric: false
        )

        XCTAssertTrue(milestones.isEmpty)
    }

    func testMetricLabelsConvertSegmentWeight() {
        let milestones = MilestoneGenerator.makeMilestones(
            initialWeight: 220,
            currentWeight: 220,
            targetWeight: 209,
            numberOfMilestones: 1,
            useMetric: true
        )

        XCTAssertEqual(milestones.first?.displayLabel, "-5.0 kg")
    }

    @MainActor
    func testMilestoneViewBody() {
        let view = MilestoneView(initialWeight: 200, currentWeight: 190, targetWeight: 150)
        let body = view.body
        XCTAssertNotNil(body)
        
        // Empty milestones view
        let viewEmpty = MilestoneView(initialWeight: 200, currentWeight: 200, targetWeight: 200)
        let bodyEmpty = viewEmpty.body
        XCTAssertNotNil(bodyEmpty)
    }
}
