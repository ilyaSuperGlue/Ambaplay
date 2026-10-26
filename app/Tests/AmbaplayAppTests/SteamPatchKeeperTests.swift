import Foundation
import Testing

@testable import AmbaplayApp

@Suite("Keeping Ambaplay in Steam")
struct SteamPatchKeeperTests {

    private func inputs(
        _ deployment: SteamDeployment = .notInstalled,
        previouslyDeployed: Bool = true,
        steamRunning: Bool = false,
        gameRunning: Bool = false,
        paused: Bool = false,
        installBlocked: Bool = false,
        lastAttempt: Date? = nil,
        lastAttemptFailed: Bool = false,
        now: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> SteamPatchKeeper.Inputs {
        SteamPatchKeeper.Inputs(
            deployment: deployment, previouslyDeployed: previouslyDeployed, steamRunning: steamRunning,
            gameRunning: gameRunning, paused: paused, installBlocked: installBlocked,
            lastAttempt: lastAttempt, lastAttemptFailed: lastAttemptFailed, now: now)
    }

    @Test("Steam closed and no game running: the patch goes back on its own")
    func reappliesSilently() {
        #expect(SteamPatchKeeper.decide(inputs()) == .reapply(.removedBySteam))
        #expect(SteamPatchKeeper.decide(inputs(.outdated(deployed: "1.0", bundled: "1.1"))) == .reapply(.outdated))
    }

    @Test("Steam running: ask, never stop Steam unasked")
    func asksWhileSteamRuns() {
        #expect(SteamPatchKeeper.decide(inputs(steamRunning: true)) == .ask(.removedBySteam, .steamRunning))
    }

    @Test("A running game wins over everything, and its banner cannot apply")
    func waitsForTheGame() {
        let decision = SteamPatchKeeper.decide(inputs(steamRunning: true, gameRunning: true))
        #expect(decision == .ask(.removedBySteam, .gameRunning))
        #expect(!SteamPatchKeeper.Banner(kind: .removedBySteam, blocker: .gameRunning).canApply)
        #expect(SteamPatchKeeper.Banner(kind: .removedBySteam, blocker: .steamRunning).canApply)
    }

    @Test("A Steam that never had Ambaplay is left to the Setup Assistant")
    func leavesFreshSteamAlone() {
        #expect(SteamPatchKeeper.decide(inputs(previouslyDeployed: false)) == .nothing)
    }

    @Test("Installed, missing, foreign or repaired Steam is left alone")
    func nothingToDo() {
        #expect(SteamPatchKeeper.decide(inputs(.installed(version: "1.0"))) == .nothing)
        #expect(SteamPatchKeeper.decide(inputs(.steamMissing)) == .nothing)
        #expect(SteamPatchKeeper.decide(inputs(.foreign(insert: "/other.dylib"))) == .nothing)
        #expect(SteamPatchKeeper.decide(inputs(paused: true)) == .nothing)
        #expect(SteamPatchKeeper.decide(inputs(installBlocked: true)) == .nothing)
    }

    @Test("A failed or recent attempt is not repeated on its own")
    func debounces() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(SteamPatchKeeper.decide(inputs(lastAttemptFailed: true)) == .ask(.removedBySteam, .lastTryFailed))
        #expect(SteamPatchKeeper.decide(inputs(lastAttempt: now.addingTimeInterval(-60), now: now))
            == .ask(.removedBySteam, .lastTryFailed))
        #expect(SteamPatchKeeper.decide(inputs(lastAttempt: now.addingTimeInterval(-SteamPatchKeeper.cooldown - 1), now: now))
            == .reapply(.removedBySteam))
    }

    @Test("Banner text names Ambaplay and says what happens next")
    func bannerText() {
        let banner = SteamPatchKeeper.Banner(kind: .removedBySteam, blocker: .steamRunning)
        #expect(banner.title == "Steam updated")
        #expect(banner.message.contains("Ambaplay"))
        #expect(banner.button == "Re-apply Ambaplay")
    }

    @Test("The Input Monitoring link opens the ListenEvent list")
    @MainActor
    func inputMonitoringLink() {
        #expect(SystemStatus.inputMonitoringPane.scheme == "x-apple.systempreferences")
        #expect(SystemStatus.inputMonitoringPane.query == "Privacy_ListenEvent")
    }
}
