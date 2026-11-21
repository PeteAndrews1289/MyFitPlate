import XCTest
import UIKit
@testable import MyFitPlate
import MyFitPlateCore

@MainActor
final class RecipePhotoImportOCRTests: XCTestCase {
    private func printedPage(_ text: String) throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1_600, height: 1_600), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1_600, height: 1_600))
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 14
            (text as NSString).draw(in: CGRect(x: 70, y: 70, width: 1_460, height: 1_460), withAttributes: [
                .font: UIFont.systemFont(ofSize: 52), .foregroundColor: UIColor.black, .paragraphStyle: paragraph
            ])
        }
        return try XCTUnwrap(image.pngData())
    }
    private var recipeText: String {
        "LEMON RICE\nIngredients\n1 cup rice\n2 cups water\n1 tbsp olive oil\nMethod\n1. Rinse the rice.\n2. Bring water to a simmer.\n3. Cook rice for 15 minutes.\n4. Stir in olive oil and serve."
    }

    func testActualOnDeviceVisionReadsPrintedIngredientsAndMethod() async throws {
        let data = try printedPage(recipeText)
        let page = try await Task.detached { try RecipePhotoOCR.page(from: data) }.value
        let text = page.reviewedText.lowercased()
        XCTAssertTrue(text.contains("ingredients"))
        XCTAssertTrue(text.contains("1 cup rice"))
        XCTAssertTrue(text.contains("15 minutes"))
        XCTAssertFalse(page.lines.isEmpty)
        XCTAssertTrue(page.lines.allSatisfy { $0.confidence.isFinite && (0...1).contains($0.confidence) })
        XCTAssertLessThanOrEqual(try XCTUnwrap(page.preview).count, 2_000_000)
        var draft = RecipeDocumentDraft(); try draft.append(page)
        XCTAssertTrue(draft.looksLikeRecipe)
        XCTAssertThrowsError(try draft.append(page), "The same captured page must not be appended twice")
    }

    func testBlankPhotoIsNotInventedIntoRecipeText() async throws {
        let data = try printedPage("")
        do {
            _ = try await Task.detached { try RecipePhotoOCR.page(from: data) }.value
            XCTFail("A blank image should produce an actionable no-text result")
        } catch { XCTAssertTrue(error is RecipeDocumentError) }
    }

    func testRecognizedNonRecipeTextDoesNotSatisfyRecipeReviewGate() async throws {
        let data = try printedPage("OUR FAMILY TABLE\nA photograph of lunch\nGood food and good company\nA lovely day together")
        let page = try await Task.detached { try RecipePhotoOCR.page(from: data) }.value
        var draft = RecipeDocumentDraft(); try draft.append(page)
        XCTAssertFalse(draft.looksLikeRecipe, "Recognized prose cannot establish ingredient amounts and instructions")
    }

    func testCaptureRecoveryPrivacyAndExactSubmissionCleanupProtectLaterCorrections() async throws {
        let previousAuth = DIContainer.shared.authService
        let auth = MockAuthService(); auth.currentUserID = "recipe-photo-native-test"
        DIContainer.shared.authService = auth
        defer { DIContainer.shared.authService = previousAuth }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory)
        let model = RecipePhotoImportModel(userID: auth.currentUserID, store: store)
        await model.recognize([try printedPage(recipeText)])
        let page = try XCTUnwrap(model.checkpoint.draft.pages.first)
        model.setChecked(page.id, value: true)
        model.setRetainSource(false)
        let submitted = try XCTUnwrap(model.reviewed())
        XCTAssertNil(model.reviewed(), "One sheet emits its reviewed document only once")
        XCTAssertNil(submitted.1.originalText)
        XCTAssertTrue(submitted.1.uncertainLines.isEmpty)
        let restored = RecipePhotoImportModel(userID: auth.currentUserID, store: store)
        XCTAssertTrue(restored.restored)
        XCTAssertEqual(restored.checkpoint.draft.pages[0].reviewedText, page.reviewedText)
        XCTAssertEqual(restored.checkpoint.submission, submitted.1)
        restored.editText(pageID: page.id, text: page.reviewedText + "\nServe with lemon.")
        XCTAssertTrue(restored.flush())
        try RecipePhotoImportCheckpointStore.finish(userID: auth.currentUserID!, provenance: submitted.1, store: store)
        let newer = RecipePhotoImportModel(userID: auth.currentUserID, store: store)
        XCTAssertTrue(newer.restored)
        XCTAssertTrue(newer.checkpoint.draft.combinedText.contains("Serve with lemon."))
        newer.setChecked(page.id, value: true)
        let latest = try XCTUnwrap(newer.reviewed())
        try RecipePhotoImportCheckpointStore.finish(userID: auth.currentUserID!, provenance: latest.1, store: store)
        XCTAssertTrue(RecipePhotoImportModel(userID: auth.currentUserID, store: store).checkpoint.draft.pages.isEmpty)
    }

    func testStaleCaptureEditorAndAccountSwitchCannotOverwriteSavedPages() async throws {
        let previousAuth = DIContainer.shared.authService
        let auth = MockAuthService(); auth.currentUserID = "recipe-photo-editor-one"
        DIContainer.shared.authService = auth
        defer { DIContainer.shared.authService = previousAuth }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EditorDraftStore(directory: directory)
        let first = RecipePhotoImportModel(userID: auth.currentUserID, store: store)
        await first.recognize([try printedPage(recipeText)])
        let stale = RecipePhotoImportModel(userID: auth.currentUserID, store: store)
        let page = try XCTUnwrap(first.checkpoint.draft.pages.first)
        first.editText(pageID: page.id, text: page.reviewedText + "\nFirst editor correction.")
        XCTAssertTrue(first.flush())
        stale.editText(pageID: page.id, text: "Stale replacement")
        XCTAssertFalse(stale.flush())
        let readback = RecipePhotoImportModel(userID: auth.currentUserID, store: store)
        XCTAssertTrue(readback.checkpoint.draft.combinedText.contains("First editor correction."))
        auth.currentUserID = "recipe-photo-editor-two"
        XCTAssertFalse(first.flush())
        XCTAssertFalse(first.canReview)
        XCTAssertTrue(RecipePhotoImportModel(userID: auth.currentUserID, store: store).checkpoint.draft.pages.isEmpty)
    }
}
