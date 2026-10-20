#if os(macOS)
import Cocoa

let lockDirectory = CTConfigStore.directory
try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
guard let instanceLock = CTInstanceLock(url: lockDirectory.appendingPathComponent("instance.lock")) else {
    fputs("[catchtype] another instance is running or the instance lock is unavailable\n", stderr)
    exit(0)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
withExtendedLifetime(instanceLock) { app.run() }
#endif
