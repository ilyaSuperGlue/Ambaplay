import Foundation
import Testing

@testable import AmbaplayApp

// The gate in front of installs while the 3.0 folder move is pending. Every root is a
// temporary directory and Steam and games are stand-ins, as in the BrandMigration tests.
@Suite("Migration launch")
@MainActor
struct MigrationLaunchTests {

    private final class Switches: @unchecked Sendable {
        private let lock = NSLock()
        private var steam = false
        private var game = false
        var steamRunning: Bool {
            get { lock.withLock { steam } }
            set { lock.withLock { steam = newValue } }
        }
        var gameRunning: Bool {
            get { lock.withLock { game } }
            set { lock.withLock { game = newValue } }
        }
    }

    private final class Count: @unchecked Sendable {
        private(set) var value = 0
        func add() { value += 1 }
    }

    private struct Fixture {
        let root: URL
        let migration: BrandMigration
        let switches: Switches
        // A file where the new support folder's parent should be, so the move fails.
        var obstacle: URL { migration.support.deletingLastPathComponent() }

        @MainActor func launcher() -> MigrationLaunch {
            let migration = migration
            return MigrationLaunch(enabled: true, migration: { migration }, pollInterval: .milliseconds(10))
        }
    }

    private func fixture(obstructed: Bool = false) throws -> Fixture {
        let root = try scratchDirectory("migration-launch")
        let switches = Switches()
        let migration = BrandMigration(
            legacySupport: root.appending(path: "old/notproton"),
            support: root.appending(path: "new/ambaplay"),
            legacyCaches: root.appending(path: "caches/notproton"),
            caches: root.appending(path: "caches/ambaplay"),
            legacyHome: root.appending(path: "home/.notproton"),
            home: root.appending(path: "home/.ambaplay"),
            steamUserData: root.appending(path: "Steam"),
            steamRunning: { switches.steamRunning }, gameRunning: { switches.gameRunning })
        let files = FileManager.default
        try files.createDirectory(at: migration.legacySupport, withIntermediateDirectories: true)
        try Data("1.0\n".utf8).write(to: migration.legacySupport.appending(path: "dylib.version"))
        try files.createDirectory(at: migration.steamUserData, withIntermediateDirectories: true)
        let fixture = Fixture(root: root, migration: migration, switches: switches)
        if obstructed { try Data().write(to: fixture.obstacle) }
        return fixture
    }

    @Test("Nothing to move leaves installs free")
    func nothingToMove() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try FileManager.default.removeItem(at: f.migration.legacySupport)

        let launch = f.launcher()
        launch.runAtLaunch()
        #expect(!launch.pending)
        #expect(launch.refusal == nil)
    }

    @Test("A debug build never moves anything")
    func disabledDoesNothing() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let migration = f.migration
        let launch = MigrationLaunch(enabled: false, migration: { migration })

        launch.runAtLaunch()
        #expect(!launch.pending)
        #expect(FileManager.default.fileExists(atPath: f.migration.legacySupport.path))
    }

    @Test("A move that works at launch leaves installs free")
    func movesAtLaunch() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }

        let launch = f.launcher()
        launch.runAtLaunch()
        #expect(!launch.pending)
        #expect(launch.failure == nil)
        #expect(FileManager.default.fileExists(atPath: f.migration.support.appending(path: "dylib.version").path))
    }

    @Test("While Steam runs, installs wait and the move finishes once it quits")
    func waitsForSteam() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.switches.steamRunning = true

        let launch = f.launcher()
        launch.runAtLaunch()
        #expect(launch.pending)
        #expect(launch.blocker == .steamRunning)
        #expect(launch.refusal != nil)

        f.switches.steamRunning = false
        let finished = Count()
        await launch.finishWhenPossible { finished.add() }
        #expect(!launch.pending)
        #expect(finished.value == 1)
        #expect(FileManager.default.fileExists(atPath: f.migration.support.appending(path: "dylib.version").path))
    }

    // Before, a failure was only logged: the move counted as done and the install ran.
    @Test("A failed move keeps blocking installs and reports why")
    func failureKeepsBlocking() async throws {
        let f = try fixture(obstructed: true)
        defer { try? FileManager.default.removeItem(at: f.root) }

        let launch = f.launcher()
        launch.runAtLaunch()
        #expect(launch.pending)
        #expect(launch.failure != nil)
        #expect(launch.refusal?.contains(launch.failure ?? "-") == true)

        // The waiting loop does not paper over it, and nothing is installed.
        let finished = Count()
        await launch.finishWhenPossible { finished.add() }
        #expect(launch.pending)
        #expect(finished.value == 0)
        #expect(FileManager.default.fileExists(atPath: f.migration.legacySupport.path))
    }

    @Test("Trying again after the cause is fixed finishes the move and the install")
    func retryFinishes() async throws {
        let f = try fixture(obstructed: true)
        defer { try? FileManager.default.removeItem(at: f.root) }
        let launch = f.launcher()
        launch.runAtLaunch()
        #expect(launch.failure != nil)

        // Still in the way: the retry fails the same and keeps blocking.
        let finished = Count()
        await launch.retry { finished.add() }
        #expect(launch.pending)
        #expect(launch.failure != nil)
        #expect(finished.value == 0)

        try FileManager.default.removeItem(at: f.obstacle)
        await launch.retry { finished.add() }
        #expect(!launch.pending)
        #expect(launch.failure == nil)
        #expect(launch.refusal == nil)
        #expect(finished.value == 1)
        #expect(FileManager.default.fileExists(atPath: f.migration.support.appending(path: "dylib.version").path))
    }

    @Test("A retry while a game runs waits for it rather than failing")
    func retryWaitsForAGame() async throws {
        let f = try fixture(obstructed: true)
        defer { try? FileManager.default.removeItem(at: f.root) }
        let launch = f.launcher()
        launch.runAtLaunch()
        try FileManager.default.removeItem(at: f.obstacle)

        f.switches.gameRunning = true
        let finished = Count()
        let switches = f.switches
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            switches.gameRunning = false
        }
        await launch.retry { finished.add() }
        #expect(!launch.pending)
        #expect(finished.value == 1)
    }

    @Test("Skipping a failed move frees installs for this launch and leaves the old files")
    func skipFreesInstalls() throws {
        let f = try fixture(obstructed: true)
        defer { try? FileManager.default.removeItem(at: f.root) }
        let launch = f.launcher()
        launch.runAtLaunch()
        #expect(launch.refusal != nil)

        launch.skip()
        #expect(!launch.pending)
        #expect(launch.refusal == nil)
        #expect(FileManager.default.fileExists(atPath: f.migration.legacySupport.path))
        // The next launch tries again.
        #expect(f.migration.isNeeded)
    }

    @Test("A move waiting on Steam cannot be skipped")
    func waitingCannotBeSkipped() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.switches.steamRunning = true
        let launch = f.launcher()
        launch.runAtLaunch()

        launch.skip()
        #expect(launch.pending)
    }

    @Test("Files the new folders already had are reported, not overwritten")
    func keptFilesAreReported() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try FileManager.default.createDirectory(at: f.migration.support, withIntermediateDirectories: true)
        try Data("2.0\n".utf8).write(to: f.migration.support.appending(path: "dylib.version"))

        let launch = f.launcher()
        launch.runAtLaunch()
        #expect(!launch.pending)
        #expect(launch.keptNotes.contains { $0.contains("dylib.version") })
        #expect(try String(contentsOf: f.migration.support.appending(path: "dylib.version"), encoding: .utf8) == "2.0\n")
    }
}
