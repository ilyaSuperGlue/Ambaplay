// Ambaplay's version as make app stamps it from dylib/version.h

import AppKit
import Foundation

enum ProductVersion {

    // CFBundleShortVersionString: the label people see, X.Y.Z or, in a beta build,
    // X.Y.Z-beta.N (stamped at build time, see scripts/stamp-beta.sh). About, Status and
    // game reports show it; installs and updates are ordered by `build`, never by this.
    static var short: String { AppVersion.display }

    // CFBundleVersion: the release counter Sparkle orders updates by.
    static var build: String? { stamped(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")) }

    // The NotProton release this build is based on.
    static var upstream: String? { stamped(Bundle.main.object(forInfoDictionaryKey: "NotProtonVersion")) }

    enum Channel: String {
        case stable, beta
    }

    // AmbaplayChannel: "beta" in a build stamped by scripts/stamp-beta.sh. A missing,
    // empty or unreadable value means stable.
    static var channel: Channel { channel(from: Bundle.main.object(forInfoDictionaryKey: "AmbaplayChannel")) }

    static func channel(from value: Any?) -> Channel {
        guard let text = value as? String else { return .stable }
        return Channel(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .stable
    }

    static var display: String { display(short: short, build: build, upstream: upstream) }

    // "Ambaplay 2.0.0 (32) · based on NotProton 1.2.0"
    static func display(short: String, build: String?, upstream: String?) -> String {
        var text = "Ambaplay \(short)"
        if let build { text += " (\(build))" }
        if let upstream { text += " · based on NotProton \(upstream)" }
        return text
    }

    // app/Info.plist carries placeholders that only make app replaces.
    private static func stamped(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty, text != "0", text != "0.0.0" else { return nil }
        return text
    }
}

@MainActor
enum AboutPanel {

    // The standard panel already reads "Version 2.0.0 (32)"; the credits name what
    // Ambaplay is built on, point people to CrossOver, which funds Wine, and carry the
    // GPL-3.0 no-warranty notice. The copyright line comes from Info.plist.
    static func show() {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: centered,
        ]
        let lines: [(text: String, link: String?)] = [
            (ProductVersion.upstream.map { "Based on NotProton \($0)" } ?? "Based on NotProton",
             "https://github.com/NotProtonNot/NotProton"),
            (String(localized: "Runs on CodeWeavers' Wine and Apple's Game Porting Toolkit."), nil),
            (String(localized: "Support Wine: buy CrossOver"), "https://www.codeweavers.com/crossover"),
            (String(localized: "Thanks to NotProton's contributors"),
             "https://github.com/NotProtonNot/NotProton/graphs/contributors"),
            (String(localized: "Thanks to everyone who contributed on GitHub"),
             "https://github.com/raymondchins/Ambaplay/graphs/contributors"),
            (String(localized: "Free software under the GPL-3.0, with no warranty."), nil),
            (String(localized: "Read the license"),
             "https://github.com/raymondchins/Ambaplay/blob/main/LICENSE"),
        ]
        let credits = NSMutableAttributedString()
        for line in lines {
            if credits.length > 0 { credits.append(NSAttributedString(string: "\n", attributes: base)) }
            var attributes = base
            if let link = line.link { attributes[.link] = URL(string: link) }
            credits.append(NSAttributedString(string: line.text, attributes: attributes))
        }
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
    }
}
