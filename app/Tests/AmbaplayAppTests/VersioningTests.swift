import Foundation
import Testing

@testable import AmbaplayApp

@Suite("Product version")
struct ProductVersionTests {

    private static func define(_ name: String) throws -> String {
        let header = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "dylib/version.h")
        let text = try String(contentsOf: header, encoding: .utf8)
        let line = try #require(text.split(separator: "\n").first { $0.hasPrefix("#define \(name) ") })
        return String(line.dropFirst("#define \(name) ".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    // The last version of the old scheme, as an installed build record in Steam says it.
    private static let lastLegacy = "1.2.0-winehq.1-ray.32"

    @Test("The install record reads as newer than any build of the old scheme")
    func newerThanLegacy() throws {
        let version = try Self.define("AMBAPLAY_VERSION")
        #expect(version.split(separator: ".").count == 3)
        let key = AppVersion.deployKey(build: try Self.define("AMBAPLAY_BUILD"), display: version)
        let bundled = DeploymentContent.Build(version: key, builtAt: 1)
        for old in [Self.lastLegacy, "3.5.0"] {
            let installed = DeploymentContent.Build(version: old, builtAt: 2)
            #expect(bundled.isNewer(than: installed), "\(old)")
            #expect(!installed.isNewer(than: bundled), "\(old)")
        }
    }

    // 3.5.0 went back to 0.7.0: installs are ordered by the build, never the display version.
    @Test("The deploy key follows the build, and an older app leaves a newer install alone")
    func deployKey() {
        #expect(AppVersion.deployKey(build: "44", display: "0.7.0") == "4.0.44")
        #expect(AppVersion.deployKey(build: nil, display: "0.1.0-dev") == "0.1.0-dev")
        let next = DeploymentContent.Build(version: AppVersion.deployKey(build: "45", display: "0.7.1"), builtAt: 1)
        let this = DeploymentContent.Build(version: AppVersion.deployKey(build: "44", display: "0.7.0"), builtAt: 2)
        let build100 = DeploymentContent.Build(version: AppVersion.deployKey(build: "100", display: "0.9.0"), builtAt: 1)
        #expect(next.isNewer(than: this) && build100.isNewer(than: next))
        // Ambaplay 3.5.0 (build 43), as another macOS user sharing Steam.app might still run it.
        let older = DeploymentContent.Build(version: "3.5.0", builtAt: 3)
        #expect(this.isNewer(than: older) && !older.isNewer(than: this))
        #expect(AppVersion.label(deployed: "4.0.44") == "build 44")
        #expect(AppVersion.label(deployed: "3.5.0") == "3.5.0")
    }

    @Test("The build number is a plain integer past the old ray counter")
    func buildContinuesCounter() throws {
        let build = try #require(Int(try Self.define("AMBAPLAY_BUILD")))
        #expect(build >= 32)
    }

    @Test("The display names the build and the NotProton release")
    func display() {
        #expect(ProductVersion.display(short: "2.0.0", build: "32", upstream: "1.2.0")
            == "Ambaplay 2.0.0 (32) · based on NotProton 1.2.0")
        #expect(ProductVersion.display(short: "0.1.0-dev", build: nil, upstream: nil) == "Ambaplay 0.1.0-dev")
    }

    // The committed version is a plain X.Y.Z. A beta label like 0.7.3-beta.1 is stamped into the
    // built app by scripts/stamp-beta.sh and never committed.
    @Test("The committed version is a plain X.Y.Z")
    func committedVersionHasNoBetaLabel() throws {
        let version = try Self.define("AMBAPLAY_VERSION")
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        #expect(parts.count == 3 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isWholeNumber } },
                "\(version)")
    }

    @Test("A stamped beta label shows in the display, with the build it carries")
    func betaLabelDisplays() {
        #expect(ProductVersion.display(short: "0.7.3-beta.1", build: "50", upstream: "1.2.0")
            == "Ambaplay 0.7.3-beta.1 (50) · based on NotProton 1.2.0")
    }

    @Test("A missing, empty or unreadable channel means stable")
    func channelDefaultsToStable() {
        #expect(ProductVersion.channel(from: "beta") == .beta)
        #expect(ProductVersion.channel(from: " Beta\n") == .beta)
        #expect(ProductVersion.channel(from: "stable") == .stable)
        #expect(ProductVersion.channel(from: nil) == .stable)
        #expect(ProductVersion.channel(from: "") == .stable)
        #expect(ProductVersion.channel(from: "nightly") == .stable)
        #expect(ProductVersion.channel(from: 1) == .stable)
    }

    private static func published(_ build: Int, _ label: String) -> DeploymentContent.Build {
        DeploymentContent.Build(version: AppVersion.deployKey(build: String(build), display: label), builtAt: 1)
    }

    // Installs are ordered by the build alone. 0.7.3-beta.1 follows 0.7.2 (build 44) and
    // the stable 0.7.3 is the number the betas were named after.
    @Test("A beta orders above the stable it branched from, and the next stable above every beta")
    func betaOrdering() {
        let stable = Self.published(44, "0.7.2")
        let beta1 = Self.published(45, "0.7.3-beta.1")
        let beta2 = Self.published(46, "0.7.3-beta.2")
        let next = Self.published(47, "0.7.3")
        for beta in [beta1, beta2] {
            #expect(beta.isNewer(than: stable) && !stable.isNewer(than: beta))
            #expect(next.isNewer(than: beta) && !beta.isNewer(than: next))
        }
        #expect(beta2.isNewer(than: beta1) && !beta1.isNewer(than: beta2))
        // Build 100 stays above 99: the build compares as a number, not as text.
        #expect(Self.published(100, "0.7.4").isNewer(than: Self.published(99, "0.7.4-beta.9")))
    }

    @Test("A beta record is never taken for an older or newer build by its label")
    func labelDoesNotOrder() {
        // By label 0.10.0-beta.1 is above 0.9.0, and the build still decides.
        let beta = Self.published(46, "0.10.0-beta.1")
        let stable = Self.published(47, "0.9.0")
        #expect(stable.isNewer(than: beta) && !beta.isNewer(than: stable))
        #expect(AppVersion.label(deployed: AppVersion.deployKey(build: "46", display: "0.10.0-beta.1")) == "build 46")
    }
}

@Suite("Post-update refresh")
struct PostUpdateRefreshTests {

    private func decide(
        steam: SteamDeployment = .outdated(deployed: "1.1.9-winehq.1-ray.31", bundled: "2.0.0"),
        steamRunning: Bool = false,
        workloadRunning: Bool = false,
        contentBlocks: Bool = false,
        hasRunner: Bool = true,
        build: String? = "32",
        lastBuild: String? = nil
    ) -> PostUpdateRefresh.Decision {
        PostUpdateRefresh.decide(steam: steam, steamRunning: steamRunning, workloadRunning: workloadRunning,
                                 contentBlocks: contentBlocks, hasRunner: hasRunner,
                                 build: build, lastBuild: lastBuild)
    }

    @Test("The first launch after an update re-applies an older patch")
    func installsAfterUpdate() {
        #expect(decide() == .install)
        // Sparkle's own ordering: build 32 follows the old dotted 1.1.9.31.
        #expect(decide(lastBuild: "1.1.9.31") == .install)
        #expect(decide(build: "33", lastBuild: "32") == .install)
    }

    @Test("Steam or a running game defers it to a later launch")
    func waitsForSteamAndGames() {
        #expect(decide(steamRunning: true) == .wait)
        #expect(decide(workloadRunning: true) == .wait)
    }

    @Test("Nothing happens without an update or when installing would need the user")
    func leavesOtherCasesAlone() {
        #expect(decide(lastBuild: "32") == .nothing)
        #expect(decide(build: "32", lastBuild: "33") == .nothing)
        #expect(decide(build: nil) == .nothing)
        #expect(decide(steam: .installed(version: "2.0.0")) == .nothing)
        #expect(decide(steam: .notInstalled) == .nothing)
        #expect(decide(steam: .outdated(deployed: "", bundled: "2.0.0")) == .nothing)
        #expect(decide(steam: .outdated(deployed: "2.0.0", bundled: "2.0.0")) == .nothing)
        #expect(decide(contentBlocks: true) == .nothing)
        #expect(decide(hasRunner: false) == .nothing)
    }
}
