import Foundation
import Testing

@testable import AmbaplayApp

@Suite("Local signing identity")
struct LocalSigningTests {

    // What `security find-identity -p codesigning` printed on a Mac carrying the identity,
    // untrusted, next to another one.
    private static let listing = """

    Policy: Code Signing
      Matching identities
      1) 1111111111111111111111111111111111111111 "Apple Development: someone@example.com (ABCDE12345)"
      2) E9B6B93497770DB40F9E30E511810EC68B9D4D93 "NotProton Local Signing" (CSSMERR_TP_NOT_TRUSTED)
         2 identities found

      Valid identities only
      1) 1111111111111111111111111111111111111111 "Apple Development: someone@example.com (ABCDE12345)"
         1 valid identities found
    """

    // Records every command and answers find-identity from a script of listings.
    private final class FakeSecurity: @unchecked Sendable {
        private let lock = NSLock()
        private var listings: [String]
        private(set) var commands: [[String]] = []
        var failing: String?

        init(listings: [String]) { self.listings = listings }

        var runner: LocalSigning.Runner {
            { executable, arguments in
                self.lock.lock(); defer { self.lock.unlock() }
                self.commands.append([executable] + arguments)
                if arguments.first == "find-identity" {
                    let next = self.listings.count > 1 ? self.listings.removeFirst() : (self.listings.first ?? "")
                    return CommandResult(status: 0, stdout: next, stderr: "")
                }
                if let failing = self.failing, arguments.first == failing {
                    return CommandResult(status: 1, stdout: "", stderr: "refused")
                }
                return CommandResult(status: 0, stdout: "", stderr: "")
            }
        }

        var created: [[String]] { commands.filter { $0[1] != "find-identity" } }
    }

    @Test("The identity is found by name even when macOS does not trust it")
    func findsUntrustedIdentity() {
        #expect(LocalSigning.identityHash(in: Self.listing) == "E9B6B93497770DB40F9E30E511810EC68B9D4D93")
        #expect(LocalSigning.identityHash(in: Self.listing, named: "Someone Else") == nil)
        #expect(LocalSigning.identityHash(in: "\n     0 valid identities found\n") == nil)
    }

    @Test("The installer keeps signing with the same name")
    func keepsTheExistingName() {
        #expect(LocalSigning.name == "NotProton Local Signing")
        #expect(SteamInstaller.localSigningIdentity == LocalSigning.name)
    }

    @Test("An existing identity is kept and nothing is created")
    func idempotent() throws {
        let fake = FakeSecurity(listings: [Self.listing])
        let outcome = try LocalSigning.ensure(run: fake.runner)
        #expect(outcome == .alreadyPresent(hash: "E9B6B93497770DB40F9E30E511810EC68B9D4D93"))
        #expect(fake.created.isEmpty)
        #expect(fake.commands == [["/usr/bin/security", "find-identity", "-p", "codesigning"]])
    }

    @Test("A missing identity is made with openssl and imported for codesign only")
    func createsWhenMissing() throws {
        let temporary = FileManager.default.temporaryDirectory.appending(path: "signing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let keychain = URL(filePath: "/tmp/test.keychain-db")
        let fake = FakeSecurity(listings: ["  0 identities found\n", Self.listing])

        let outcome = try LocalSigning.ensure(keychain: keychain, run: fake.runner, temporaryRoot: temporary)

        #expect(outcome == .created(hash: "E9B6B93497770DB40F9E30E511810EC68B9D4D93"))
        let created = fake.created
        #expect(created.map { $0[0] } == ["/usr/bin/openssl", "/usr/bin/openssl", "/usr/bin/security"])
        let request = created[0]
        #expect(request.contains("/CN=NotProton Local Signing"))
        #expect(request.contains("extendedKeyUsage=critical,codeSigning"))
        let importing = created[2]
        #expect(importing[1] == "import")
        #expect(importing.contains(keychain.path(percentEncoded: false)))
        #expect(importing.firstIndex(of: "-T").map { importing[$0 + 1] } == "/usr/bin/codesign")
        // Neither asks for a password: no trust settings change, no partition list.
        #expect(!fake.commands.joined().contains("add-trusted-cert"))
        #expect(!fake.commands.joined().contains("set-key-partition-list"))
        // The private key never outlives the call.
        #expect(try FileManager.default.contentsOfDirectory(atPath: temporary.path(percentEncoded: false)).isEmpty)
    }

    @Test("The PKCS#12 password matches between export and import")
    func transportPasswordMatches() {
        let commands = LocalSigning.creationCommands(work: URL(filePath: "/w"), keychain: URL(filePath: "/k"), transportPassword: "secret")
        #expect(commands[1].arguments.contains("pass:secret"))
        #expect(commands[2].arguments.firstIndex(of: "-P").map { commands[2].arguments[$0 + 1] } == "secret")
    }

    @Test("A refused import is reported and leaves no key behind")
    func refusedImport() throws {
        let temporary = FileManager.default.temporaryDirectory.appending(path: "signing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let fake = FakeSecurity(listings: [""])
        fake.failing = "import"

        #expect(throws: StepFailure.self) { try LocalSigning.ensure(run: fake.runner, temporaryRoot: temporary) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: temporary.path(percentEncoded: false)).isEmpty)
    }

    // Uses the real tools against a throwaway keychain file (not added to the search list)
    // and signs a copy of /bin/echo with the result: proves the identity is usable by
    // codesign without a prompt. Off by default because a prompt would hang the run.
    @Test("A real identity in a throwaway keychain signs without a prompt",
          .enabled(if: ProcessInfo.processInfo.environment["NOTPROTON_KEYCHAIN_TEST"] != nil))
    func realKeychain() throws {
        let work = FileManager.default.temporaryDirectory.appending(path: "signing-real-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let keychain = work.appending(path: "test.keychain-db")
        let path = keychain.path(percentEncoded: false)
        try Shell.check("/usr/bin/security", ["create-keychain", "-p", "test", path])
        defer { _ = try? Shell.run("/usr/bin/security", ["delete-keychain", path]) }
        try Shell.check("/usr/bin/security", ["unlock-keychain", "-p", "test", path])

        let first = try LocalSigning.ensure(keychain: keychain, lookIn: [keychain])
        guard case .created(let hash) = first else { Issue.record("expected a new identity, got \(first)"); return }
        #expect(try LocalSigning.ensure(keychain: keychain, lookIn: [keychain]) == .alreadyPresent(hash: hash))

        let binary = work.appending(path: "echo")
        try FileManager.default.copyItem(at: URL(filePath: "/bin/echo"), to: binary)
        try Shell.check("/usr/bin/codesign", ["-f", "-s", hash, "--keychain", path, binary.path(percentEncoded: false)])
        let requirement = try Shell.run("/usr/bin/codesign", ["-d", "-r-", binary.path(percentEncoded: false)])
        #expect((requirement.stdout + requirement.stderr).lowercased().contains("h\"\(hash.lowercased())\""))
    }
}
