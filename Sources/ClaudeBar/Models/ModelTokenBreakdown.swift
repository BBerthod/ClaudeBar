import Foundation

struct ModelTokenBreakdown: Sendable {
    var input: Int = 0
    var output: Int = 0
    var cacheRead: Int = 0
    var cacheCreation: Int = 0
    var total: Int { input + output + cacheRead + cacheCreation }
}
