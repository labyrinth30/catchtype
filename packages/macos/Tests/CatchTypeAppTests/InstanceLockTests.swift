#if os(macOS)
import XCTest
@testable import CatchTypeApp

final class InstanceLockTests: XCTestCase {
    func testSecondInstanceIsRejectedAndCrashStyleCloseReleasesLock() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("instance.lock")
        var first: CTInstanceLock? = try XCTUnwrap(CTInstanceLock(url: url))
        XCTAssertNotNil(first)
        XCTAssertNil(CTInstanceLock(url: url))
        first = nil
        XCTAssertNotNil(CTInstanceLock(url: url))
    }

    func testLockDoesNotFollowSymlink() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target")
        try Data().write(to: target)
        let link = directory.appendingPathComponent("instance.lock")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertNil(CTInstanceLock(url: link))
    }
}
#endif
