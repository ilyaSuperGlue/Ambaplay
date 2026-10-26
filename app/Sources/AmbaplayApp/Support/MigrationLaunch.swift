import Foundation
import Observation

// Runs the 3.0.0 move from the notproton folders to the ambaplay ones (BrandMigration).
// It starts in Launch.main, before AppLog or anything else opens the support folder. While
// it is pending nothing that writes Ambaplay's folders runs: installs, the Setup
// Assistant, the patch keeper, the post-update install and the command line installs all
// wait. If Steam or a game is running it waits: the main window shows a banner and the move
// finishes by itself once both are closed. If the move fails, the Status page says why and
// it keeps waiting until the user tries again or skips it for this launch. Once it is done
// Ambaplay installs itself into Steam again, because the copy Steam holds still points at
// the old folders.
@MainActor
@Observable
final class MigrationLaunch {
    static let shared = MigrationLaunch()

    private(set) var pending = false
    private(set) var blocker: BrandMigration.Blocker?
    // Why the last attempt failed; the move stays pending until a retry works or a skip.
    private(set) var failure: String?
    // What the move left in the old folders because the new ones already had it.
    private(set) var keptNotes: [String] = []
    private(set) var isRunning = false
    @ObservationIgnored private var launchNote: String?

    @ObservationIgnored private let enabled: Bool
    @ObservationIgnored private let migration: @Sendable () -> BrandMigration
    @ObservationIgnored private let pollInterval: Duration

    init(
        enabled: Bool = MigrationLaunch.enabled,
        migration: @escaping @Sendable () -> BrandMigration = { BrandMigration.live() },
        pollInterval: Duration = .seconds(4)
    ) {
        self.enabled = enabled
        self.migration = migration
        self.pollInterval = pollInterval
    }

    // Debug builds run from the source tree and never move the real folders.
    nonisolated static var enabled: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    func runAtLaunch() {
        guard enabled else { return }
        let migration = migration()
        guard migration.isNeeded else { return }
        pending = true
        if let blocker = migration.canRun() {
            self.blocker = blocker
            launchNote = "migration 3.0.0 waits: \(blocker)"
            return
        }
        launchNote = settle(Result { try migration.run() })
    }

    // AppLog only exists once the app has started, so the launch result is logged then.
    func logLaunchResult() {
        if let launchNote { AppLog.note(launchNote) }
        launchNote = nil
    }

    // Waits for Steam and games to close, then moves; finished runs after a move that worked.
    // Returns without waiting when the last attempt failed: only retry() tries again.
    func finishWhenPossible(then finished: @MainActor () async -> Void) async {
        while pending, failure == nil, !Task.isCancelled {
            try? await Task.sleep(for: pollInterval)
            guard pending, failure == nil, !isRunning else { continue }
            let migration = migration()
            guard migration.isNeeded else {
                pending = false
                blocker = nil
                return
            }
            blocker = migration.canRun()
            guard blocker == nil else { continue }
            if await attempt(migration) {
                await finished()
                return
            }
        }
    }

    func finishWhenPossible(_ status: SystemStatus) async {
        await finishWhenPossible { await Self.afterMove(status) }
    }

    func retry(then finished: @MainActor () async -> Void) async {
        guard pending, !isRunning else { return }
        failure = nil
        AppLog.note("migration 3.0.0: trying again")
        let migration = migration()
        guard migration.isNeeded else {
            pending = false
            blocker = nil
            return
        }
        blocker = migration.canRun()
        if blocker == nil, await attempt(migration) {
            await finished()
        } else if pending, failure == nil {
            // Steam or a game is open: wait for it like the launch does.
            await finishWhenPossible(then: finished)
        }
    }

    func retry(_ status: SystemStatus) async {
        await retry { await Self.afterMove(status) }
    }

    // Lets installs run again until the next launch, which tries the move once more. Only
    // offered after a failure: a move waiting on Steam finishes by itself.
    func skip() {
        guard pending, failure != nil, !isRunning else { return }
        AppLog.note("migration 3.0.0 skipped for this launch after: \(failure ?? "")")
        pending = false
        failure = nil
        blocker = nil
    }

    // Why an install cannot run yet, or nil when it can.
    var refusal: String? {
        guard pending else { return nil }
        if let failure {
            return String(localized: "Ambaplay could not move its files to the new Ambaplay folders: \(failure) Try again or skip it on the Status page first.")
        }
        return String(localized: "Ambaplay is still moving its files to the new Ambaplay folders.") + " " + bannerMessage
    }

    private static func afterMove(_ status: SystemStatus) async {
        await status.refresh()
        await status.installIntoSteam(unattended: true)
    }

    private func attempt(_ migration: BrandMigration) async -> Bool {
        isRunning = true
        defer { isRunning = false }
        let result = await Task.detached(priority: .userInitiated) { Result { try migration.run() } }.value
        AppLog.note(settle(result))
        return !pending
    }

    // Records a run's result and returns the line to log.
    private func settle(_ result: Result<BrandMigration.Summary, Error>) -> String {
        switch result {
        case .success(let summary):
            pending = false
            blocker = nil
            failure = nil
            keptNotes = summary.notes
            return "migration 3.0.0: \(summary.description)"
        case .failure(let refusal as BrandMigration.Failure):
            // Steam or a game started between the check and the run; wait again.
            switch refusal {
            case .blocked(let blocker):
                self.blocker = blocker
                return "migration 3.0.0 waits: \(blocker)"
            }
        case .failure(let error):
            failure = error.localizedDescription
            return "migration 3.0.0 failed: \(error)"
        }
    }

    var bannerMessage: String {
        switch blocker {
        case .gameRunning: String(localized: "Quit your game. Ambaplay finishes moving its files to the new Ambaplay folders by itself.")
        default: String(localized: "Quit Steam. Ambaplay finishes moving its files to the new Ambaplay folders by itself, then adds itself to Steam again.")
        }
    }
}
