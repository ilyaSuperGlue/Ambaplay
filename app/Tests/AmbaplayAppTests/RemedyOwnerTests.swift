import Foundation
import Testing

@testable import AmbaplayApp

// #391: a Steam.app root owns (MDM, `sudo cp`) was blamed on another account on this Mac.
@Suite("Who owns a refused path")
struct RemedyOwnerTests {

    private static let user: uid_t = 501

    private static func lookup(
        owner: @escaping (String) -> uid_t?, writable: Bool = false, home: String = "/Users/np-test"
    ) -> Remedy.Lookup {
        Remedy.Lookup(owner: owner, writable: { _ in writable }, user: user, home: home)
    }

    private static func owned(by uid: uid_t, writable: Bool = false) -> Remedy.Lookup {
        lookup(owner: { _ in uid }, writable: writable)
    }

    private func scratch() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "np-owner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func steamBundle() throws -> (root: URL, app: URL, inside: String) {
        let root = try scratch()
        let app = root.appending(path: "Steam.app")
        let inside = app.appending(path: "Contents/MacOS")
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: app.appending(path: "Contents/Info.plist"))
        return (root, app, inside.path(percentEncoded: false))
    }

    @Test("A bundle root owns is root's, with the bundle to hand over")
    func rootOwnedBundle() throws {
        let steam = try steamBundle()
        defer { try? FileManager.default.removeItem(at: steam.root) }

        let found = Remedy(forPath: steam.inside, lookup: Self.owned(by: 0))

        #expect(found == .rootOwned(handOver: steam.app.path(percentEncoded: false)))
        #expect(found.settingsPane == nil)
        #expect(Remedy(forPath: steam.inside, errno: EACCES, lookup: Self.owned(by: 0, writable: true))
            == found, "the permissions refused it, whatever access() says")
    }

    // EPERM comes from a policy, App Management among them, not from who owns the folder.
    @Test("A root-owned bundle refused by a policy asks for App Management")
    func policyRefusalAsksForAppManagement() throws {
        let steam = try steamBundle()
        defer { try? FileManager.default.removeItem(at: steam.root) }

        #expect(Remedy(forPath: steam.inside, errno: EPERM, lookup: Self.owned(by: 0)) == .appManagement)
        #expect(Remedy(forPath: steam.inside, errno: EPERM, lookup: Self.owned(by: 502)) == .appManagement)
    }

    // Renames and new files are decided by the folder, not by the file being replaced.
    @Test("The folder holding a file decides, not the file")
    func folderDecides() throws {
        let steam = try steamBundle()
        defer { try? FileManager.default.removeItem(at: steam.root) }
        let dylib = URL(filePath: steam.inside).appending(path: "notproton.dylib")
        try Data("old".utf8).write(to: dylib)
        let path = dylib.path(percentEncoded: false)
        let rootFolder = Self.lookup(owner: { $0 == steam.inside ? 0 : Self.user })

        #expect(Remedy(forPath: path, errno: EACCES, lookup: rootFolder)
            == .rootOwned(handOver: steam.app.path(percentEncoded: false)))
        #expect(Remedy(forPath: path, errno: EPERM, lookup: Self.lookup(owner: { $0 == path ? 0 : Self.user }))
            == .appManagement)
    }

    @Test("A refusal inside a nested app names the outer bundle")
    func nestedAppNamesTheOuterBundle() throws {
        let steam = try steamBundle()
        defer { try? FileManager.default.removeItem(at: steam.root) }
        let helper = steam.app.appending(path: "Contents/MacOS/Frameworks/Steam Helper.app")
        try FileManager.default.createDirectory(
            at: helper.appending(path: "Contents/MacOS"), withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: helper.appending(path: "Contents/Info.plist"))

        let inside = helper.appending(path: "Contents/MacOS").path(percentEncoded: false)

        #expect(Remedy(forPath: inside, lookup: Self.owned(by: 0))
            == .rootOwned(handOver: steam.app.path(percentEncoded: false)))
    }

    @Test("A root folder outside a bundle and the home gets no chown command")
    func rootOwnedFolder() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }

        let found = Remedy(forPath: root.path(percentEncoded: false), lookup: Self.owned(by: 0))

        #expect(found == .rootOwned(handOver: nil))
        #expect(!found.advice.contains("chown"))
        #expect(!found.advice.contains("its owner"), "advised taking over a system folder")
    }

    // /Applications itself is root-owned. A target missing under it is judged by it.
    @Test("A missing target under /Applications is not advised to take over /Applications")
    func missingTargetUnderApplications() {
        let found = Remedy(forPath: "/Applications/np-missing-\(UUID().uuidString).app",
                           errno: EACCES, lookup: Self.owned(by: 0))

        #expect(found == .rootOwned(handOver: nil))
        #expect(!found.advice.contains("chown"))
    }

    // After `sudo make deploy`, say: the support folder is root's, inside the user's home.
    @Test("A root-owned folder in the home hands over its topmost root-owned folder")
    func rootOwnedFolderInTheHome() throws {
        let home = try scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let support = home.appending(path: "Library/Application Support")
        let ambaplay = support.appending(path: "ambaplay")
        let runners = ambaplay.appending(path: "runners")
        try FileManager.default.createDirectory(at: runners, withIntermediateDirectories: true)
        let rootOwned = ambaplay.path(percentEncoded: false)
        let lookup = Self.lookup(
            owner: { $0.hasPrefix(rootOwned) ? 0 : Self.user },
            home: home.path(percentEncoded: false)
        )

        let found = Remedy(forPath: runners.appending(path: "crossover-1").path(percentEncoded: false),
                           errno: EACCES, lookup: lookup)

        #expect(found == .rootOwned(handOver: rootOwned))
        #expect(found.advice.contains(Remedy.chownCommand(rootOwned)))
    }

    @Test("A bundle root owns that this account may still write asks for App Management")
    func writableRootBundleAsksForAppManagement() throws {
        let steam = try steamBundle()
        defer { try? FileManager.default.removeItem(at: steam.root) }

        #expect(Remedy(forPath: steam.inside, lookup: Self.owned(by: 0, writable: true)) == .appManagement)
        #expect(Remedy(forPath: steam.inside, lookup: Self.owned(by: 502, writable: true)) == .appManagement)
    }

    @Test("A bundle another user owns is still another account's")
    func otherUser() throws {
        let steam = try steamBundle()
        defer { try? FileManager.default.removeItem(at: steam.root) }

        #expect(Remedy(forPath: steam.inside, lookup: Self.owned(by: 502)) == .otherAccount)
        #expect(Remedy(forPath: steam.inside, errno: EACCES, lookup: Self.owned(by: 502)) == .otherAccount)
    }

    @Test("Root running the app owns what root owns")
    func rootIsItsOwnAccount() throws {
        let steam = try steamBundle()
        defer { try? FileManager.default.removeItem(at: steam.root) }
        var lookup = Self.owned(by: 0)
        lookup.user = 0

        #expect(Remedy(forPath: steam.inside, lookup: lookup) == .appManagement)
    }

    @Test("An own folder inside a bundle asks for App Management")
    func ownBundle() throws {
        let steam = try steamBundle()
        defer { try? FileManager.default.removeItem(at: steam.root) }

        #expect(Remedy(forPath: steam.inside) == .appManagement)
        #expect(Remedy(forPath: steam.inside, lookup: Self.owned(by: Self.user)) == .appManagement)
    }

    @Test("An own folder outside a bundle asks to check ownership")
    func ownFolder() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(Remedy(forPath: root.path(percentEncoded: false)) == .ownership)
    }

    @Test("A path that is not there asks to check ownership")
    func missingPath() {
        #expect(Remedy(forPath: "/nonexistent/np-\(UUID().uuidString)/file", lookup: Self.owned(by: 0)) == .ownership)
    }

    // Real refusals: a locked folder gives EPERM, a read-only one EACCES.
    @Test("A real refusal carries its POSIX code")
    func realRefusalsCarryTheirCode() throws {
        let steam = try steamBundle()
        let files = FileManager.default
        defer {
            try? files.setAttributes([.immutable: false, .posixPermissions: 0o755], ofItemAtPath: steam.inside)
            try? files.removeItem(at: steam.root)
        }
        let probe = URL(filePath: steam.inside).appending(path: "probe")

        try files.setAttributes([.immutable: true], ofItemAtPath: steam.inside)
        let locked = try #require(throws: WriteRefused.self) {
            try WriteRefused.catching(probe) { try Data("x".utf8).write(to: probe) }
        }
        #expect(locked.remedy == .appManagement)
        try files.setAttributes([.immutable: false], ofItemAtPath: steam.inside)

        try files.setAttributes([.posixPermissions: 0o555], ofItemAtPath: steam.inside)
        let readOnly = try #require(throws: NSError.self) { try Data("x".utf8).write(to: probe) }
        #expect(WriteRefused.posixCode(of: readOnly) == EACCES)
    }

    @Test("The real lookup reads the owner")
    func realLookup() throws {
        #expect(Remedy.owner(of: "/usr/bin") == 0)
        #expect(Remedy.folder(holding: "/usr/bin/true") == "/usr/bin")
        #expect(Remedy.folder(holding: "/usr/bin") == "/usr/bin")
    }

    @Test("The remedy is fixed when the write is refused")
    func remedyIsTakenAtRefusal() throws {
        let steam = try steamBundle()
        let refusal = WriteRefused(path: steam.inside)
        try FileManager.default.removeItem(at: steam.root)

        #expect(refusal.remedy == .appManagement)
    }

    @Test("The advice names the bundle and a command that hands it over")
    func adviceCarriesTheCommand() {
        let advice = Remedy.rootOwned(handOver: "/Applications/Steam.app").advice

        #expect(advice.contains("/Applications/Steam.app belongs to the system (root)"))
        #expect(advice.contains("sudo chown -R '\(NSUserName())' '/Applications/Steam.app'"))
        #expect(!advice.contains("another account"))
    }

    @Test("The command quotes paths with spaces and apostrophes")
    func commandQuotesThePath() {
        #expect(
            Remedy.chownCommand("/Volumes/Ray's Drive/Steam.app", user: "ray")
                == #"sudo chown -R 'ray' '/Volumes/Ray'\''s Drive/Steam.app'"#
        )
    }

    @Test("Refusals root owns in one bundle keep the command")
    func oneRootBundleKeepsTheCommand() throws {
        let steam = Remedy.rootOwned(handOver: "/Applications/Steam.app")
        let report = try #require(FailureReport([
            WriteRefused(path: "/Applications/Steam.app/Contents/MacOS", remedy: steam),
            WriteRefused(path: "/Applications/Steam.app/Contents/Info.plist", remedy: steam),
        ]))

        #expect(report.remedy == steam)
        #expect(report.message.contains("sudo chown -R"))
    }

    @Test("Refusals root owns in different places still get advice")
    func rootRefusalsInDifferentPlacesShareAdvice() throws {
        let report = try #require(FailureReport([
            WriteRefused(path: "/Applications/Steam.app/Contents/MacOS",
                         remedy: .rootOwned(handOver: "/Applications/Steam.app")),
            WriteRefused(path: "/Library/Shared/np", remedy: .rootOwned(handOver: nil)),
        ]))

        #expect(report.remedy == .rootOwned(handOver: nil))
        #expect(report.message.contains("belongs to the system (root)"))
        #expect(!report.message.contains("chown"))
    }

    @Test("Refusals with different causes share no advice")
    func mixedRefusalsShareNothing() throws {
        let report = try #require(FailureReport([
            WriteRefused(path: "/a", remedy: .rootOwned(handOver: nil)),
            WriteRefused(path: "/b", remedy: .otherAccount),
        ]))

        #expect(report.remedy == nil)
    }

    @Test("Installing into a root-owned Steam says root owns it, not another account")
    func installerNamesRoot() throws {
        let root = Remedy.rootOwned(handOver: "/Applications/Steam.app")

        let unpatched = try #require(SteamInstaller.refusalDetail(root, deployed: false))
        #expect(unpatched == root.advice)

        let mismatch = try #require(SteamInstaller.refusalDetail(root, deployed: true))
        #expect(mismatch.hasPrefix("Steam has a different copy of Ambaplay, and this account cannot update it."))
        #expect(mismatch.hasSuffix(root.advice))

        for detail in [unpatched, mismatch] {
            #expect(!detail.contains("another account"))
            #expect(!detail.contains("account that owns Steam"))
        }
    }

    @Test("Installing into another account's Steam keeps its own messages")
    func installerNamesOtherAccount() throws {
        let unpatched = try #require(SteamInstaller.refusalDetail(.otherAccount, deployed: false))
        let mismatch = try #require(SteamInstaller.refusalDetail(.otherAccount, deployed: true))

        #expect(unpatched.contains("Install from the account that owns Steam"))
        #expect(mismatch.contains("installed by another account"))
        #expect(SteamInstaller.refusalDetail(.appManagement, deployed: false) == nil)
        #expect(SteamInstaller.refusalDetail(.ownership, deployed: true) == nil)
    }

    @Test("The command line gives the app's root advice and keeps its own wording elsewhere")
    func commandLineAdvice() {
        let root = Remedy.rootOwned(handOver: "/Applications/Steam.app")

        #expect(RemoveEverythingCommand.failureMessage(WriteRefused(path: "/x", remedy: root))
            == "Could not write /x. \(root.advice)")
        #expect(RemoveEverythingCommand.failureMessage(WriteRefused(path: "/x", remedy: .appManagement))
            .contains("Allow your terminal app"))
        let other = RemoveEverythingCommand.failureMessage(WriteRefused(path: "/x", remedy: .otherAccount))
        #expect(other.contains("Run this again while logged in to that account"))
        #expect(!other.contains("reinstall"))
    }
}
