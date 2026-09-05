import XCTest
@testable import ClaudeBarLib

final class OmlxStatsTests: XCTestCase {
    private let sample = """
    {
      "total_prompt_tokens": 1000, "total_completion_tokens": 500,
      "total_cached_tokens": 100, "total_requests": 10,
      "total_prefill_duration": 2, "total_generation_duration": 50,
      "per_model": {
        "Qwen3.6-27B": {"prompt_tokens":800,"completion_tokens":400,"cached_tokens":100,"requests":8,"prefill_duration":1.5,"generation_duration":40},
        "Qwen3-Next-80B": {"prompt_tokens":200,"completion_tokens":100,"cached_tokens":0,"requests":2,"prefill_duration":0.5,"generation_duration":10}
      }
    }
    """

    func testDecodesActualStatsKeysAndRoundTrips() throws {
        let stats = try OmlxStats.decode(Data(sample.utf8))
        XCTAssertEqual(stats.totalPromptTokens, 1000)
        XCTAssertEqual(stats.totalCompletionTokens, 500)
        XCTAssertEqual(stats.totalCachedTokens, 100)
        XCTAssertEqual(stats.totalRequests, 10)
        XCTAssertEqual(stats.totalPrefillDuration, 2)
        XCTAssertEqual(stats.totalGenerationDuration, 50)
        XCTAssertEqual(stats.perModel["Qwen3.6-27B"], usage(800, 400, 100, 8, 1.5, 40))
        XCTAssertEqual(stats.perModel["Qwen3-Next-80B"], usage(200, 100, 0, 2, 0.5, 10))
        XCTAssertEqual(try OmlxStats.decode(JSONEncoder().encode(stats)), stats)
    }

    func testMalformedStatsThrows() {
        XCTAssertThrowsError(try OmlxStats.decode(Data("not json".utf8)))
        XCTAssertThrowsError(try OmlxStats.decode(Data("{}".utf8)))
    }

    func testSnapshotsCanBeUpdatedIndependently() throws {
        let baseline = try OmlxStats.decode(Data(sample.utf8))
        var current = baseline
        current.perModel["Qwen3.6-27B"]?.promptTokens = 1300
        current.perModel["Qwen3.6-27B"]?.completionTokens = 650
        current.totalPromptTokens = 1500
        XCTAssertEqual(baseline.perModel["Qwen3.6-27B"]?.promptTokens, 800)
        XCTAssertEqual(baseline.totalPromptTokens, 1000)
        let delta = OmlxDailyUsage.delta(current: current, baseline: baseline)
        XCTAssertEqual(delta.totals.promptTokens, 500)
        XCTAssertEqual(delta.totals.completionTokens, 250)
    }

    func testGenerationSpeedHandlesZeroDuration() {
        XCTAssertEqual(usage(0, 400, 0, 0, 0, 40).generationTokensPerSecond, 10)
        XCTAssertEqual(usage(0, 400, 0, 0, 0, 0).generationTokensPerSecond, 0)
    }

    func testDeltaIncludesNewModelsAndOmitsUnchangedModels() throws {
        let baseline = try OmlxStats.decode(Data(sample.utf8))
        var models = baseline.perModel
        models["Qwen3.6-27B"] = usage(1300, 650, 150, 13, 2, 65)
        models["NewModel"] = usage(10, 20, 0, 1, 0.1, 2)
        let delta = OmlxDailyUsage.delta(current: stats(models), baseline: baseline)
        XCTAssertFalse(delta.resetDetected)
        XCTAssertEqual(delta.perModel.map(\.model), ["Qwen3.6-27B", "NewModel"])
        let qwen = try XCTUnwrap(delta.perModel.first)
        XCTAssertEqual(qwen.id, qwen.model)
        XCTAssertEqual(qwen.usage, usage(500, 250, 50, 5, 0.5, 25))
        XCTAssertEqual(qwen.promptTokens, 500)
        XCTAssertEqual(qwen.completionTokens, 250)
        XCTAssertEqual(qwen.cachedTokens, 50)
        XCTAssertEqual(qwen.requests, 5)
        XCTAssertEqual(qwen.generationTokensPerSecond, 10)
        XCTAssertEqual(delta.totals, usage(510, 270, 50, 6, 0.6, 27))
    }

    func testResetCountsCurrentModelFromZero() throws {
        let baseline = try OmlxStats.decode(Data(sample.utf8))
        var models = baseline.perModel
        models["Qwen3.6-27B"] = usage(5, 5, 0, 1, 0, 1)
        let delta = OmlxDailyUsage.delta(current: stats(models), baseline: baseline)
        XCTAssertTrue(delta.resetDetected)
        XCTAssertEqual(delta.totals, usage(5, 5, 0, 1, 0, 1))
    }

    func testEveryCounterCanDetectAModelReset() {
        let baselineUsage = usage(10, 10, 10, 10, 10, 10)
        let decreases = [usage(9, 11, 11, 11, 11, 11), usage(11, 9, 11, 11, 11, 11),
                         usage(11, 11, 9, 11, 11, 11), usage(11, 11, 11, 9, 11, 11),
                         usage(11, 11, 11, 11, 9, 11), usage(11, 11, 11, 11, 11, 9)]
        for currentUsage in decreases {
            let delta = OmlxDailyUsage.delta(current: stats(["M": currentUsage]),
                                            baseline: stats(["M": baselineUsage]))
            XCTAssertTrue(delta.resetDetected)
            XCTAssertEqual(delta.totals, currentUsage)
        }
    }

    func testRemovedModelAndGlobalDecreaseFlagResetWithoutNegativeUsage() {
        let original = usage(10, 10, 10, 10, 10, 10)
        let removed = OmlxDailyUsage.delta(current: stats([:]), baseline: stats(["M": original]))
        XCTAssertTrue(removed.resetDetected)
        XCTAssertEqual(removed.totals, usage())
        XCTAssertTrue(removed.perModel.isEmpty)
        let baseline = OmlxStats(totalPromptTokens: 100, totalCompletionTokens: 100,
                                 totalCachedTokens: 100, totalRequests: 100,
                                 totalPrefillDuration: 100, totalGenerationDuration: 100,
                                 perModel: ["M": original])
        let delta = OmlxDailyUsage.delta(current: stats(["M": original]), baseline: baseline)
        XCTAssertTrue(delta.resetDetected)
        XCTAssertEqual(delta.totals, usage())
    }

    func testEmptyAndUnchangedSnapshotsHaveNoUsage() {
        for snapshot in [stats([:]), stats(["M": usage(1, 2, 0, 1, 0, 1)])] {
            let delta = OmlxDailyUsage.delta(current: snapshot, baseline: snapshot)
            XCTAssertFalse(delta.resetDetected)
            XCTAssertEqual(delta.totals, usage())
            XCTAssertTrue(delta.perModel.isEmpty)
        }
    }

    func testNegativeResetValuesAreClamped() {
        let delta = OmlxDailyUsage.delta(current: stats(["M": usage(-1, -1, -1, -1, -1, -1)]),
                                        baseline: stats(["M": usage(1, 1, 1, 1, 1, 1)]))
        XCTAssertTrue(delta.resetDetected)
        XCTAssertEqual(delta.totals, usage())
    }

    func testEquivalentCostUsesInputAndOutputWithoutCacheAdjustment() {
        let pricing = CostCalculator.ModelPricing(inputPerMTok: 2, outputPerMTok: 10,
                                                  cacheReadPerMTok: 0.2, cacheWritePerMTok: 2.5)
        XCTAssertEqual(OmlxDailyUsage.apiEquivalentCost(of: usage(1_000_000, 100_000, 500_000),
                                                      reference: pricing), 3, accuracy: 0.000001)
    }

    private func usage(_ prompt: Int = 0, _ completion: Int = 0, _ cached: Int = 0,
                       _ requests: Int = 0, _ prefill: Double = 0, _ generation: Double = 0) -> OmlxModelUsage {
        OmlxModelUsage(promptTokens: prompt, completionTokens: completion, cachedTokens: cached,
                       requests: requests, prefillDuration: prefill, generationDuration: generation)
    }

    private func stats(_ models: [String: OmlxModelUsage]) -> OmlxStats {
        OmlxStats(totalPromptTokens: models.values.reduce(0) { $0 + $1.promptTokens },
                  totalCompletionTokens: models.values.reduce(0) { $0 + $1.completionTokens },
                  totalCachedTokens: models.values.reduce(0) { $0 + $1.cachedTokens },
                  totalRequests: models.values.reduce(0) { $0 + $1.requests },
                  totalPrefillDuration: models.values.reduce(0) { $0 + $1.prefillDuration },
                  totalGenerationDuration: models.values.reduce(0) { $0 + $1.generationDuration },
                  perModel: models)
    }
}

final class OmlxModelStatusTests: XCTestCase {
    func testModelsEnvelope() throws {
        let models = try OmlxModelStatus.decodeList(Data(#"{"models":[{"id":"Qwen3.6-27B","loaded":true,"is_loading":false,"last_access":1757100000.5,"estimated_size":16000000000}]}"#.utf8))
        let model = try XCTUnwrap(models.first)
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(model.id, "Qwen3.6-27B")
        XCTAssertTrue(model.isLoaded)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.lastAccess?.timeIntervalSince1970, 1757100000.5)
        XCTAssertEqual(try XCTUnwrap(model.sizeGB), 16, accuracy: 1e-9)
    }

    func testBareArrayMissingOptionalFields() throws {
        let model = try XCTUnwrap(OmlxModelStatus.decodeList(Data(#"[{"id":"x"}]"#.utf8)).first)
        XCTAssertFalse(model.isLoaded)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.lastAccess)
        XCTAssertNil(model.sizeBytes)
    }

    func testDataEnvelopeAndAliases() throws {
        let models = try OmlxModelStatus.decodeList(Data(#"{"data":[{"id":"y","status":"loaded"},{"id":"z","is_loaded":true,"is_loading":true,"last_access":1757100000500,"size_bytes":2000000000}]}"#.utf8))
        XCTAssertTrue(models[0].isLoaded)
        XCTAssertTrue(models[1].isLoaded)
        XCTAssertTrue(models[1].isLoading)
        XCTAssertEqual(models[1].lastAccess?.timeIntervalSince1970, 1757100000.5)
        XCTAssertEqual(models[1].sizeGB, 2)
    }

    func testMalformedItemsAreSkippedAndOptionalTypesAreTolerated() throws {
        let models = try OmlxModelStatus.decodeList(Data(#"[null,42,{}, {"id":""}, {"id":"ok","loaded":"invalid","last_access":"invalid","estimated_size":-1}]"#.utf8))
        XCTAssertEqual(models.map(\.id), ["ok"])
        XCTAssertFalse(models[0].isLoaded)
        XCTAssertNil(models[0].lastAccess)
        XCTAssertNil(models[0].sizeGB)
    }

    func testInvalidJSONAndUnsupportedEnvelopeThrow() {
        for text in ["broken", "{}", #"{"models":"invalid"}"#] {
            XCTAssertThrowsError(try OmlxModelStatus.decodeList(Data(text.utf8)))
        }
    }
}
