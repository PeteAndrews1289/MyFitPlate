import XCTest
import MyFitPlateCore
@testable import MyFitPlate

@MainActor
final class MaiaStreamingTransportTests: XCTestCase {
    func testCancellingRequestClosesURLSessionConnectionAndRejectsPartialResponse() async throws {
        let previous = DIContainer.shared.authService
        let owner = "maia-stream-\(UUID().uuidString)"
        let auth = MockAuthService(); auth.currentUserID = owner
        DIContainer.shared.authService = auth
        AIDataConsentStore.shared.grant(for: owner, includesHealthData: false)
        defer {
            DIContainer.shared.authService = previous
            AIDataConsentStore.shared.revoke(for: owner)
            StreamingURLProtocol.reset()
        }
        let receipt = try XCTUnwrap(AIDataConsentStore.shared.consent(for: owner))
        let requestID = UUID()
        let started = expectation(description: "Connection has streamed partial text")
        let stopped = expectation(description: "Network connection closed on cancellation")
        StreamingURLProtocol.configure(started: started, stopped: stopped, requestID: requestID)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamingURLProtocol.self]
        let request = URLRequest(url: URL(string: "https://maia-transport.test/stream")!)
        let task = Task { @MainActor in
            try await MaiaStreamingTransport().execute(request, requestID: requestID, ownerID: owner,
                consent: receipt, configuration: configuration) { _ in }
        }
        await fulfillment(of: [started], timeout: 3)
        task.cancel()
        do { _ = try await task.value; XCTFail("A cancelled partial stream cannot become a final answer") } catch { }
        await fulfillment(of: [stopped], timeout: 3)
    }
}

private class StreamingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var started: XCTestExpectation?
    private static var stopped: XCTestExpectation?
    private static var requestID: UUID?
    static func configure(started: XCTestExpectation, stopped: XCTestExpectation, requestID: UUID) {
        lock.lock(); defer { lock.unlock() }
        self.started = started; self.stopped = stopped; self.requestID = requestID
    }
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        started = nil; stopped = nil; requestID = nil
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "maia-transport.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let id = Self.requestID; let started = Self.started
        Self.lock.unlock()
        guard let id, let url = request.url else { return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("data:{\"message\":{\"requestID\":\"\(id)\",\"delta\":\"Partial\"}}\n\n".utf8))
        started?.fulfill()
        // Deliberately keep the stream open. The task must close it rather than simply ignore it.
    }
    override func stopLoading() {
        Self.lock.lock(); let stopped = Self.stopped; Self.stopped = nil; Self.lock.unlock()
        stopped?.fulfill()
    }
}
