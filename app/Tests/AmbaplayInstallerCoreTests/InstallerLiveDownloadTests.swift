import Foundation
import Testing
@testable import AmbaplayInstallerCore

// Downloads the Latest release over the network, so it runs only with AMBAPLAY_LIVE_DOWNLOAD=1.
@Suite("Installer live download", .enabled(if: ProcessInfo.processInfo.environment["AMBAPLAY_LIVE_DOWNLOAD"] == "1"))
struct InstallerLiveDownloadTests {
    final class Seen: @unchecked Sendable {
        let lock = NSLock()
        var calls = 0, last: Int64 = 0
    }

    @Test("The Latest app downloads with progress and passes its signature check")
    func latestApp() async throws {
        let release = try await InstallerRelease.latest()
        let seen = Seen()
        let dir = FileManager.default.temporaryDirectory.appending(path: "live-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let start = Date()
        let archive = try await release.download(to: dir) { value in
            seen.lock.withLock { seen.calls += 1; seen.last = value.received }
        }
        let seconds = Date().timeIntervalSince(start)
        print("live download: \(release.archiveLength) bytes in \(String(format: "%.1f", seconds))s, "
              + "\(String(format: "%.1f", Double(release.archiveLength) / seconds / 1e6)) MB/s, \(seen.calls) progress calls")
        #expect(FileManager.default.fileExists(atPath: archive.path))
        #expect(seen.calls > 10 && seen.last == release.archiveLength)
    }
}
