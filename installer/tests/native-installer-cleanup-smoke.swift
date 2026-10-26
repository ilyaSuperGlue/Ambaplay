import AppKit
import Foundation

func tr(_ value: String.LocalizationValue) -> String { String(localized: value) }
enum InstallerResources { static let bundle = Bundle.main }

@main
struct CleanupSmoke {
    @MainActor
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ambaplay-cleanup-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let image = root.appendingPathComponent("Installer.dmg")
        try Data("test image identity".utf8).write(to: image)
        let executable = URL(fileURLWithPath: "/Volumes/Test Installer/Ambaplay Installer.app/Contents/MacOS/AmbaplayInstaller")
        func info(image: URL, mount: String = "/Volumes/Test Installer", device: String = "/dev/disk123s1") throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: ["images": [
                ["image-path": image.path, "system-entities": [["mount-point": mount, "dev-entry": device]]]
            ]], format: .xml, options: 0)
        }
        var passed = 0
        func expect(_ condition: Bool, _ message: String) throws {
            guard condition else { throw NSError(domain: message, code: 1) }
            passed += 1
            print("PASS \(message)")
        }
        let source = try InstallerCleanup.source(containing: executable, info: info(image: image))
        try expect(source?.image == image, "exact source image from disk metadata")
        try expect(source?.device == "/dev/disk123s1", "exact mounted device")
        let decoy = URL(fileURLWithPath: "/Volumes/Test Installer-other/App")
        try expect(try InstallerCleanup.source(containing: decoy, info: info(image: image)) == nil, "mount prefix boundary")
        try expect(try InstallerCleanup.source(containing: executable, info: info(image: image, device: "/tmp/fake")) == nil, "unsafe device rejected")
        try expect(try InstallerCleanup.source(containing: executable, info: info(image: image, mount: "/")) == nil, "root mount rejected")
        let link = root.appendingPathComponent("link.dmg")
        try fm.createSymbolicLink(at: link, withDestinationURL: image)
        try expect(try InstallerCleanup.source(containing: executable, info: info(image: link)) == nil, "symlink image rejected")
        let other = root.appendingPathComponent("file.txt")
        try Data().write(to: other)
        try expect(try InstallerCleanup.source(containing: executable, info: info(image: other)) == nil, "unrelated source file preserved")
        try expect(try InstallerCleanup.source(containing: executable, info: info(image: root.appendingPathComponent("missing.dmg"))) == nil, "missing source preserved")
        print("Cleanup smoke: \(passed) checks passed; no mounted image or Trash modified.")
    }
}
