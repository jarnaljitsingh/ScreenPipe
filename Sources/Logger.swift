import Foundation
import os.log

enum Log {
    private static let logger = OSLog(subsystem: "com.jarnaljit.screenpipe", category: "app")

    static func info(_ message: String) {
        os_log("%{public}@", log: logger, type: .info, message)
        print("[ScreenPipe] \(message)")
    }

    static func error(_ message: String) {
        os_log("%{public}@", log: logger, type: .error, message)
        print("[ScreenPipe][ERROR] \(message)")
    }

    static func fault(_ message: String) {
        os_log("%{public}@", log: logger, type: .fault, message)
        print("[ScreenPipe][FAULT] \(message)")
    }
}
