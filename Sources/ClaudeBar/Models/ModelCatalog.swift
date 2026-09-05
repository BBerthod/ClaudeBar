import Foundation

struct ModelCatalogEntry: Codable, Sendable, Equatable {
    let id: String
    let provider: String
    let family: String
    let inputPerMTok: Double
    let outputPerMTok: Double
    let cacheReadPerMTok: Double
    let cacheWritePerMTok: Double
    let contextWindow: Int
}

/// Canonicalises vendor/cloud-prefixed and date-suffixed model ids.
enum ModelIdNormalizer {
    private static let prefixes = ["anthropic/", "anthropic.", "openai/", "openai.", "azure/", "vertex_ai/",
                                   "gemini/", "bedrock/", "bedrock_mantle/", "global.", "us.", "eu.", "au.", "jp."]
    static let families = ["fable", "mythos", "opus", "sonnet", "haiku", "gpt", "codex", "gemini"]

    static func normalize(_ raw: String) -> String {
        var id = raw.lowercased()
        var changed = true
        while changed {                       // "azure/eu/gpt-…", "bedrock_mantle/openai.gpt-…"
            changed = false
            for p in prefixes where id.hasPrefix(p) { id.removeFirst(p.count); changed = true }
            if let slash = id.firstIndex(of: "/") { id = String(id[id.index(after: slash)...]); changed = true }
        }
        if let at = id.firstIndex(of: "@") { id = String(id[..<at]) }                 // claude-opus-4-5@20251101
        if let r = id.range(of: #"-\d{8}$"#, options: .regularExpression) { id = String(id[..<r.lowerBound]) }
        return id
    }

    static func family(of raw: String) -> String? {
        let id = normalize(raw)
        return families.first { id.contains($0) }   // "fable" before "opus": order matters for "claude-fable-…"
    }

    /// First numeric run after the family name, "4-8" / "4.8" / "5" → 4.8 / 4.8 / 5.0. Segments after the minor are ignored.
    static func version(of raw: String) -> Double? {
        let id = normalize(raw)
        let parts = id.split(whereSeparator: { $0 == "-" || $0 == "." || $0 == "_" }).map(String.init)
        guard let familyIdx = parts.firstIndex(where: { families.contains($0) }) else { return nil }
        // Version digits may sit before ("claude-3-7-sonnet") or after ("claude-opus-4-8") the family token.
        let after = parts[(familyIdx + 1)...].prefix { $0.allSatisfy(\.isNumber) }
        let before = parts[..<familyIdx].reversed().prefix { $0.allSatisfy(\.isNumber) }.reversed()
        let digits = after.isEmpty ? Array(before) : Array(after)
        guard let major = digits.first.flatMap(Double.init) else { return nil }
        let minor = digits.dropFirst().first.flatMap(Double.init) ?? 0
        return major + minor / 10
    }
}

struct ModelCatalog: Codable, Sendable {
    let generatedAt: Date
    let entries: [String: ModelCatalogEntry]

    struct Resolution: Sendable {
        let entry: ModelCatalogEntry
        let isEstimated: Bool
        let basedOn: String?
    }

    func resolve(_ modelId: String) -> Resolution? {
        if let e = entries[modelId] { return Resolution(entry: e, isEstimated: false, basedOn: nil) }
        let normalized = ModelIdNormalizer.normalize(modelId)
        if let e = entries[normalized] { return Resolution(entry: e, isEstimated: false, basedOn: nil) }
        guard let family = ModelIdNormalizer.family(of: normalized) else { return nil }
        let provider = family == "gpt" || family == "codex" ? "openai" : family == "gemini" ? "gemini" : "anthropic"
        let candidates = entries.values.filter { $0.family == family && $0.provider == provider }
        guard let best = candidates.max(by: { a, b in
            let va = ModelIdNormalizer.version(of: a.id) ?? 0, vb = ModelIdNormalizer.version(of: b.id) ?? 0
            return va == vb ? a.id < b.id : va < vb
        }) else { return nil }
        return Resolution(entry: best, isEstimated: true, basedOn: best.id)
    }
}
