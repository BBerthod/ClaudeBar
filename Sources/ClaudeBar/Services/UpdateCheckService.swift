import Foundation
import os

@Observable
@MainActor
final class UpdateCheckService {
    private(set) var latestVersion: String?
    private(set) var currentVersion: String = "0.6.0"
    private(set) var updateAvailable: Bool = false
    private(set) var releaseURL: String?

    init() {
        Task { await checkForUpdate() }
    }

    func checkForUpdate() async {
        guard let url = URL(string: "https://api.github.com/repos/BBerthod/ClaudeBar/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String else { return }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            if isNewer(remote: remoteVersion, current: currentVersion) {
                latestVersion = remoteVersion
                releaseURL = htmlURL
                updateAvailable = true
                Log.stats.info("Update available: \(remoteVersion) (current: \(self.currentVersion))")
            } else {
                Log.stats.debug("ClaudeBar is up to date (\(self.currentVersion))")
            }
        } catch {
            // Silent failure — best-effort check
            Log.stats.debug("Update check failed silently: \(error.localizedDescription)")
        }
    }

    // MARK: - Semantic Version Comparison

    /// Returns true if `remote` is strictly newer than `current`.
    private func isNewer(remote: String, current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(remoteParts.count, currentParts.count)
        for i in 0..<maxLength {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }
}
