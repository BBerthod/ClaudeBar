import XCTest
@testable import ClaudeBarLib

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
        let svc = OmlxMonitorService(endpoint: "http://127.0.0.1:8000", skipInitialCheck: true)
        XCTAssertEqual(svc.endpoint, "http://127.0.0.1:8000")
    }
}
