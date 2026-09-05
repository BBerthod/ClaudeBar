import Foundation

enum ModelCatalogImporter {
    static let targetProviders: Set<String> = ["anthropic", "openai", "gemini"]
    static let targetIdMarkers = ["claude", "gpt", "codex", "gemini"]

    /// Cloud deployment suffixes must not become numeric model generations.
    static func canonicalID(_ raw: String) -> String {
        var id = raw.lowercased()
        if let claude = id.range(of: "claude-") { id = String(id[claude.lowerBound...]) }
        id = id.replacingOccurrences(of: #"-v\d+(?::\d+)?$"#, with: "", options: .regularExpression)
        return ModelIdNormalizer.normalize(id)
    }

    /// Remove binary multiplication noise while retaining sub-cent precision.
    private static func perMillion(_ price: Double) -> Double {
        (price * 1_000_000 * 1_000_000_000).rounded() / 1_000_000_000
    }

    static func normalise(litellm: [String: Any], generatedAt: Date) throws -> ModelCatalog {
        var entries: [String: ModelCatalogEntry] = [:]
        // Canonical ids precede longer cloud aliases; lexical order breaks ties deterministically.
        let ids = litellm.keys.sorted { $0.count == $1.count ? $0 < $1 : $0.count < $1.count }
        for rawId in ids {
            guard rawId != "sample_spec", let dict = litellm[rawId] as? [String: Any] else { continue }
            let provider = (dict["litellm_provider"] as? String ?? "").lowercased()
            let id = canonicalID(rawId)
            let isReasoningModel = id.range(of: #"^o[1-9](?:-|$)"#, options: .regularExpression) != nil
            let isTarget = targetProviders.contains(provider) || provider.hasPrefix("vertex_ai")
                || targetIdMarkers.contains { rawId.lowercased().contains($0) } || isReasoningModel
            guard isTarget,
                  let input = dict["input_cost_per_token"] as? Double,
                  let output = dict["output_cost_per_token"] as? Double else { continue }
            if entries[id] != nil { continue }
            let family = ModelIdNormalizer.family(of: id) ?? (isReasoningModel ? "gpt" : provider)
            let canonicalProvider: String
            if family == "gpt" || family == "codex" {
                canonicalProvider = "openai"
            } else if family == "gemini" {
                canonicalProvider = "gemini"
            } else if id.contains("claude") {
                canonicalProvider = "anthropic"
            } else {
                canonicalProvider = provider
            }
            let read = (dict["cache_read_input_token_cost"] as? Double) ?? input * 0.10
            let write = (dict["cache_creation_input_token_cost"] as? Double) ?? input * 1.25
            let context = (dict["max_input_tokens"] as? Int) ?? (dict["max_tokens"] as? Int) ?? 200_000
            entries[id] = ModelCatalogEntry(id: id, provider: canonicalProvider, family: family,
                                            inputPerMTok: perMillion(input), outputPerMTok: perMillion(output),
                                            cacheReadPerMTok: perMillion(read), cacheWritePerMTok: perMillion(write),
                                            contextWindow: context)
        }
        return ModelCatalog(generatedAt: generatedAt, entries: entries)
    }
}
