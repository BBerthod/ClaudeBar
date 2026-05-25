import Foundation

/// Response from `GET http://localhost:8000/health` (no auth required).
/// Example: {"status":"healthy","default_model":"Qwen3.6-27B",
///           "engine_pool":{"model_count":2,"loaded_count":0,
///                          "max_model_memory":115964116992,"current_model_memory":0},"mcp":null}
struct OmlxHealthResponse: Codable, Sendable {
    let status: String
    let defaultModel: String?
    let enginePool: EnginePool?

    struct EnginePool: Codable, Sendable {
        let modelCount: Int
        let loadedCount: Int
        let maxModelMemory: Int64
        let currentModelMemory: Int64

        enum CodingKeys: String, CodingKey {
            case modelCount = "model_count"
            case loadedCount = "loaded_count"
            case maxModelMemory = "max_model_memory"
            case currentModelMemory = "current_model_memory"
        }
    }

    /// True when `status == "healthy"`.
    var isHealthy: Bool { status == "healthy" }

    /// Max engine memory in GB (0 if no engine_pool).
    var maxMemoryGB: Double {
        Double(max(0, enginePool?.maxModelMemory ?? 0)) / 1_073_741_824
    }

    /// Current memory used in GB (0 if no engine_pool).
    var usedMemoryGB: Double {
        Double(max(0, enginePool?.currentModelMemory ?? 0)) / 1_073_741_824
    }

    enum CodingKeys: String, CodingKey {
        case status
        case defaultModel = "default_model"
        case enginePool = "engine_pool"
    }
}
