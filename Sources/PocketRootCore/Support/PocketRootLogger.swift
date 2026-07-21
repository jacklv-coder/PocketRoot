enum PocketRootLogger {
    static func debug(_ message: String) {
        print("[PocketRootCore] DEBUG: \(message)")
    }

    static func error(_ message: String) {
        print("[PocketRootCore] ERROR: \(message)")
    }
}
