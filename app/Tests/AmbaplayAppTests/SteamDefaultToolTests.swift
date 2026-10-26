import Foundation
import Testing

@testable import AmbaplayApp

@Suite("Steam default compatibility tool")
struct SteamDefaultToolTests {

    private static let head = """
        "InstallConfigStore"
        {
        \t"Software"
        \t{
        \t\t"valve"
        \t\t{
        \t\t\t"Steam"
        \t\t\t{
        """
    private static let tail = """
        \t\t\t}
        \t\t}
        \t}
        }
        """

    private static func entry(_ tool: String) -> String {
        """
        \t\t\t\t\t"0"
        \t\t\t\t\t{
        \t\t\t\t\t\t"name"\t\t"\(tool)"
        \t\t\t\t\t\t"config"\t\t""
        \t\t\t\t\t\t"priority"\t\t"75"
        \t\t\t\t\t}
        """
    }

    @Test("Adds CompatToolMapping with the default when Steam has none")
    func addsMapping() throws {
        let text = Self.head + "\n\t\t\t\t\"SentryFile\"\t\t\"x\"\n" + Self.tail
        let result = try #require(SteamDefaultTool.updated(text, tool: "ambaplay-proton-winecx-11.17"))
        #expect(result == Self.head + "\n\t\t\t\t\"CompatToolMapping\"\n\t\t\t\t{\n" + Self.entry("ambaplay-proton-winecx-11.17")
            + "\n\t\t\t\t}\n\t\t\t\t\"SentryFile\"\t\t\"x\"\n" + Self.tail)
    }

    @Test("Adds the default beside per-app mappings and keeps them")
    func keepsAppMappings() throws {
        let app = "\t\t\t\t\t\"3764200\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"name\"\t\t\"other\"\n\t\t\t\t\t}"
        let text = Self.head + "\n\t\t\t\t\"CompatToolMapping\"\n\t\t\t\t{\n" + app + "\n\t\t\t\t}\n" + Self.tail
        let result = try #require(SteamDefaultTool.updated(text, tool: "t"))
        #expect(result == Self.head + "\n\t\t\t\t\"CompatToolMapping\"\n\t\t\t\t{\n" + Self.entry("t") + "\n" + app
            + "\n\t\t\t\t}\n" + Self.tail)
    }

    @Test("Replaces an existing default and is idempotent")
    func replacesDefault() throws {
        let text = Self.head + "\n\t\t\t\t\"CompatToolMapping\"\n\t\t\t\t{\n" + Self.entry("old") + "\n\t\t\t\t}\n" + Self.tail
        let once = try #require(SteamDefaultTool.updated(text, tool: "new"))
        #expect(once == Self.head + "\n\t\t\t\t\"CompatToolMapping\"\n\t\t\t\t{\n" + Self.entry("new") + "\n\t\t\t\t}\n" + Self.tail)
        #expect(SteamDefaultTool.updated(once, tool: "new") == once)
    }

    @Test("Refuses a file without a Valve > Steam section")
    func refusesUnknownLayout() {
        #expect(SteamDefaultTool.updated("\"InstallConfigStore\"\n{\n}\n", tool: "t") == nil)
    }

    // MARK: Writing, backing up and restoring

    private static func config(_ entry: String?) -> String {
        Self.head + "\n\t\t\t\t\"CompatToolMapping\"\n\t\t\t\t{\n" + (entry.map { $0 + "\n" } ?? "") + "\t\t\t\t}\n" + Self.tail
    }

    private func files(_ text: String) throws -> (dir: URL, config: URL, backup: URL) {
        let dir = try scratchDirectory("default-tool")
        let config = dir.appending(path: "config.vdf")
        try Data(text.utf8).write(to: config)
        return (dir, config, dir.appending(path: "backups/steam-default-tool.json"))
    }

    private func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    @Test("Nothing is written while Steam runs, since Steam rewrites the file when it quits")
    func refusesWhileSteamRuns() throws {
        let f = try files(Self.config(Self.entry("GE-Proton9-1")))
        defer { try? FileManager.default.removeItem(at: f.dir) }

        #expect(throws: SteamDefaultTool.SteamRunning.self) {
            try SteamDefaultTool.set("ambaplay-proton-winecx-11.17", in: f.config, backup: f.backup, steamRunning: { true })
        }
        #expect(try read(f.config) == Self.config(Self.entry("GE-Proton9-1")))
        #expect(!FileManager.default.fileExists(atPath: f.backup.path))
    }

    @Test("The user's own default is backed up and comes back on restore")
    func backsUpAndRestoresTheUsersDefault() throws {
        let original = Self.config(Self.entry("GE-Proton9-1"))
        let f = try files(original)
        defer { try? FileManager.default.removeItem(at: f.dir) }

        try SteamDefaultTool.set("ambaplay-proton-winecx-11.17", in: f.config, backup: f.backup, steamRunning: { false })
        #expect(try read(f.config) == Self.config(Self.entry("ambaplay-proton-winecx-11.17")))
        // Setting another of ours keeps the backup of the user's choice, not of ours.
        try SteamDefaultTool.set("ambaplay-proton-winecx-11.18", in: f.config, backup: f.backup, steamRunning: { false })

        #expect(try SteamDefaultTool.restore(in: f.config, backup: f.backup, steamRunning: { false }))
        #expect(try read(f.config) == original)
    }

    @Test("A default that was not there is removed again on restore")
    func restoreRemovesADefaultThatWasNotThere() throws {
        let original = Self.config(nil)
        let f = try files(original)
        defer { try? FileManager.default.removeItem(at: f.dir) }

        try SteamDefaultTool.set("ambaplay-proton", in: f.config, backup: f.backup, steamRunning: { false })
        #expect(try SteamDefaultTool.restore(in: f.config, backup: f.backup, steamRunning: { false }))
        #expect(try read(f.config) == original)
    }

    @Test("Without a backup, a default naming one of our tools is removed")
    func restoreWithoutBackupRemovesOurs() throws {
        let f = try files(Self.config(Self.entry("notproton-winecx-11.17")))
        defer { try? FileManager.default.removeItem(at: f.dir) }

        #expect(try SteamDefaultTool.restore(in: f.config, backup: f.backup, steamRunning: { false }))
        #expect(try read(f.config) == Self.config(nil))
    }

    @Test("A default the user chose since is left alone")
    func restoreLeavesTheUsersNewChoice() throws {
        let f = try files(Self.config(Self.entry("GE-Proton9-1")))
        defer { try? FileManager.default.removeItem(at: f.dir) }
        try FileManager.default.createDirectory(at: f.backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(SteamDefaultTool.Backup(previous: nil)).write(to: f.backup)

        // Steam running does not matter when there is nothing to put back.
        #expect(try SteamDefaultTool.restore(in: f.config, backup: f.backup, steamRunning: { true }) == false)
        #expect(try read(f.config) == Self.config(Self.entry("GE-Proton9-1")))
    }

    @Test("The default entry is read with its fields")
    func readsTheDefault() {
        #expect(SteamDefaultTool.current(in: Self.config(Self.entry("t")))
            == SteamDefaultTool.Mapping(name: "t", config: "", priority: "75"))
        #expect(SteamDefaultTool.current(in: Self.config(nil)) == nil)
    }
}

@Suite("Steam per-game tool entries")
struct SteamGameEntriesTests {
    private static func game(_ id: String, _ tool: String) -> String {
        "\t\t\t\t\t\"\(id)\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"name\"\t\t\"\(tool)\"\n\t\t\t\t\t\t\"config\"\t\t\"\"\n\t\t\t\t\t\t\"priority\"\t\t\"250\"\n\t\t\t\t\t}"
    }

    private static func vdf(_ entries: [String]) -> String {
        (["\"InstallConfigStore\"", "{", "\t\"Software\"", "\t{", "\t\t\"valve\"", "\t\t{", "\t\t\t\"Steam\"", "\t\t\t{",
         "\t\t\t\t\"CompatToolMapping\"", "\t\t\t\t{"]
            + entries + ["\t\t\t\t}", "\t\t\t}", "\t\t}", "\t}", "}"])
            .joined(separator: "\n")
    }

    @Test("Removes Ambaplay and legacy entries, keeps the rest")
    func removesOurs() throws {
        let text = Self.vdf([
            Self.game("0", "ambaplay-proton-winecx-11.17"), Self.game("10", "ambaplay-proton-winecx-11.17"),
            Self.game("20", "proton_9"), Self.game("30", "notproton-winecx-11.17"),
        ])
        let result = try #require(SteamDefaultTool.removingOurGameEntries(text))
        #expect(result == Self.vdf([Self.game("0", "ambaplay-proton-winecx-11.17"), Self.game("20", "proton_9")]))
    }

    @Test("Returns nil when no entry is ours")
    func nothingToRemove() {
        #expect(SteamDefaultTool.removingOurGameEntries(Self.vdf([Self.game("20", "proton_9")])) == nil)
        #expect(SteamDefaultTool.removingOurGameEntries(Self.vdf([Self.game("0", "ambaplay-proton")])) == nil)
    }

    @Test("Leaves the file untouched when nothing matches, and refuses while Steam runs")
    func fileHandling() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "bp-gameentries-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "config.vdf")
        let other = Self.vdf([Self.game("20", "proton_9")])
        try other.write(to: file, atomically: true, encoding: .utf8)
        #expect(try SteamDefaultTool.removeGameEntries(in: file, steamRunning: { true }) == false)
        #expect(try String(contentsOf: file, encoding: .utf8) == other)

        try Self.vdf([Self.game("10", "ambaplay-proton-x")]).write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: SteamDefaultTool.SteamRunning.self) {
            try SteamDefaultTool.removeGameEntries(in: file, steamRunning: { true })
        }
        #expect(try SteamDefaultTool.removeGameEntries(in: file, steamRunning: { false }))
        #expect(try String(contentsOf: file, encoding: .utf8) == Self.vdf([]))
    }
}
