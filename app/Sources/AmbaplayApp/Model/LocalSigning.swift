import Foundation

// Creates the self-signed code signing identity that SteamInstaller signs Steam with, so
// Steam's designated requirement (and with it the Input Monitoring approval macOS keys to
// it) stays the same across Ambaplay updates. Without it Steam is signed ad hoc, the
// requirement is the cdhash, and every update makes macOS forget the controller approval.
//
// Design, checked on macOS 27 with a throwaway keychain:
// - The key and certificate come from /usr/bin/openssl (LibreSSL 3.3.6 accepts -addext)
//   and go in through `security import -T /usr/bin/codesign`. The key's access list then
//   names codesign, so signing never shows a keychain prompt. A key made with
//   SecKeyCreateRandomKey inside this app would instead belong to this app's own
//   signature, which changes with every ad hoc Ambaplay build, and codesign would ask.
// - Nothing calls `security set-key-partition-list`: it needs the keychain password, and
//   the import above already leaves codesign able to use the key without asking.
// - The certificate is NOT marked trusted (`security add-trusted-cert`). codesign signs
//   with an untrusted identity just as well; the designated requirement is then
//   `certificate leaf = H"<sha1>"`, which is what the owner's existing identity produces.
//   Trusting it would cost a password prompt and could change that requirement's form
//   (leaf to root), which would make macOS drop the approval once more.
// - The name stays "NotProton Local Signing": existing installs look it up by that name.
enum LocalSigning {

    static let name = SteamInstaller.localSigningIdentity
    static let step = String(localized: "Trust Ambaplay on this Mac")

    typealias Runner = @Sendable (String, [String]) throws -> CommandResult

    static let realRunner: Runner = { try Shell.run($0, $1) }

    static var loginKeychain: URL {
        SupportPaths.home.appending(path: "Library/Keychains/login.keychain-db")
    }

    enum Outcome: Equatable, Sendable {
        case alreadyPresent(hash: String)
        case created(hash: String)
    }

    // `security find-identity -p codesigning` without -v, so an untrusted identity, which
    // is what this creates, still counts. Each line reads `  1) <SHA-1> "<name>" (...)`.
    static func identityHash(in output: String, named wanted: String = name) -> String? {
        for line in output.split(separator: "\n") where line.contains("\"\(wanted)\"") {
            let fields = line.split(separator: " ")
            if let hash = fields.first(where: { $0.count == 40 && $0.allSatisfy(\.isHexDigit) }) {
                return String(hash)
            }
        }
        return nil
    }

    // Looks in the given keychains, or in the user's search list when none are given.
    static func existingHash(in keychains: [URL] = [], run: Runner = realRunner) -> String? {
        let arguments = ["find-identity", "-p", "codesigning"] + keychains.map { $0.path(percentEncoded: false) }
        guard let result = try? run("/usr/bin/security", arguments), result.succeeded else { return nil }
        return identityHash(in: result.stdout)
    }

    struct Command: Equatable, Sendable {
        let executable: String
        let arguments: [String]
    }

    // The commands that make the identity, in order. The key only ever exists in `work`,
    // which ensure() creates private to this user and removes afterwards.
    static func creationCommands(work: URL, keychain: URL, transportPassword: String) -> [Command] {
        let key = work.appending(path: "key.pem").path(percentEncoded: false)
        let cert = work.appending(path: "cert.pem").path(percentEncoded: false)
        let bundle = work.appending(path: "identity.p12").path(percentEncoded: false)
        return [
            Command(executable: "/usr/bin/openssl", arguments: [
                "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "7300",
                "-subj", "/CN=\(name)",
                "-addext", "extendedKeyUsage=critical,codeSigning",
                "-addext", "keyUsage=critical,digitalSignature",
                "-addext", "basicConstraints=critical,CA:false",
                "-keyout", key, "-out", cert,
            ]),
            // security import refuses a PKCS#12 with an empty password, so the bundle gets a
            // random one that lives only as long as the file.
            Command(executable: "/usr/bin/openssl", arguments: [
                "pkcs12", "-export", "-inkey", key, "-in", cert, "-name", name,
                "-out", bundle, "-passout", "pass:\(transportPassword)",
            ]),
            Command(executable: "/usr/bin/security", arguments: [
                "import", bundle, "-k", keychain.path(percentEncoded: false), "-f", "pkcs12",
                "-P", transportPassword, "-T", "/usr/bin/codesign",
            ]),
        ]
    }

    // Creates the identity unless one with this name is already there. Never asks for a
    // password, except macOS's own prompt to unlock a locked login keychain.
    static func ensure(
        keychain: URL = loginKeychain,
        lookIn: [URL] = [],
        run: Runner = realRunner,
        temporaryRoot: URL = FileManager.default.temporaryDirectory
    ) throws -> Outcome {
        if let hash = existingHash(in: lookIn, run: run) {
            return .alreadyPresent(hash: hash)
        }
        let files = FileManager.default
        let work = temporaryRoot.appending(path: "ambaplay-signing-\(UUID().uuidString)", directoryHint: .isDirectory)
        try files.createDirectory(at: work, withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: work) }

        let password = UUID().uuidString
        for command in creationCommands(work: work, keychain: keychain, transportPassword: password) {
            let result = try run(command.executable, command.arguments)
            guard result.succeeded else {
                let tool = (command.executable as NSString).lastPathComponent
                AppLog.note("signing: \(tool) \(command.arguments.first ?? "") failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
                throw StepFailure(step: step, detail: String(localized: "macOS did not add the certificate to your keychain."))
            }
        }
        guard let hash = existingHash(in: lookIn, run: run) else {
            throw StepFailure(step: step, detail: String(localized: "The certificate was added, but macOS does not offer it for signing."))
        }
        AppLog.note("signing: created \(name) \(hash)")
        return .created(hash: hash)
    }
}
