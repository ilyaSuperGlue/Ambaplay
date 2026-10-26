import Foundation
import AmbaplayInstallerCore
import AmbaplayUI

enum InstallerReport {
    static func issueURL(failure: String, version: String, installed: String?) -> URL? {
        GitHubIssue.bugReport(
            title: "Installer: \(GitHubIssue.summary(failure))",
            what: "The installer stopped with:\n\n\(failure)",
            version: "Installer, offering \(version)" + (installed.map { ", installed \($0)" } ?? ""),
            mac: InstallerLog.system,
            logs: InstallerLog.tail())
    }
}
