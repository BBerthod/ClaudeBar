import XCTest
@testable import ClaudeBarLib

final class OmlxHealthResponseTests: XCTestCase {

    private let fullJSON = """
    {
      "status": "healthy",
      "default_model": "Qwen3.6-27B",
      "engine_pool": {
        "model_count": 2,
        "loaded_count": 0,
        "max_model_memory": 115964116992,
        "current_model_memory": 0
      },
      "mcp": null
    }
    """.data(using: .utf8)!

    func testDecodesStatus() throws {
        let r = try JSONDecoder().decode(OmlxHealthResponse.self, from: fullJSON)
        XCTAssertEqual(r.status, "healthy")
    }

    func testIsHealthyTrueWhenStatusHealthy() throws {
        let r = try JSONDecoder().decode(OmlxHealthResponse.self, from: fullJSON)
        XCTAssertTrue(r.isHealthy)
    }

    func testIsHealthyFalseWhenStatusNotHealthy() throws {
        let json = #"{"status":"degraded","default_model":null,"engine_pool":null,"mcp":null}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(OmlxHealthResponse.self, from: json)
        XCTAssertFalse(r.isHealthy)
    }

    func testDecodesDefaultModel() throws {
        let r = try JSONDecoder().decode(OmlxHealthResponse.self, from: fullJSON)
        XCTAssertEqual(r.defaultModel, "Qwen3.6-27B")
    }

    func testDecodesEnginePool() throws {
        let r = try JSONDecoder().decode(OmlxHealthResponse.self, from: fullJSON)
        XCTAssertEqual(r.enginePool?.modelCount, 2)
        XCTAssertEqual(r.enginePool?.loadedCount, 0)
        XCTAssertEqual(r.enginePool?.maxModelMemory, 115964116992)
        XCTAssertEqual(r.enginePool?.currentModelMemory, 0)
    }

    func testMaxMemoryGB() throws {
        let r = try JSONDecoder().decode(OmlxHealthResponse.self, from: fullJSON)
        XCTAssertEqual(r.maxMemoryGB, 115964116992.0 / 1073741824.0, accuracy: 0.01)
    }

    func testUsedMemoryGBWhenZero() throws {
        let r = try JSONDecoder().decode(OmlxHealthResponse.self, from: fullJSON)
        XCTAssertEqual(r.usedMemoryGB, 0.0, accuracy: 0.01)
    }

    func testMinimalJSONWithoutEnginePool() throws {
        let json = #"{"status":"healthy","default_model":null,"engine_pool":null,"mcp":null}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(OmlxHealthResponse.self, from: json)
        XCTAssertTrue(r.isHealthy)
        XCTAssertNil(r.enginePool)
        XCTAssertEqual(r.maxMemoryGB, 0.0, accuracy: 0.01)
    }

    func testDecodesWhenEnginePoolKeyAbsent() throws {
        let json = #"{"status":"healthy"}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(OmlxHealthResponse.self, from: json)
        XCTAssertNil(r.enginePool)
        XCTAssertNil(r.defaultModel)
    }

    func testThrowsOnMalformedJSON() {
        let bad = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(OmlxHealthResponse.self, from: bad))
    }
}
