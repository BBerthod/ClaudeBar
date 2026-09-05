import XCTest
@testable import ClaudeBarLib

private final class OmlxUsageURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.unknown) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class OmlxUsageServiceTests: XCTestCase {
    private final class Clock { var date = Date(timeIntervalSince1970: 1_788_609_600) }
    private struct Baseline: Codable { let date: String; let stats: OmlxStats }

    private func fixture() throws -> (OmlxUsageService, URL, Clock, URLSession) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OmlxUsageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let clock = Clock()
        let service = OmlxUsageService(omlxDirectory: directory, baselineDirectory: directory,
                                       session: session, now: { clock.date }, disablePolling: true)
        addTeardownBlock {
            session.invalidateAndCancel()
            try FileManager.default.removeItem(at: directory)
            await MainActor.run { OmlxUsageURLProtocol.handler = nil }
        }
        return (service, directory, clock, session)
    }

    private func stats(requests: Int = 10, prompt: Int = 1000, completion: Int = 500) -> OmlxStats {
        OmlxStats(totalPromptTokens: prompt, totalCompletionTokens: completion, totalCachedTokens: 100,
                  totalRequests: requests, totalPrefillDuration: 2, totalGenerationDuration: 50,
                  perModel: ["Qwen": OmlxModelUsage(promptTokens: prompt, completionTokens: completion,
                      cachedTokens: 100, requests: requests, prefillDuration: 2, generationDuration: 50)])
    }

    private func write(_ stats: OmlxStats, to directory: URL) throws {
        try JSONEncoder().encode(stats).write(to: directory.appendingPathComponent("stats.json"), options: .atomic)
    }

    private func baseline(_ directory: URL) throws -> Baseline {
        try JSONDecoder().decode(Baseline.self, from: Data(contentsOf: directory.appendingPathComponent("omlx-baseline.json")))
    }

    func testUnavailableWithoutStatsFile() throws {
        let (service, _, _, _) = try fixture()
        XCTAssertFalse(service.isAvailable)
        XCTAssertNil(service.today)
        XCTAssertNil(service.allTime)
        XCTAssertEqual(service.todayApiEquivalentCost, 0)
    }

    func testFirstSightCreatesBaselineAndZeroDelta() throws {
        let (service, directory, clock, _) = try fixture()
        try write(stats(), to: directory)
        service.reload()
        XCTAssertTrue(service.isAvailable)
        XCTAssertEqual(service.today?.totals.requests, 0)
        XCTAssertTrue(service.today?.perModel.isEmpty == true)
        XCTAssertEqual(service.allTime, stats())
        let saved = try baseline(directory)
        XCTAssertEqual(saved.stats, stats())
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        XCTAssertEqual(saved.date, formatter.string(from: clock.date))
    }

    func testDeltaAgainstPersistedBaseline() throws {
        let (service, directory, clock, session) = try fixture()
        try write(stats(), to: directory)
        service.reload()
        try write(stats(requests: 15, prompt: 1500, completion: 750), to: directory)
        let restarted = OmlxUsageService(omlxDirectory: directory, baselineDirectory: directory,
            session: session, now: { clock.date }, disablePolling: true)
        XCTAssertEqual(restarted.today?.totals.requests, 5)
        XCTAssertEqual(restarted.today?.totals.promptTokens, 500)
        XCTAssertEqual(try baseline(directory).stats, stats())
    }

    func testBaselineRollsOverAtMidnight() throws {
        let (service, directory, clock, _) = try fixture()
        clock.date = Calendar.current.startOfDay(for: clock.date).addingTimeInterval(-1)
        try write(stats(), to: directory)
        service.reload()
        let yesterday = try baseline(directory).date
        clock.date = clock.date.addingTimeInterval(2)
        try write(stats(requests: 15), to: directory)
        service.reload()
        XCTAssertEqual(service.today?.totals.requests, 0)
        XCTAssertNotEqual(try baseline(directory).date, yesterday)
        XCTAssertEqual(try baseline(directory).stats, stats(requests: 15))
    }

    func testResetReplacesBaseline() throws {
        let (service, directory, _, _) = try fixture()
        try write(stats(), to: directory)
        service.reload()
        let reset = stats(requests: 1, prompt: 5, completion: 5)
        try write(reset, to: directory)
        service.reload()
        XCTAssertEqual(service.today?.totals.requests, 1)
        XCTAssertEqual(service.today?.totals.promptTokens, 5)
        XCTAssertEqual(try baseline(directory).stats, reset)
        try write(stats(requests: 3, prompt: 15, completion: 15), to: directory)
        service.reload()
        XCTAssertEqual(service.today?.totals.requests, 2)
    }

    func testCorruptAndRemovedStatsClearPublishedUsage() throws {
        let (service, directory, _, _) = try fixture()
        try write(stats(), to: directory)
        service.reload()
        let file = directory.appendingPathComponent("stats.json")
        try Data("broken".utf8).write(to: file)
        service.reload()
        XCTAssertFalse(service.isAvailable)
        XCTAssertNil(service.today)
        XCTAssertNil(service.allTime)
        try FileManager.default.removeItem(at: file)
        service.reload()
        XCTAssertFalse(service.isAvailable)
    }

    func testCorruptBaselineIsReplacedWithCurrentUsage() throws {
        let (service, directory, _, _) = try fixture()
        try Data("broken".utf8).write(to: directory.appendingPathComponent("omlx-baseline.json"))
        try write(stats(), to: directory)
        service.reload()
        XCTAssertEqual(service.today?.totals.requests, 0)
        XCTAssertEqual(try baseline(directory).stats, stats())
    }

    func testBaselineSaveErrorSurvivesModelRefreshAndClearsAfterRecovery() async throws {
        let (_, directory, clock, session) = try fixture()
        let blockedDirectory = directory.appendingPathComponent("baseline")
        try Data("obstruction".utf8).write(to: blockedDirectory)
        try write(stats(), to: directory)
        let service = OmlxUsageService(omlxDirectory: directory, baselineDirectory: blockedDirectory,
            session: session, now: { clock.date }, disablePolling: true)
        let error = service.lastError
        XCTAssertNotNil(error)
        await service.refreshModels()
        XCTAssertEqual(service.lastError, error)
        try FileManager.default.removeItem(at: blockedDirectory)
        service.reload()
        XCTAssertNil(service.lastError)
        XCTAssertEqual(try baseline(blockedDirectory).stats, stats())
    }

    func testSuccessfulReloadPreservesModelStatusError() async throws {
        let (service, directory, _, _) = try fixture()
        try settings(directory)
        OmlxUsageURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        await service.refreshModels()
        try write(stats(), to: directory)
        service.reload()
        XCTAssertEqual(service.lastError, "HTTP 401")
    }

    func testWatcherFindsNewStatsAndRearmsAfterAtomicReplacement() async throws {
        let (service, directory, _, _) = try fixture()
        // Each observation completes before the next replacement, exercising each new inode.
        for requests in [10, 11, 12] {
            try write(stats(requests: requests), to: directory)
            let deadline = Date().addingTimeInterval(3)
            while service.allTime?.totalRequests != requests && Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(service.allTime?.totalRequests, requests)
            XCTAssertEqual(service.today?.totals.requests, requests - 10)
        }
    }

    private func settings(_ directory: URL, key: String = "test-secret", port: Int? = 8123) throws {
        var object: [String: Any] = ["api_key": key]
        if let port { object["port"] = port }
        try JSONSerialization.data(withJSONObject: object).write(to: directory.appendingPathComponent("settings.json"))
    }

    func testModelsStatusUsesKeyAndPort() async throws {
        let (service, directory, _, _) = try fixture()
        try settings(directory)
        OmlxUsageURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "127.0.0.1")
            XCTAssertEqual(request.url?.port, 8123)
            XCTAssertEqual(request.url?.path, "/v1/models/status")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-secret")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"models":[{"id":"Qwen","loaded":true}]}"#.utf8))
        }
        await service.refreshModels()
        XCTAssertEqual(service.loadedModels.first?.id, "Qwen")
        XCTAssertNil(service.lastError)
        try settings(directory, key: "rotated-secret", port: nil)
        OmlxUsageURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.port, 8000)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer rotated-secret")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("[]".utf8))
        }
        await service.refreshModels()
        XCTAssertTrue(service.loadedModels.isEmpty)
    }

    func testModelsStatus401ClearsListAndSetsError() async throws {
        let (service, directory, _, _) = try fixture()
        try settings(directory)
        for status in [200, 401, 200, 404] {
            OmlxUsageURLProtocol.handler = { request in
                (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
                 Data(#"[{"id":"Qwen","loaded":true}]"#.utf8))
            }
            await service.refreshModels()
            if status == 200 {
                XCTAssertEqual(service.loadedModels.count, 1)
                XCTAssertNil(service.lastError)
            } else {
                XCTAssertTrue(service.loadedModels.isEmpty)
                XCTAssertEqual(service.lastError, "HTTP \(status)")
            }
        }
    }

    func testMissingSettingsAndKeyUseHealthOnlyMode() async throws {
        let (service, directory, _, _) = try fixture()
        OmlxUsageURLProtocol.handler = { _ in
            XCTFail("Health-only mode must not request model status")
            throw URLError(.unknown)
        }
        await service.refreshModels()
        XCTAssertNil(service.lastError)
        try Data(#"{"port":8123}"#.utf8).write(to: directory.appendingPathComponent("settings.json"))
        await service.refreshModels()
        XCTAssertNil(service.lastError)
        XCTAssertTrue(service.loadedModels.isEmpty)
    }

    func testNetworkErrorsDoNotExposeKey() async throws {
        let (service, directory, _, _) = try fixture()
        try settings(directory)
        OmlxUsageURLProtocol.handler = { _ in
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "test-secret"])
        }
        await service.refreshModels()
        XCTAssertTrue(service.loadedModels.isEmpty)
        XCTAssertNotNil(service.lastError)
        XCTAssertFalse(service.lastError?.contains("test-secret") == true)
    }

    func testApiEquivalentCostUsesReferenceModel() throws {
        let (service, directory, _, _) = try fixture()
        let key = "claudebar.omlxReferenceModel"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(service.referenceModelId, "claude-sonnet-5")
        try write(stats(), to: directory)
        service.reload()
        try write(stats(requests: 11, prompt: 1_001_000, completion: 100_500), to: directory)
        service.reload()
        service.referenceModelId = "claude-sonnet-5"
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), "claude-sonnet-5")
        XCTAssertEqual(service.todayApiEquivalentCost, 3, accuracy: 1e-9)
        service.referenceModelId = "claude-opus-5"
        XCTAssertEqual(service.todayApiEquivalentCost, 7.5, accuracy: 1e-9)
    }
}
