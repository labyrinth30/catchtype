#if os(macOS)
import Foundation
import Darwin

/// Keep the descriptor open: removing a lock file on exit can let two instances own different inodes.
final class CTInstanceLock {
    private let descriptor: Int32

    init?(url: URL) {
        descriptor = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
    }

    deinit { close(descriptor) }
}
#endif
