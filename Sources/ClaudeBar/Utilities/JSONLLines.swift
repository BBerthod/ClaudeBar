import Foundation

/// Cheap byte-level pre-filter for JSONL transcripts. Most lines are user / tool_result
/// payloads that the scanners discard after a full JSON parse; skipping them on raw bytes
/// avoids the parse and the String conversion.
enum JSONLLines {
    /// Non-empty lines of `data` (split on "\n") whose bytes contain `needle` (UTF-8).
    /// Lossless for callers that only keep JSON objects whose value is exactly "assistant":
    /// such a line always contains the quoted token `"assistant"`, whatever the JSON spacing.
    nonisolated static func lines(in data: Data, containing needle: String) -> [Data] {
        guard !data.isEmpty else { return [] }

        let needleData = Data(needle.utf8)

        return data.withUnsafeBytes { dataBuffer in
            guard let dataBaseAddress = dataBuffer.baseAddress else { return [] }

            var lines: [Data] = []
            var lineStart = 0

            while lineStart < dataBuffer.count {
                let lineAddress = dataBaseAddress.advanced(by: lineStart)
                let remainingCount = dataBuffer.count - lineStart
                let newlineAddress = memchr(lineAddress, Int32(0x0A), remainingCount)
                let lineLength: Int

                if let newlineAddress {
                    lineLength = dataBaseAddress.distance(to: UnsafeRawPointer(newlineAddress)) - lineStart
                } else {
                    lineLength = remainingCount
                }

                if lineLength > 0 {
                    let containsNeedle = needleData.isEmpty || needleData.withUnsafeBytes { needleBuffer in
                        guard let needleAddress = needleBuffer.baseAddress else { return true }
                        return memmem(lineAddress, lineLength, needleAddress, needleBuffer.count) != nil
                    }

                    if containsNeedle {
                        lines.append(Data(bytes: lineAddress, count: lineLength))
                    }
                }

                guard newlineAddress != nil else { break }
                lineStart += lineLength + 1
            }

            return lines
        }
    }
}
