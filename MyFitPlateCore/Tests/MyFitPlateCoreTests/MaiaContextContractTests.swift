import XCTest
@testable import MyFitPlateCore

final class MaiaContextContractTests: XCTestCase {
    func testContextContractOrdersAndDeduplicatesScopes() {
        let contract = MaiaContextContract(
            action: "test_action",
            scopes: [.pantry, .todayLog, .todayLog, .healthKit]
        )

        XCTAssertEqual(contract.scopes, [.todayLog, .healthKit, .pantry])
        XCTAssertEqual(contract.telemetryScopeList, "today_log,healthkit,pantry")
        XCTAssertTrue(contract.promptSummary.contains("test_action"))
        XCTAssertTrue(contract.promptSummary.contains("today's food totals"))
    }

    func testActionContractsOnlyAllowExpectedContext() {
        XCTAssertTrue(MaiaContextContract.recoveryMeal.allows(.loggedTraining))
        XCTAssertTrue(MaiaContextContract.recoveryMeal.allows(.nutritionGoals))
        XCTAssertFalse(MaiaContextContract.recoveryMeal.allows(.healthKit))

        XCTAssertTrue(MaiaContextContract.proteinAnchor.allows(.nutritionGoals))
        XCTAssertFalse(MaiaContextContract.proteinAnchor.allows(.loggedTraining))

        XCTAssertTrue(MaiaContextContract.trustAudit.allows(.nutritionAudit))
        XCTAssertFalse(MaiaContextContract.trustAudit.allows(.water))

        XCTAssertTrue(MaiaContextContract.fillMacros.allows(.pantry))
        XCTAssertFalse(MaiaContextContract.hydration.allows(.todayLog))
    }

    func testDailyReadAddsHealthKitOnlyWhenRequested() {
        let localRead = MaiaContextContract.dailyRead(includeHealthKit: false)
        let healthRead = MaiaContextContract.dailyRead(includeHealthKit: true)

        XCTAssertFalse(localRead.allows(.healthKit))
        XCTAssertTrue(healthRead.allows(.healthKit))
        XCTAssertTrue(healthRead.telemetryScopeList.contains("healthkit"))
    }

    func testActionPayloadValidationAcceptsRenderableLegacyMealCard() throws {
        let payload = try decodePayload("""
        {
          "mealName": "Greek yogurt bowl",
          "calories": 320,
          "protein": 32,
          "carbs": 35,
          "fats": 6
        }
        """)

        XCTAssertNil(payload.validationIssueKind)
        XCTAssertTrue(payload.isRenderableAction)
    }

    func testActionPayloadValidationRejectsDecodedButIncompleteCard() throws {
        let payload = try decodePayload("""
        {
          "type": "meal_suggestion",
          "mealName": "Chicken bowl",
          "protein": 35,
          "carbs": 42,
          "fats": 11
        }
        """)

        XCTAssertEqual(payload.validationIssueKind, "meal_suggestion_missing_fields")
        XCTAssertFalse(payload.isRenderableAction)
    }

    func testActionPayloadValidationRejectsUnknownActionType() throws {
        let payload = try decodePayload("""
        {
          "type": "order_takeout",
          "mealName": "Pizza"
        }
        """)

        XCTAssertEqual(payload.validationIssueKind, "unknown_action_type")
    }

    private func decodePayload(_ json: String) throws -> MaiaActionPayload {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try JSONDecoder().decode(MaiaActionPayload.self, from: data)
    }
}
