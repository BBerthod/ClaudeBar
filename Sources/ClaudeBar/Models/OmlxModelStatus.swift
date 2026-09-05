import CoreFoundation
import Foundation

struct OmlxModelStatus: Sendable, Identifiable {
    let id: String
    let isLoaded: Bool
    let isLoading: Bool
    let lastAccess: Date?
    let sizeBytes: Int64?

    var sizeGB: Double? { sizeBytes.map { Double($0) / 1_000_000_000 } }

    static func decodeList(_ data: Data) throws -> [Self] {
        let json = try JSONSerialization.jsonObject(with: data)
        let items: [Any]
        if let array = json as? [Any] {
            items = array
        } else if let envelope = json as? [String: Any],
                  let array = (envelope["models"] as? [Any]) ?? (envelope["data"] as? [Any]) {
            items = array
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: [],
                debugDescription: "Expected a model array or a models/data envelope"))
        }

        return items.compactMap { item in
            guard let model = item as? [String: Any],
                  let id = model["id"] as? String,
                  !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

            let lastAccess = number(model["last_access"]).map { timestamp in
                // Contemporary Unix epochs in milliseconds have at least twelve digits.
                Date(timeIntervalSince1970: abs(timestamp) >= 100_000_000_000
                     ? timestamp / 1_000 : timestamp)
            }
            let sizeBytes = bytes(model["estimated_size"]) ?? bytes(model["size_bytes"])
            return Self(id: id,
                        isLoaded: boolean(model["loaded"]) ?? boolean(model["is_loaded"])
                            ?? ((model["status"] as? String) == "loaded"),
                        isLoading: boolean(model["is_loading"]) ?? false,
                        lastAccess: lastAccess, sizeBytes: sizeBytes)
        }
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let value = value as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value.boolValue
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }

    private static func bytes(_ value: Any?) -> Int64? {
        guard let value = number(value), value >= 0 else { return nil }
        return Int64(exactly: value)
    }
}
