import Foundation

enum ScreenshotMode {
    case fullScreen
    case interactive
}

enum ScreenshotService {
    static func capture(mode: ScreenshotMode, completion: @escaping (URL?) -> Void) {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = cachesDir.appendingPathComponent("ScreenPipe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let filename = "screenshot-\(formatter.string(from: Date())).png"
        let url = dir.appendingPathComponent(filename)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        switch mode {
        case .fullScreen:
            task.arguments = ["-x", url.path]
        case .interactive:
            task.arguments = ["-i", "-s", "-x", url.path]
        }

        Log.info("spawning screencapture \(task.arguments ?? []) → \(url.path)")

        task.terminationHandler = { proc in
            let exists = FileManager.default.fileExists(atPath: url.path)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            Log.info("screencapture exited status=\(proc.terminationStatus) fileExists=\(exists) size=\(size)")
            DispatchQueue.main.async {
                if proc.terminationStatus == 0, exists {
                    completion(url)
                } else {
                    completion(nil)
                }
            }
        }

        do {
            try task.run()
        } catch {
            Log.error("failed to run screencapture: \(error)")
            DispatchQueue.main.async { completion(nil) }
        }
    }

    static func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
