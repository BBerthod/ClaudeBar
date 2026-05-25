import XCTest
@testable import ClaudeBarLib

// MARK: - URLProtocol mock for testing

private class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

final class OmlxMonitorServiceTests: XCTestCase {

    func testStateSnapshotFromHealthyResponse() {
        let pool = OmlxHealthResponse.EnginePool(
            modelCount: 2, loadedCount: 1,
            maxModelMemory: 115964116992, currentModelMemory: 10737418240
        )
        let r = OmlxHealthResponse(status: "healthy", defaultModel: "Qwen3.6-27B", enginePool: pool)
        let state = OmlxMonitorService.StateSnapshot(from: r)
        XCTAssertTrue(state.isOnline)
        XCTAssertEqual(state.defaultModel, "Qwen3.6-27B")
        XCTAssertEqual(state.modelCount, 2)
        XCTAssertEqual(state.loadedCount, 1)
        XCTAssertEqual(state.maxMemoryGB, 115964116992.0 / 1_073_741_824, accuracy: 0.01)
        XCTAssertEqual(state.usedMemoryGB, 10737418240.0 / 1_073_741_824, accuracy: 0.01)
    }

    func testStateSnapshotFromDegradedResponse() {
        let r = OmlxHealthResponse(status: "degraded", defaultModel: nil, enginePool: nil)
        let state = OmlxMonitorService.StateSnapshot(from: r)
        XCTAssertFalse(state.isOnline)
        XCTAssertNil(state.defaultModel)
        XCTAssertEqual(state.modelCount, 0)
    }

    func testMemoryLabelZeroUsed() {
        let pool = OmlxHealthResponse.EnginePool(
            modelCount: 1, loadedCount: 0,
            maxModelMemory: 115964116992, currentModelMemory: 0
        )
        let r = OmlxHealthResponse(status: "healthy", defaultModel: "Qwen3", enginePool: pool)
        let state = OmlxMonitorService.StateSnapshot(from: r)
        XCTAssertEqual(state.memoryLabel, "0.0 / 108.0 GB")
    }

    func testMemoryLabelPartialUsed() {
        let pool = OmlxHealthResponse.EnginePool(
            modelCount: 1, loadedCount: 1,
            maxModelMemory: 34359738368, currentModelMemory: 17179869184
        )
        let r = OmlxHealthResponse(status: "healthy", defaultModel: "Llama", enginePool: pool)
        let state = OmlxMonitorService.StateSnapshot(from: r)
        XCTAssertEqual(state.memoryLabel, "16.0 / 32.0 GB")
    }

    func testDefaultSnapshotIsOffline() {
        let state = OmlxMonitorService.StateSnapshot()
        XCTAssertFalse(state.isOnline)
        XCTAssertNil(state.defaultModel)
        XCTAssertEqual(state.modelCount, 0)
        XCTAssertEqual(state.maxMemoryGB, 0.0, accuracy: 0.01)
    }

    @MainActor
    func testEndpointDefault() {
        let svc = OmlxMonitorService(disablePolling: true)
        XCTAssertEqual(svc.endpoint, "http://127.0.0.1:8000")
    }

    // MARK: - checkHealth() tests

    @MainActor
    func testCheckHealthSetsStateOnSuccess() async throws {
        let json = """
        {"status":"healthy","default_model":"Qwen3.6-27B","engine_pool":{"model_count":2,"loaded_count":0,"max_model_memory":115964116992,"current_model_memory":0},"mcp":null}
        """.data(using: .utf8)!
        MockURLProtocol.requestHandler = { _ in
            let resp = HTTPURLResponse(url: URL(string: "http://127.0.0.1:8000/health")!,
                                       statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, json)
        }
        let svc = OmlxMonitorService(disablePolling: true, session: makeMockSession())
        await svc.checkHealth()
        XCTAssertTrue(svc.isOnline)
        XCTAssertEqual(svc.defaultModel, "Qwen3.6-27B")
        XCTAssertNil(svc.lastError)
        XCTAssertNotNil(svc.lastChecked)
    }

    @MainActor
    func testCheckHealthSetsOfflineOn503() async throws {
        MockURLProtocol.requestHandler = { _ in
            let resp = HTTPURLResponse(url: URL(string: "http://127.0.0.1:8000/health")!,
                                       statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        let svc = OmlxMonitorService(disablePolling: true, session: makeMockSession())
        await svc.checkHealth()
        XCTAssertFalse(svc.isOnline)
        XCTAssertEqual(svc.lastError, "HTTP 503")
    }

    @MainActor
    func testCheckHealthSetsOfflineOnNetworkError() async throws {
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        let svc = OmlxMonitorService(disablePolling: true, session: makeMockSession())
        await svc.checkHealth()
        XCTAssertFalse(svc.isOnline)
        XCTAssertNotNil(svc.lastError)
    }
}
