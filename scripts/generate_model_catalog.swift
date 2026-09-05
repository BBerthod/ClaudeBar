#!/usr/bin/env swift
import Foundation

// MIRROR OF Sources/ClaudeBar/Models — keep in sync

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
}


enum ModelCatalogImporter {
    static let targetProviders: Set<String> = ["anthropic", "openai", "gemini"]
    static let targetIdMarkers = ["claude", "gpt", "codex", "gemini"]

    static func normalise(litellm: [String: Any], generatedAt: Date) throws -> ModelCatalog {
        var entries: [String: ModelCatalogEntry] = [:]
        // Canonical ids precede longer cloud aliases; lexical order breaks ties deterministically.
        let ids = litellm.keys.sorted { $0.count == $1.count ? $0 < $1 : $0.count < $1.count }
        for rawId in ids {
            guard rawId != "sample_spec", let dict = litellm[rawId] as? [String: Any] else { continue }
            let provider = (dict["litellm_provider"] as? String ?? "").lowercased()
            let id = ModelIdNormalizer.normalize(rawId)
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
                                            inputPerMTok: input * 1_000_000, outputPerMTok: output * 1_000_000,
                                            cacheReadPerMTok: read * 1_000_000, cacheWritePerMTok: write * 1_000_000,
                                            contextWindow: context)
        }
        return ModelCatalog(generatedAt: generatedAt, entries: entries)
    }
}
// END MIRROR

// The semaphore publishes the callback result before the waiting thread reads it.
private final class DownloadResult: @unchecked Sendable {
    var value: Result<Data, Error>?
}

private enum GeneratorError: Error {
    case usage
    case httpStatus(Int)
    case invalidResponse
    case invalidJSON
    case emptyCatalog
}

private func download() throws -> Data {
    let url = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!
    var request = URLRequest(url: url)
    request.timeoutInterval = 60
    let semaphore = DispatchSemaphore(value: 0)
    let result = DownloadResult()
    URLSession.shared.dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }
        if let error = error {
            result.value = .failure(error)
        } else if let response = response as? HTTPURLResponse {
            if (200..<300).contains(response.statusCode), let data = data {
                result.value = .success(data)
            } else {
                result.value = .failure(GeneratorError.httpStatus(response.statusCode))
            }
        } else {
            result.value = .failure(GeneratorError.invalidResponse)
        }
    }.resume()
    semaphore.wait()
    guard let value = result.value else { throw GeneratorError.invalidResponse }
    return try value.get()
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let data: Data
    if arguments.isEmpty {
        data = try download()
    } else if arguments.count == 2, arguments[0] == "--input" {
        data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
    } else {
        throw GeneratorError.usage
    }
    guard let litellm = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw GeneratorError.invalidJSON
    }
    let catalog = try ModelCatalogImporter.normalise(litellm: litellm, generatedAt: Date())
    guard !catalog.entries.isEmpty else { throw GeneratorError.emptyCatalog }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let json = String(decoding: try encoder.encode(catalog), as: UTF8.self)
    let generatedAt = ISO8601DateFormatter().string(from: catalog.generatedAt)
    let indentedJSON = json.split(separator: "\n", omittingEmptySubsequences: false)
        .map { "    " + $0 }.joined(separator: "\n")
    let source = "// Generated by `make catalog` on \(generatedAt) — do not edit by hand.\n"
        + "enum ModelCatalogSnapshot {\n"
        + "    static let generatedAt = \"\(generatedAt)\"\n"
        + "    static let json = #\"\"\"\n"
        + indentedJSON + "\n    \"\"\"#\n}\n"
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let destination = root.appendingPathComponent("Sources/ClaudeBar/Models/ModelCatalogSnapshot.swift")
    try source.write(to: destination, atomically: true, encoding: .utf8)
    print("Generated \(catalog.entries.count) models at \(generatedAt): \(destination.path)")
} catch {
    FileHandle.standardError.write(Data("Catalog generation failed: \(error). Usage: swift scripts/generate_model_catalog.swift [--input <path>]\n".utf8))
    exit(1)
}
