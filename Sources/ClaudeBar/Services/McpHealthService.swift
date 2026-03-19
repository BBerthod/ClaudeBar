import Foundation

/// Represents one configured MCP server and its health status.
struct McpServerInfo: Identifiable, Sendable {
    let name: String
    let type: String           // "stdio" or "http"
    let endpoint: String       // command or URL
    var status: McpStatus = .unknown

    var id: String { name }

    enum McpStatus: Sendable {
        case unknown
        case checking
        case healthy
        case unhealthy(String)

        var label: String {
            switch self {
            case .unknown:          return "Unknown"
            case .checking:         return "Checking…"
            case .healthy:          return "Healthy"
            case .unhealthy(let e): return e
            }
        }

        var isHealthy: Bool {
            if case .healthy = self { return true }
            return false
        }
    }
}

/// Reads MCP server config from ~/.claude.json and checks health.
@Observable
@MainActor
final class McpHealthService {
    private(set) var servers: [McpServerInfo] = []
    private(set) var isChecking = false

    private let claudeJsonPath: String

    init(claudeDir: String = "~") {
        self.claudeJsonPath = NSString(string: claudeDir).expandingTildeInPath + "/.claude.json"
        loadServers()
    }

    // MARK: - Load

    func loadServers() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: claudeJsonPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mcpServers = json["mcpServers"] as? [String: [String: Any]] else {
            servers = []
            return
        }

        servers = mcpServers.map { (name, config) in
            let type = config["type"] as? String ?? "unknown"
            let endpoint: String
            if type == "http" {
                endpoint = config["url"] as? String ?? "—"
            } else {
                let cmd = config["command"] as? String ?? ""
                let args = (config["args"] as? [String])?.prefix(2).joined(separator: " ") ?? ""
                endpoint = "\(cmd) \(args)".trimmingCharacters(in: .whitespaces)
            }
            return McpServerInfo(name: name, type: type, endpoint: endpoint)
        }.sorted { $0.name < $1.name }
    }

    // MARK: - Health Check

    func checkAll() {
        isChecking = true
        for i in servers.indices {
            servers[i].status = .checking
        }

        // Snapshot the server list before leaving the actor to avoid data races.
        let snapshot = servers

        Task {
            var results: [(index: Int, status: McpServerInfo.McpStatus)] = []

            for i in snapshot.indices {
                let server = snapshot[i]
                let status: McpServerInfo.McpStatus

                if server.type == "http" {
                    status = await checkHttp(url: server.endpoint)
                } else {
                    // Run blocking Process work off the main actor to avoid UI hangs.
                    let endpoint = server.endpoint
                    status = await Task.detached(priority: .utility) {
                        McpHealthService.checkStdioDetached(command: endpoint)
                    }.value
                }

                results.append((index: i, status: status))
            }

            await MainActor.run {
                for result in results {
                    if result.index < self.servers.count {
                        self.servers[result.index].status = result.status
                    }
                }
                self.isChecking = false
            }
        }
    }

    // MARK: - Private

    private func checkHttp(url: String) async -> McpServerInfo.McpStatus {
        guard let url = URL(string: url) else { return .unhealthy("Invalid URL") }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unhealthy("No HTTP response") }
            if (200..<400).contains(http.statusCode) {
                return .healthy
            }
            return .unhealthy("HTTP \(http.statusCode)")
        } catch {
            return .unhealthy(error.localizedDescription.prefix(40).description)
        }
    }

    /// Checks whether the stdio command binary exists.
    /// Declared `nonisolated` and `static` so it can be safely called from
    /// `Task.detached` without crossing the `@MainActor` boundary.
    private nonisolated static func checkStdioDetached(command: String) -> McpServerInfo.McpStatus {
        let parts = command.split(separator: " ", maxSplits: 1)
        guard let cmd = parts.first else { return .unhealthy("No command") }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [String(cmd)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? .healthy : .unhealthy("\(cmd) not found")
        } catch {
            return .unhealthy("Check failed")
        }
    }
}
