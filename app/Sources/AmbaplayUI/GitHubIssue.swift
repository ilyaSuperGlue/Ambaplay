import Foundation

/// A bug report on Ambaplay's GitHub, prefilled from the issue form. The user reviews it
/// and posts it with their own account.
public enum GitHubIssue {
    public static func bugReport(title: String, what: String, version: String, mac: String, logs: String) -> URL? {
        let fields = [
            ("template", "bug-report.yml"),
            ("title", title),
            ("what", what),
            ("version", version),
            ("macos", mac),
            ("logs", logs),
        ]
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let query = fields.compactMap { name, value in
            value.addingPercentEncoding(withAllowedCharacters: allowed).map { "\(name)=\($0)" }
        }.joined(separator: "&")
        return URL(string: "https://github.com/raymondchins/Ambaplay/issues/new?\(query)")
    }

    /// The first line of a failure, short enough for an issue title.
    public static func summary(_ failure: String) -> String {
        String((failure.split(separator: "\n").first.map(String.init) ?? failure).prefix(80))
    }

    /// The last lines of a log, capped so the link stays under GitHub's URL limit.
    public static func tail(of url: URL, lines: Int = 40, maxCharacters: Int = 4000) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        let tail = text.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n")
        return tail.count > maxCharacters ? String(tail.suffix(maxCharacters)) : tail
    }
}
