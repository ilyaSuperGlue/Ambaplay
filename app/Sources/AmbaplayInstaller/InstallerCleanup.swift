import AppKit
import Foundation
import Darwin

@MainActor
enum InstallerCleanup {
    struct Source: Codable, Equatable {
        let image: URL
        let device: String
        let inode: UInt64
        let filesystem: Int32
    }

    static func source() throws -> Source? {
        guard let executable = Bundle.main.executableURL else { return nil }
        return try source(containing: executable, info: diskImages())
    }

    static func source(containing executable: URL, info: Data) throws -> Source? {
        let plist = try PropertyListSerialization.propertyList(from: info, format: nil)
        guard let images = (plist as? [String: Any])?["images"] as? [[String: Any]] else { return nil }
        let executablePath = executable.resolvingSymlinksInPath().path
        for item in images {
            guard let path = item["image-path"] as? String,
                  let entities = item["system-entities"] as? [[String: Any]] else { continue }
            for entity in entities {
                guard let mount = entity["mount-point"] as? String,
                      let device = entity["dev-entry"] as? String,
                      mount != "/", executablePath.hasPrefix(mount + "/"),
                      device.range(of: #"^/dev/disk[0-9]+(s[0-9]+)*$"#, options: .regularExpression) != nil else { continue }
                let image = URL(fileURLWithPath: path)
                guard image.pathExtension.lowercased() == "dmg", let identity = identity(image) else { continue }
                return Source(image: image, device: device, inode: identity.st_ino, filesystem: identity.st_dev)
            }
        }
        return nil
    }

    static func schedule(_ source: Source) throws {
        guard let executable = Bundle.main.executableURL,
              let current = try self.source(), current == source else {
            throw CocoaError(.fileReadUnknown)
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ambaplay-cleanup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let helper = folder.appendingPathComponent("AmbaplayCleanup")
            try FileManager.default.copyItem(at: executable, to: helper)
            let resources = InstallerResources.bundle.bundleURL
            try FileManager.default.copyItem(at: resources, to: folder.appendingPathComponent(resources.lastPathComponent))
            let process = Process()
            process.currentDirectoryURL = folder
            process.executableURL = helper
            process.arguments = ["--cleanup", try JSONEncoder().encode(source).base64EncodedString(), String(getpid())]
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard args.count > 1, args[1] == "--cleanup" else { return false }
        guard args.count == 4, args[2].count < 16_384,
              let bytes = Data(base64Encoded: args[2]),
              let source = try? JSONDecoder().decode(Source.self, from: bytes),
              let parent = Int32(args[3]), parent > 1 else { return true }
        let ownDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
        defer {
            if let ownDirectory,
               ownDirectory.lastPathComponent.hasPrefix("ambaplay-cleanup-"),
               ownDirectory.deletingLastPathComponent().standardizedFileURL == FileManager.default.temporaryDirectory.standardizedFileURL {
                try? FileManager.default.removeItem(at: ownDirectory)
            }
        }
        do {
            for _ in 0..<300 {
                if kill(parent, 0) != 0 { break }
                Thread.sleep(forTimeInterval: 0.2)
            }
            guard kill(parent, 0) != 0 else { throw CocoaError(.fileWriteFileExists) }
            guard let before = identity(source.image), before.st_ino == source.inode,
                  before.st_dev == source.filesystem else { throw CocoaError(.fileReadUnknown) }
            let info = try diskImages()
            guard mounted(source, info: info) else { throw CocoaError(.fileReadUnknown) }
            try run("/usr/bin/hdiutil", ["detach", source.device])
            guard let after = identity(source.image), after.st_ino == source.inode,
                  after.st_dev == source.filesystem else { throw CocoaError(.fileReadUnknown) }
            try FileManager.default.trashItem(at: source.image, resultingItemURL: nil)
        } catch {
            _ = NSApplication.shared
            let alert = NSAlert()
            alert.messageText = tr("Installer cleanup could not finish")
            alert.informativeText = tr("Ambaplay is installed. You can eject the installer and move its DMG to Trash in Finder.") + "\n\n" + error.localizedDescription
            alert.addButton(withTitle: tr("OK"))
            alert.runModal()
        }
        return true
    }

    private static func mounted(_ source: Source, info: Data) -> Bool {
        guard let plist = try? PropertyListSerialization.propertyList(from: info, format: nil),
              let images = (plist as? [String: Any])?["images"] as? [[String: Any]] else { return false }
        return images.contains { item in
            guard let path = item["image-path"] as? String,
                  URL(fileURLWithPath: path) == source.image,
                  let entities = item["system-entities"] as? [[String: Any]] else { return false }
            return entities.contains { ($0["dev-entry"] as? String) == source.device && $0["mount-point"] != nil }
        }
    }

    private static func identity(_ url: URL) -> stat? {
        var info = stat()
        guard url.isFileURL, url.pathExtension.lowercased() == "dmg",
              lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        return info
    }

    private static func diskImages() throws -> Data { try run("/usr/bin/hdiutil", ["info", "-plist"]) }

    @discardableResult
    private static func run(_ executable: String, _ args: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}
