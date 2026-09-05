import Foundation
import os

@Observable
@MainActor
final class UpdateCheckService {
    private(set) var latestVersion: String?
    private(set) var currentVersion: String
    private(set) var updateAvailable: Bool = false
    private(set) var releaseURL: String?
    /// Direct download URL for the release zip asset. Set only when a newer version is found
    /// and the release has a `.zip` asset attached.
    private(set) var assetDownloadURL: String?
    private(set) var retryAfter: Date?

    private let session: URLSession
    private var isChecking: Bool = false
    private var etag: String?

    init(
        currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
        session: URLSession = .shared
    ) {
        self.currentVersion = currentVersion
        self.session = session
        // Initial check is driven explicitly by AppDelegate.startUpdateCheckTimer()
    }

    func checkForUpdate() async {
        guard !isChecking else { return }
        if let retryAfter, Date() < retryAfter { return }

        isChecking = true
        defer { isChecking = false }

        guard let url = URL(string: "https://api.github.com/repos/BBerthod/ClaudeBar/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudeBar/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                resetReleaseState()
                return
            }

            if httpResponse.statusCode == 304 {
                return
            }

            resetReleaseState()

            if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
                retryAfter = backoffDate(from: httpResponse)
                return
            }

            guard httpResponse.statusCode == 200 else { return }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String else { return }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            // Only remember the ETag once the payload proved usable.
            etag = httpResponse.value(forHTTPHeaderField: "ETag")

            if isNewer(remote: remoteVersion, current: currentVersion) {
                latestVersion = remoteVersion
                releaseURL = htmlURL
                updateAvailable = true

                // Parse asset download URL (first .zip in assets array)
                if let assets = json["assets"] as? [[String: Any]],
                   let zipAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
                   let downloadURL = zipAsset["browser_download_url"] as? String {
                    assetDownloadURL = downloadURL
                }

                Log.stats.info("Update available: \(remoteVersion) (current: \(self.currentVersion))")
            } else {
                Log.stats.debug("ClaudeBar is up to date (\(self.currentVersion))")
            }
        } catch {
            resetReleaseState()
            Log.stats.debug("Update check failed silently: \(error.localizedDescription)")
        }
    }

    private func resetReleaseState() {
        // Drop the ETag too: a later 304 must not freeze a cleared state.
        etag = nil
        latestVersion = nil
        updateAvailable = false
        releaseURL = nil
        assetDownloadURL = nil
    }

    private func backoffDate(from response: HTTPURLResponse) -> Date? {
        if let value = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = TimeInterval(value), seconds >= 0 {
            return Date().addingTimeInterval(seconds)
        }

        if let value = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let epoch = TimeInterval(value) {
            return Date(timeIntervalSince1970: epoch)
        }

        return nil
    }

    // MARK: - Semantic Version Comparison

    /// Returns true if `remote` is strictly newer than `current`.
    func isNewer(remote: String, current: String) -> Bool {
        guard let remoteParts = versionParts(remote),
              let currentParts = versionParts(current) else { return false }

        let maxLength = max(remoteParts.count, currentParts.count)
        for i in 0..<maxLength {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }

    private func versionParts(_ version: String) -> [Int]? {
        let release = version.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let segments = release.split(separator: ".", omittingEmptySubsequences: false)

        guard !segments.isEmpty else { return nil }

        var parts: [Int] = []
        for segment in segments {
            guard !segment.isEmpty,
                  segment.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(segment) else { return nil }
            parts.append(value)
        }
        return parts
    }
}
