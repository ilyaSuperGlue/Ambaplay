import Foundation

// Notices when Steam no longer carries Ambaplay (a Steam client update rewrites
// Steam.app) or carries an older build (Ambaplay itself updated), and decides whether to
// put it back silently or to ask. It never touches Steam while Steam or a game runs, so it
// cannot fight Steam's own updater, and it tries on its own at most once per cooldown.
enum SteamPatchKeeper {

    // Set by Repair Steam, cleared by any install: a Steam the user restored on purpose
    // stays restored.
    static let pausedKey = "steamPatchKeeperPaused"
    static let cooldown: TimeInterval = 15 * 60
    // Window focus can arrive in bursts; checks closer together than this are skipped.
    static let checkInterval: TimeInterval = 20
    static let pollInterval: Duration = .seconds(300)

    enum Kind: Equatable, Sendable {
        // Steam's update replaced the bundle, so the patch is gone.
        case removedBySteam
        // This Ambaplay has a newer patch than the one in Steam.
        case outdated
    }

    enum Blocker: Equatable, Sendable {
        case steamRunning
        case gameRunning
        case lastTryFailed
    }

    enum Decision: Equatable, Sendable {
        case nothing
        case reapply(Kind)
        case ask(Kind, Blocker)
    }

    struct Inputs: Sendable {
        var deployment: SteamDeployment
        // dylib.version exists, so Ambaplay was installed into Steam from this account.
        var previouslyDeployed: Bool
        var steamRunning: Bool
        var gameRunning: Bool
        var paused = false
        var installBlocked = false
        var lastAttempt: Date?
        var lastAttemptFailed = false
        var now = Date()
    }

    static func kind(of deployment: SteamDeployment, previouslyDeployed: Bool) -> Kind? {
        switch deployment {
        case .notInstalled: previouslyDeployed ? .removedBySteam : nil
        case .outdated: .outdated
        case .installed, .steamMissing, .foreign: nil
        }
    }

    static func decide(_ inputs: Inputs) -> Decision {
        guard !inputs.paused, !inputs.installBlocked,
              let kind = kind(of: inputs.deployment, previouslyDeployed: inputs.previouslyDeployed)
        else { return .nothing }
        if inputs.gameRunning { return .ask(kind, .gameRunning) }
        if inputs.steamRunning { return .ask(kind, .steamRunning) }
        if inputs.lastAttemptFailed { return .ask(kind, .lastTryFailed) }
        if let last = inputs.lastAttempt, inputs.now.timeIntervalSince(last) < cooldown {
            return .ask(kind, .lastTryFailed)
        }
        return .reapply(kind)
    }

    // Reads only what decide() needs: the plist, two process lists and one small file.
    static func capture(
        bundledVersion: String,
        versionFile: URL = SupportPaths.deployedVersion
    ) -> (deployment: SteamDeployment, previouslyDeployed: Bool, steamRunning: Bool, gameRunning: Bool) {
        let gameRunning = Shell.processIsRunning(named: "wineserver")
            || RunnerStore.clonedBuilds().contains { RunnerInstaller.isRunning(from: SupportPaths.runnerRoot(forBuild: $0)) }
        return (SteamBundle.deployment(bundledVersion: bundledVersion, versionFile: versionFile),
                SteamBundle.deployedVersion(at: versionFile) != nil,
                SteamBundle.isRunning,
                gameRunning)
    }

    struct Banner: Equatable, Sendable {
        let kind: Kind
        let blocker: Blocker

        var title: String {
            switch kind {
            case .removedBySteam: String(localized: "Steam updated")
            case .outdated: String(localized: "Ambaplay update for Steam")
            }
        }

        var message: String {
            let lead = switch kind {
            case .removedBySteam: String(localized: "Steam's update removed Ambaplay, so Windows games won't start.")
            case .outdated: String(localized: "This version of Ambaplay has newer files for Steam.")
            }
            let next = switch blocker {
            case .steamRunning: String(localized: "Steam closes for a moment and opens again.")
            case .gameRunning: String(localized: "Quit your game first.")
            case .lastTryFailed: String(localized: "Ambaplay couldn't do this on its own.")
            }
            return "\(lead) \(next)"
        }

        var button: String {
            switch blocker {
            case .lastTryFailed: String(localized: "Try Again")
            case .steamRunning, .gameRunning: String(localized: "Re-apply Ambaplay")
            }
        }

        var canApply: Bool { blocker != .gameRunning }
    }
}
