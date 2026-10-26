import Foundation

// The few settings the Setup Assistant and the Status page offer for every game. They live
// in the user's gamefixes/default.conf, the lowest layer the run script reads (launch
// options, then <appid>.conf, then the shipped per-game defaults all win over it). Only the
// lines for these keys are rewritten: every other line, comment or setting the user wrote
// stays as it is. A setting that is off is removed rather than written as 0, so the engine's
// own default applies.
enum GameDefaults {

    enum Setting: CaseIterable, Sendable {
        case metalHUD
        case highResolution

        // The first spelling is the one written; the others are read and replaced.
        var keys: [String] {
            switch self {
            case .metalHUD: ["MTL_HUD_ENABLED"]
            case .highResolution: ["RETINA", "AMBAPLAY_RETINA"]
            }
        }
    }

    static var file: URL { SupportPaths.gamefixes.appending(path: "default.conf") }

    static let header = "# Settings for every game. Per-game confs and Steam launch options win over these."

    // Last assignment wins, as in the run script.
    static func isOn(_ setting: Setting, in text: String) -> Bool {
        var on = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let (key, value) = assignment(line), setting.keys.contains(key) else { continue }
            on = value == "1"
        }
        return on
    }

    static func setting(_ setting: Setting, to on: Bool, in text: String) -> String {
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        lines.removeAll { line in assignment(Substring(line)).map { setting.keys.contains($0.0) } ?? false }
        if on {
            if lines.isEmpty { lines.append(header) }
            lines.append("\(setting.keys[0])=1")
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    static func isOn(_ setting: Setting, at url: URL = file) -> Bool {
        isOn(setting, in: (try? String(contentsOf: url, encoding: .utf8)) ?? "")
    }

    static func set(_ setting: Setting, to on: Bool, at url: URL = file) throws {
        let current = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let updated = Self.setting(setting, to: on, in: current)
        guard updated != current else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(updated.utf8).write(to: url, options: .atomic)
        AppLog.note("game defaults: \(setting.keys[0]) \(on ? "on" : "off")")
    }

    // KEY=VALUE with surrounding whitespace trimmed, as the run script reads it.
    private static func assignment(_ line: Substring) -> (String, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let equals = trimmed.firstIndex(of: "="), !trimmed.hasPrefix("#") else { return nil }
        return (String(trimmed[..<equals]), String(trimmed[trimmed.index(after: equals)...]))
    }
}
