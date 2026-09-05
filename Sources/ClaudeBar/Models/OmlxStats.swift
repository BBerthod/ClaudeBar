import Foundation

struct OmlxModelUsage: Codable, Sendable, Equatable {
    var promptTokens: Int
    var completionTokens: Int
    var cachedTokens: Int
    var requests: Int
    var prefillDuration: Double
    var generationDuration: Double

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case cachedTokens = "cached_tokens"
        case requests
        case prefillDuration = "prefill_duration"
        case generationDuration = "generation_duration"
    }

    var generationTokensPerSecond: Double {
        generationDuration > 0 ? Double(completionTokens) / generationDuration : 0
    }

    fileprivate static let zero = OmlxModelUsage(promptTokens: 0, completionTokens: 0,
                                               cachedTokens: 0, requests: 0,
                                               prefillDuration: 0, generationDuration: 0)

    fileprivate func hasDecreased(from baseline: Self) -> Bool {
        promptTokens < baseline.promptTokens || completionTokens < baseline.completionTokens
            || cachedTokens < baseline.cachedTokens || requests < baseline.requests
            || prefillDuration < baseline.prefillDuration || generationDuration < baseline.generationDuration
    }

    fileprivate func subtracting(_ baseline: Self) -> Self {
        Self(promptTokens: max(0, promptTokens - baseline.promptTokens),
             completionTokens: max(0, completionTokens - baseline.completionTokens),
             cachedTokens: max(0, cachedTokens - baseline.cachedTokens),
             requests: max(0, requests - baseline.requests),
             prefillDuration: max(0, prefillDuration - baseline.prefillDuration),
             generationDuration: max(0, generationDuration - baseline.generationDuration))
    }

    fileprivate func adding(_ other: Self) -> Self {
        Self(promptTokens: promptTokens + other.promptTokens,
             completionTokens: completionTokens + other.completionTokens,
             cachedTokens: cachedTokens + other.cachedTokens, requests: requests + other.requests,
             prefillDuration: prefillDuration + other.prefillDuration,
             generationDuration: generationDuration + other.generationDuration)
    }
}

struct OmlxStats: Codable, Sendable, Equatable {
    var totalPromptTokens: Int
    var totalCompletionTokens: Int
    var totalCachedTokens: Int
    var totalRequests: Int
    var totalPrefillDuration: Double
    var totalGenerationDuration: Double
    var perModel: [String: OmlxModelUsage]

    enum CodingKeys: String, CodingKey {
        case totalPromptTokens = "total_prompt_tokens"
        case totalCompletionTokens = "total_completion_tokens"
        case totalCachedTokens = "total_cached_tokens"
        case totalRequests = "total_requests"
        case totalPrefillDuration = "total_prefill_duration"
        case totalGenerationDuration = "total_generation_duration"
        case perModel = "per_model"
    }

    static func decode(_ data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }

    fileprivate var totals: OmlxModelUsage {
        OmlxModelUsage(promptTokens: totalPromptTokens, completionTokens: totalCompletionTokens,
                       cachedTokens: totalCachedTokens, requests: totalRequests,
                       prefillDuration: totalPrefillDuration, generationDuration: totalGenerationDuration)
    }
}

struct OmlxDailyUsage: Sendable {
    struct ModelDelta: Sendable, Identifiable {
        let model: String
        let usage: OmlxModelUsage

        var id: String { model }
        var promptTokens: Int { usage.promptTokens }
        var completionTokens: Int { usage.completionTokens }
        var cachedTokens: Int { usage.cachedTokens }
        var requests: Int { usage.requests }
        var generationTokensPerSecond: Double { usage.generationTokensPerSecond }
    }

    let perModel: [ModelDelta]
    let totals: OmlxModelUsage
    let resetDetected: Bool

    static func delta(current: OmlxStats, baseline: OmlxStats) -> Self {
        var resetDetected = current.totals.hasDecreased(from: baseline.totals)
            || baseline.perModel.keys.contains { current.perModel[$0] == nil }
        var models: [ModelDelta] = []
        for (model, usage) in current.perModel {
            let previous = baseline.perModel[model] ?? .zero
            let modelReset = usage.hasDecreased(from: previous)
            resetDetected = resetDetected || modelReset
            // A reset invalidates all counters for this model, not just the decreased one.
            let delta = usage.subtracting(modelReset ? .zero : previous)
            if delta != .zero {
                models.append(ModelDelta(model: model, usage: delta))
            }
        }
        models.sort {
            $0.completionTokens == $1.completionTokens
                ? $0.model < $1.model : $0.completionTokens > $1.completionTokens
        }
        return Self(perModel: models, totals: models.reduce(.zero) { $0.adding($1.usage) },
                    resetDetected: resetDetected)
    }

    static func apiEquivalentCost(of usage: OmlxModelUsage,
                                  reference: CostCalculator.ModelPricing) -> Double {
        Double(usage.promptTokens) / 1_000_000 * reference.inputPerMTok
            + Double(usage.completionTokens) / 1_000_000 * reference.outputPerMTok
    }
}
