import os

enum Log {
    static let stats = Logger(subsystem: "com.claudebar", category: "stats")
    static let sessions = Logger(subsystem: "com.claudebar", category: "sessions")
    static let usage = Logger(subsystem: "com.claudebar", category: "usage")
    static let providers = Logger(subsystem: "com.claudebar", category: "providers")
    static let notifications = Logger(subsystem: "com.claudebar", category: "notifications")
    static let settings = Logger(subsystem: "com.claudebar", category: "settings")
}
