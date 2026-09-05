import XCTest
@testable import ClaudeBarLib

// MARK: - URLProtocol mock

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

private func makeResponse(status: Int = 200, headers: [String: String]? = nil) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.github.com")!,
        statusCode: status, httpVersion: nil, headerFields: headers
    )!
}

// MARK: - Tests

@MainActor
final class UpdateCheckServiceNetworkTests: XCTestCase {

    /// Release with a zip asset → assetDownloadURL is set, updateAvailable is true
    func testAssetDownloadURLParsedWhenReleaseHasZipAsset() async throws {
        let responseData = """
        {
          "tag_name": "v1.1.0",
          "html_url": "https://github.com/BBerthod/ClaudeBar/releases/tag/v1.1.0",
          "assets": [
            {
              "name": "ClaudeBar.zip",
              "browser_download_url": "https://github.com/BBerthod/ClaudeBar/releases/download/v1.1.0/ClaudeBar.zip"
            }
          ]
        }
        """.data(using: .utf8)!
        MockURLProtocol.requestHandler = { _ in (makeResponse(), responseData) }

        let service = UpdateCheckService(currentVersion: "1.0.0", session: makeMockSession())
        await service.checkForUpdate()

        XCTAssertEqual(
            service.assetDownloadURL,
            "https://github.com/BBerthod/ClaudeBar/releases/download/v1.1.0/ClaudeBar.zip"
        )
        XCTAssertTrue(service.updateAvailable)
        XCTAssertEqual(service.latestVersion, "1.1.0")
    }

    /// Release with no assets → assetDownloadURL is nil, but updateAvailable may be true
    func testAssetDownloadURLNilWhenNoAssets() async throws {
        let responseData = """
        {
          "tag_name": "v1.1.0",
          "html_url": "https://github.com/BBerthod/ClaudeBar/releases/tag/v1.1.0",
          "assets": []
        }
        """.data(using: .utf8)!
        MockURLProtocol.requestHandler = { _ in (makeResponse(), responseData) }

        let service = UpdateCheckService(currentVersion: "1.0.0", session: makeMockSession())
        await service.checkForUpdate()

        XCTAssertNil(service.assetDownloadURL)
        XCTAssertTrue(service.updateAvailable)
    }

    /// Same version → updateAvailable false, assetDownloadURL nil
    func testNoUpdateWhenVersionIsCurrent() async throws {
        let responseData = """
        {
          "tag_name": "v1.0.0",
          "html_url": "https://github.com/BBerthod/ClaudeBar/releases/tag/v1.0.0",
          "assets": [
            {
              "name": "ClaudeBar.zip",
              "browser_download_url": "https://github.com/.../ClaudeBar.zip"
            }
          ]
        }
        """.data(using: .utf8)!
        MockURLProtocol.requestHandler = { _ in (makeResponse(), responseData) }

        let service = UpdateCheckService(currentVersion: "1.0.0", session: makeMockSession())
        await service.checkForUpdate()

        XCTAssertNil(service.assetDownloadURL)
        XCTAssertFalse(service.updateAvailable)
    }

    /// Only first .zip asset URL is used when multiple assets present
    func testFirstZipAssetIsUsedWhenMultipleAssets() async throws {
        let responseData = """
        {
          "tag_name": "v2.0.0",
          "html_url": "https://github.com/BBerthod/ClaudeBar/releases/tag/v2.0.0",
          "assets": [
            {
              "name": "README.txt",
              "browser_download_url": "https://github.com/.../README.txt"
            },
            {
              "name": "ClaudeBar.zip",
              "browser_download_url": "https://github.com/.../ClaudeBar.zip"
            }
          ]
        }
        """.data(using: .utf8)!
        MockURLProtocol.requestHandler = { _ in (makeResponse(), responseData) }

        let service = UpdateCheckService(currentVersion: "1.0.0", session: makeMockSession())
        await service.checkForUpdate()

        XCTAssertEqual(service.assetDownloadURL, "https://github.com/.../ClaudeBar.zip")
    }

    func testReleaseWithoutAssetClearsPreviousAssetState() async throws {
        let releaseWithAsset = """
        {
          "tag_name": "v1.1.0",
          "html_url": "https://github.com/BBerthod/ClaudeBar/releases/tag/v1.1.0",
          "assets": [{
            "name": "ClaudeBar.zip",
            "browser_download_url": "https://github.com/.../ClaudeBar-1.1.0.zip"
          }]
        }
        """.data(using: .utf8)!
        let releaseWithoutAsset = """
        {
          "tag_name": "v1.2.0",
          "html_url": "https://github.com/BBerthod/ClaudeBar/releases/tag/v1.2.0",
          "assets": []
        }
        """.data(using: .utf8)!
        var requestCount = 0
        MockURLProtocol.requestHandler = { _ in
            requestCount += 1
            return (makeResponse(), requestCount == 1 ? releaseWithAsset : releaseWithoutAsset)
        }

        let service = UpdateCheckService(currentVersion: "1.0.0", session: makeMockSession())
        await service.checkForUpdate()
        XCTAssertNotNil(service.assetDownloadURL)

        await service.checkForUpdate()

        XCTAssertNil(service.assetDownloadURL)
        XCTAssertTrue(service.updateAvailable)
        XCTAssertEqual(service.latestVersion, "1.2.0")
    }

    func testNotModifiedPreservesStateAndSendsConditionalHeaders() async throws {
        let responseData = """
        {
          "tag_name": "v1.1.0",
          "html_url": "https://github.com/BBerthod/ClaudeBar/releases/tag/v1.1.0",
          "assets": [{
            "name": "ClaudeBar.zip",
            "browser_download_url": "https://github.com/.../ClaudeBar.zip"
          }]
        }
        """.data(using: .utf8)!
        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "ClaudeBar/1.0.0")
            if requestCount == 1 {
                XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"))
                return (makeResponse(headers: ["ETag": "\"release-etag\""]), responseData)
            }

            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"release-etag\"")
            return (makeResponse(status: 304), Data())
        }

        let service = UpdateCheckService(currentVersion: "1.0.0", session: makeMockSession())
        await service.checkForUpdate()
        await service.checkForUpdate()

        XCTAssertEqual(requestCount, 2)
        XCTAssertTrue(service.updateAvailable)
        XCTAssertEqual(service.latestVersion, "1.1.0")
        XCTAssertEqual(service.assetDownloadURL, "https://github.com/.../ClaudeBar.zip")
    }

    func testRetryAfterOn429SuspendsNextCheck() async throws {
        var requestCount = 0
        MockURLProtocol.requestHandler = { _ in
            requestCount += 1
            return (makeResponse(status: 429, headers: ["Retry-After": "3600"]), Data())
        }

        let service = UpdateCheckService(currentVersion: "1.0.0", session: makeMockSession())
        await service.checkForUpdate()
        let retryAfter = try XCTUnwrap(service.retryAfter)
        XCTAssertGreaterThan(retryAfter, Date())

        await service.checkForUpdate()

        XCTAssertEqual(requestCount, 1)
    }
}
