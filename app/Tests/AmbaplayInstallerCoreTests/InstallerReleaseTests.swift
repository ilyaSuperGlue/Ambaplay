import Foundation
import CryptoKit
import Testing
@testable import AmbaplayInstallerCore

@Suite("Installer release validation")
struct InstallerReleaseTests {
    private let validURL = URL(string: "https://github.com/raymondchins/Ambaplay/releases/download/v3.5.0/Ambaplay.zip")!
    private let signature = Data(repeating: 0xA5, count: 64)

    private func release(
        url: URL? = nil,
        length: Int64 = 1234,
        signature: Data? = nil,
        build: Int = 35,
        version: String = "3.5.0",
        minimumOS: String = "26.0"
    ) throws -> InstallerRelease {
        try InstallerRelease(
            build: build,
            shortVersion: version,
            minimumOS: minimumOS,
            archiveURL: url ?? validURL,
            archiveLength: length,
            signature: signature ?? self.signature
        )
    }

    private func appcast(
        url: String = "https://github.com/raymondchins/Ambaplay/releases/download/v3.5.0/Ambaplay.zip",
        length: String = "1234",
        build: String = "35",
        version: String = "3.5.0",
        minimumOS: String = "26.0",
        signature: String = Data(repeating: 0xA5, count: 64).base64EncodedString(),
        hardware: String? = "arm64"
    ) -> Data {
        let xml = """
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel><item>
            <sparkle:version>\(build)</sparkle:version>
            <sparkle:shortVersionString>\(version)</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>\(minimumOS)</sparkle:minimumSystemVersion>
            \(hardware.map { "<sparkle:hardwareRequirements>\($0)</sparkle:hardwareRequirements>" } ?? "")
            <enclosure url="\(url)" length="\(length)" type="application/octet-stream"
                       sparkle:edSignature="\(signature)" />
          </item></channel>
        </rss>
        """
        return Data(xml.utf8)
    }

    @Test func parsesCurrentFeedFields() throws {
        let value = try InstallerRelease.parse(appcast: appcast())
        #expect(value.build == 35)
        #expect(value.shortVersion == "3.5.0")
        #expect(value.minimumOS == "26.0")
        #expect(value.archiveLength == 1234)
        #expect(value.archiveURL == validURL)
        #expect(value.signature.count == 64)
    }

    @Test(arguments: [
        "http://github.com/raymondchins/Ambaplay/releases/download/v3.5.0/Ambaplay.zip",
        "https://github.com.attacker.invalid/raymondchins/Ambaplay/releases/download/v3.5.0/Ambaplay.zip",
        "https://attacker.invalid/raymondchins/Ambaplay/releases/download/v3.5.0/Ambaplay.zip",
        "https://github.com/raymondchins/Ambaplay/releases/download/v3.5.0/Other.zip",
        "https://user@github.com/raymondchins/Ambaplay/releases/download/v3.5.0/Ambaplay.zip",
        "https://github.com/raymondchins/Ambaplay/releases/download/v3.5.0/Ambaplay.zip?redirect=attacker.invalid",
        "https://github.com:444/raymondchins/Ambaplay/releases/download/v3.5.0/Ambaplay.zip",
    ])
    func rejectsUntrustedArchiveURL(_ input: String) throws {
        let url = try #require(URL(string: input))
        #expect(throws: InstallerError.self) {
            try release(url: url)
        }
    }

    @Test func rejectsInvalidLengthsBuildVersionsAndSignatures() {
        #expect(throws: InstallerError.self) { try release(length: 0) }
        #expect(throws: InstallerError.self) { try release(length: 1_073_741_825) }
        #expect(throws: InstallerError.self) { try release(build: 0) }
        #expect(throws: InstallerError.self) { try release(version: "3.5.release") }
        #expect(throws: InstallerError.self) { try release(minimumOS: "26") }
        #expect(throws: InstallerError.self) { try release(minimumOS: "26.0.1.2") }
        #expect(throws: InstallerError.self) { try release(signature: Data(repeating: 0, count: 63)) }
    }

    @Test func acceptsTwoOrThreeNumericOSVersionComponents() throws {
        #expect(try release(minimumOS: "26.0").minimumOS == "26.0")
        #expect(try release(minimumOS: "26.0.1").minimumOS == "26.0.1")
    }

    @Test func rejectsMalformedOrUnsafeAppcast() {
        #expect(throws: InstallerError.self) { try InstallerRelease.parse(appcast: Data("not XML".utf8)) }
        #expect(throws: InstallerError.self) {
            try InstallerRelease.parse(appcast: Data("<!DOCTYPE rss [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><rss>&x;</rss>".utf8))
        }
        #expect(throws: InstallerError.self) { try InstallerRelease.parse(appcast: appcast(url: "https://evil.example/app.zip")) }
        #expect(throws: InstallerError.self) { try InstallerRelease.parse(appcast: appcast(length: "-1")) }
        #expect(throws: InstallerError.self) { try InstallerRelease.parse(appcast: appcast(build: "35junk")) }
        #expect(throws: InstallerError.self) { try InstallerRelease.parse(appcast: appcast(version: "not-a-version")) }
        #expect(throws: InstallerError.self) { try InstallerRelease.parse(appcast: appcast(minimumOS: "26.0.1.2.3")) }
        #expect(throws: InstallerError.self) { try InstallerRelease.parse(appcast: appcast(signature: "!!!")) }
        #expect(throws: InstallerError.self) { try InstallerRelease.parse(appcast: appcast(hardware: "x86_64")) }
    }

    @Test func requiresAppleSiliconHardwareRequirement() {
        #expect(throws: InstallerError.self) {
            try InstallerRelease.parse(appcast: appcast(hardware: nil))
        }
    }

    @Test func rejectsAppcastURLOutsidePinnedFeed() async {
        let wrong = URL(string: "https://attacker.invalid/releases/latest/download/appcast.xml")!
        await #expect(throws: InstallerError.self) { try await InstallerRelease.latest(from: wrong) }
    }

    @Test(arguments: [
        "https://github.com/raymondchins/Ambaplay/releases/download/appcast.xml",
        "https://github.com:444/raymondchins/Ambaplay/releases/latest/download/appcast.xml",
    ])
    func rejectsUntrustedAppcastPath(_ input: String) async throws {
        let url = try #require(URL(string: input))
        await #expect(throws: InstallerError.self) { try await InstallerRelease.latest(from: url) }
    }

    @Test func rejectsArchiveBytesWithWrongLengthBeforeTrustingSignature() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "archive.zip")
        try Data(repeating: 0, count: 12).write(to: file)
        #expect(throws: InstallerError.self) { try release().verifyArchive(at: file) }
    }

    @Test func rejectsTamperedArchiveUsingPinnedProductionKey() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "archive.zip")
        try Data(repeating: 0x42, count: 1234).write(to: file)
        do {
            try release().verifyArchive(at: file)
            Issue.record("The archive must not pass with an unrelated signature.")
        } catch let error as InstallerError {
            guard case .signatureMismatch = error else {
                Issue.record("Expected signatureMismatch, received \(error).")
                return
            }
        }
    }

    @Test func acceptsBytesSignedByTheCorrespondingTestKeyAndRejectsTampering() throws {
        let key = Curve25519.Signing.PrivateKey()
        let signedBytes = Data("test archive contents".utf8)
        let signature = try key.signature(for: signedBytes)

        try InstallerRelease.verify(signedBytes, signature: signature, publicKey: key.publicKey.rawRepresentation)

        do {
            try InstallerRelease.verify(Data("tampered archive contents".utf8), signature: signature,
                                        publicKey: key.publicKey.rawRepresentation)
            Issue.record("Changing one signed archive must fail signature verification.")
        } catch let error as InstallerError {
            guard case .signatureMismatch = error else {
                Issue.record("Expected signatureMismatch, received \(error).")
                return
            }
        }
    }
}
