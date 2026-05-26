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

private func makeResponse(status: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.github.com")!,
        statusCode: status, httpVersion: nil, headerFields: nil
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
}
