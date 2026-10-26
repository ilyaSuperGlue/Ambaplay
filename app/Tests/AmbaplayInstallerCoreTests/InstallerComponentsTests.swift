import Foundation
import CryptoKit
import Testing
@testable import AmbaplayInstallerCore

@Suite("Installer components")
struct InstallerComponentsTests {
    private let key = Curve25519.Signing.PrivateKey()

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "components-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func signed(_ data: Data) throws -> InstallerComponents {
        let signature = try key.signature(for: data).base64EncodedString()
        return try InstallerComponents(signatureFile: "\(signature) \(data.count)\n",
                                       verificationKey: key.publicKey.rawRepresentation)
    }

    @Test("The signature file is a base64 EdDSA signature and a length")
    func parse() throws {
        let signature = Data(repeating: 7, count: 64).base64EncodedString()
        #expect(try InstallerComponents(signatureFile: "\(signature) 504399923").length == 504_399_923)
        for bad in ["", signature, "\(signature) 0", "\(signature) -5", "\(signature) 12a", "AAAA 10",
                    "\(signature) 10 extra", "\(signature) 99999999999"] {
            #expect(throws: InstallerError.self) { try InstallerComponents(signatureFile: bad) }
        }
    }

    @Test("Only an archive signed by the key, at the signed length, passes")
    func verify() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let payload = Data("components".utf8)
        let archive = dir.appending(path: "Ambaplay-Installer.zip")
        try payload.write(to: archive)
        try signed(payload).verify(archive)

        try Data("tampered!!".utf8).write(to: archive)
        #expect(throws: InstallerError.self) { try signed(payload).verify(archive) }
        try Data("longer components".utf8).write(to: archive)
        #expect(throws: InstallerError.self) { try signed(payload).verify(archive) }
    }

    @Test("Needed without GPTK in either support folder, or without Steam")
    func needed() throws {
        let home = try scratch(), apps = try scratch()
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: apps) }
        #expect(InstallerComponents.needed(home: home, applications: apps))
        try FileManager.default.createDirectory(at: apps.appending(path: "Steam.app"), withIntermediateDirectories: true)
        #expect(InstallerComponents.needed(home: home, applications: apps))
        let legacy = home.appending(path: "Library/Application Support/notproton/gptk")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        #expect(!InstallerComponents.needed(home: home, applications: apps))
        try FileManager.default.removeItem(at: apps.appending(path: "Steam.app"))
        #expect(InstallerComponents.needed(home: home, applications: apps))
    }

    @Test("A failing Install.command reports its last message")
    func scriptFailure() throws {
        #expect(throws: InstallerError.self) {
            try InstallerComponents.run("/bin/sh", ["-c", "echo '==> step'; echo 'Gagal: disk full' >&2; exit 1"])
        }
        let output = try InstallerComponents.run("/bin/sh", ["-c", "printf '==> one\\n==> two\\n'"])
        #expect(output == "==> one\n==> two\n")
    }
}
