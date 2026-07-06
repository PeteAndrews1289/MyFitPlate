import XCTest
@testable import MyFitPlateCore

final class AICameraServiceTests: XCTestCase {
    private var service: AICameraService!

    override func setUp() {
        super.setUp()
        service = AICameraService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    func testPrepareImageDataWithinLimit() {
        let data = Data(repeating: 0, count: 500)
        let prepared = service.prepareImageData(data, maxSizeBytes: 1000)
        XCTAssertNotNil(prepared)
        XCTAssertEqual(prepared?.count, 500)
    }

    func testPrepareImageDataExceedsLimit() {
        let data = Data(repeating: 0, count: 1500)
        let prepared = service.prepareImageData(data, maxSizeBytes: 1000)
        XCTAssertNotNil(prepared)
        XCTAssertEqual(prepared?.count, 1000)
    }

    func testPrepareImageDataEmpty() {
        let data = Data()
        let prepared = service.prepareImageData(data)
        XCTAssertNil(prepared)
    }

    func testCreateAttachment() {
        let data = Data(repeating: 1, count: 100)
        let attachment = service.createAttachment(from: data, source: .photoLibrary)
        XCTAssertNotNil(attachment)
        XCTAssertEqual(attachment?.source, .photoLibrary)
        XCTAssertEqual(attachment?.imageData?.count, 100)
        XCTAssertFalse(attachment!.id.isEmpty)
    }

    func testCreateAttachmentEmptyDataReturnsNil() {
        let attachment = service.createAttachment(from: Data(), source: .camera)
        XCTAssertNil(attachment)
    }
}
