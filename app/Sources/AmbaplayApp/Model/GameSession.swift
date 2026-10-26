import Foundation

// The last game session in a prefix's ambaplay-run.log. compat_run.sh starts each run
// with "=== ambaplay run <date> ===" and ends a game with "=== game exited status=N";
// the log is only written to while the game runs, so its modification date is the end.
struct GameSession: Equatable, Sendable {
    let id: String
    let started: Date?
    let ended: Date
    let exitStatus: Int
    // Steam's Exit Game or the client quitting: a normal end, whatever the exit status.
    let stoppedBySteam: Bool
    // Asked for from the Prefixes page with no finished session in the log.
    var byHand = false

    var seconds: Int? { started.map { max(0, Int(ended.timeIntervalSince($0))) } }

    static func last(in log: String, modified: Date) -> GameSession? {
        let headers = ["=== ambaplay run ", "=== notproton run "]
        let starts = headers.compactMap { header -> String.Index? in
            if let found = log.range(of: "\n" + header, options: .backwards) { return log.index(after: found.lowerBound) }
            return log.hasPrefix(header) ? log.startIndex : nil
        }
        guard let start = starts.max() else { return nil }
        let block = log[start...]
        let header = block.prefix { $0 != "\n" }
        guard let exited = block.range(of: "=== game exited status=", options: .backwards) else { return nil }
        let status = Int(block[exited.upperBound...].prefix { $0.isNumber }) ?? 0
        let date = header.range(of: " run ").map { header[$0.upperBound...] } ?? ""
        let started = startDate(String(date.hasSuffix(" ===") ? date.dropLast(4) : date))
        return GameSession(id: String(header), started: started, ended: modified, exitStatus: status,
                           stoppedBySteam: block.contains("=== termination signal received"))
    }

    // `date` output, "Wed Oct 21 14:03:22 WIB 2026". Zone abbreviations don't parse reliably,
    // so the zone is dropped and the time read as local: the game ran on this Mac.
    static func startDate(_ text: String) -> Date? {
        var parts = text.split(separator: " ")
        if parts.count == 6 { parts.remove(at: 4) }
        guard parts.count == 5 else { return nil }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = .current
        format.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return format.date(from: parts.joined(separator: " "))
    }

    // Wine prints these when a game dies on an exception it didn't handle.
    static func wineCrashed(_ wineLog: String?) -> Bool {
        guard let wineLog else { return false }
        return wineLog.contains("Unhandled exception") || wineLog.contains("Unhandled page fault")
    }

    func crashed(wineLog: String?) -> Bool {
        (exitStatus != 0 && !stoppedBySteam) || Self.wineCrashed(wineLog)
    }

    // What auto-share reports without asking: a crash within three minutes doesn't run, half
    // an hour that ends cleanly is playable. Anything else waits for the player's answer.
    func inferredStatus(wineLog: String?) -> ReportStatus? {
        guard let seconds else { return nil }
        let crashed = crashed(wineLog: wineLog)
        if crashed, seconds < 180 { return .borked }
        if !crashed, seconds >= 1800 { return .silver }
        return nil
    }

    // Worth asking about: ended in the last three days. A game that quits cleanly within a
    // minute often showed an error dialog first (SteamAPI_Init failed), so it is asked too.
    func worthAsking(now: Date = Date(), wineLog: String?) -> Bool {
        guard now.timeIntervalSince(ended) < 3 * 86400 else { return false }
        return (seconds ?? 60) >= 60 || exitStatus == 0 || crashed(wineLog: wineLog)
    }

    static func byHand(now: Date = Date()) -> GameSession {
        GameSession(id: "by hand", started: nil, ended: now, exitStatus: 0, stoppedBySteam: false, byHand: true)
    }

    // compat_run.sh's account of how this session ended, from its run block:
    //   === exit summary: exit status 3 after 75s, the game quit by itself (abort() …) ===
    //   === exit cause: wine: Unhandled page fault on read access to … ===
    func exitAccount(in log: String) -> (summary: String, cause: String?)? {
        guard !byHand, id.hasPrefix("=== "), let start = log.range(of: id, options: .backwards)?.lowerBound else { return nil }
        var block = log[start...]
        let rest = block.dropFirst(id.count)
        if let end = ["\n=== ambaplay run ", "\n=== notproton run "].compactMap({ rest.range(of: $0)?.lowerBound }).min() {
            block = block[..<end]
        }
        func line(_ tag: String) -> String? {
            guard let found = block.range(of: "\n=== \(tag): ") else { return nil }
            let text = block[found.upperBound...].prefix { $0 != "\n" }
            return String(text.hasSuffix(" ===") ? text.dropLast(4) : text)
        }
        guard let summary = line("exit summary") else { return nil }
        return (summary: summary, cause: line("exit cause"))
    }

    // English on purpose: it goes into the public report. The exit summary and Wine's first
    // error line say why the game quit; logs from before the summary give the bare status.
    func summary(log: String? = nil, wineLog: String?) -> String {
        if byHand { return "Reported from the Prefixes page" }
        var parts: [String] = []
        if let seconds { parts.append("Session \(seconds / 60) min") }
        // The run script already searched the whole Wine log for the cause.
        let cause: String?
        if let account = log.flatMap({ exitAccount(in: $0) }) {
            parts.append(account.summary)
            cause = account.cause
        } else {
            parts.append(stoppedBySteam ? "stopped from Steam" : "exit status \(exitStatus)")
            cause = wineLog.flatMap { GameReport.wineErrorLines(in: $0[...], limit: 1).first }
        }
        if let cause {
            parts.append("first Wine error: \(GameReport.redacted(cause))")
        } else if Self.wineCrashed(wineLog) {
            parts.append("Wine reported an unhandled exception")
        }
        return parts.joined(separator: ", ")
    }
}

// Must match STATUS in ambaplay-web/api/report.mjs.
enum ReportStatus: String, Codable, Sendable {
    case platinum, gold, silver, bronze, borked
}

// The main problem behind a Has Issues answer. Must match ISSUES in ambaplay-web's
// api/_lib/github.mjs; performance lets the site tell a slow Mac from a Ambaplay bug.
enum ReportIssue: String, Codable, Sendable, CaseIterable {
    case performance, crash, graphics, sound, controls, launcher
}
