import Foundation

struct ProviderInfo: Identifiable, Sendable {
    let name: String               // "Claude", "Gemini"
    let icon: String               // SF Symbol name
    let isConfigured: Bool
    var totalTokens: Int?
    var estimatedCost: Double?
    var details: String?           // e.g. "via gemini-delegate MCP"

    var id: String { name }
}
