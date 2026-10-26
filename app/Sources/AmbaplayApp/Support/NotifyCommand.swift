import Foundation
import UserNotifications

// Posts one notification under Ambaplay's own name and icon, for the run script:
// `open -n -g -b com.ambaplay.Ambaplay --args --notify <title> <subtitle> <body>`.
// Runs before the migration and the log so a game launch never waits on either, and exits
// without opening a window. macOS asks once whether Ambaplay may send notifications.
enum NotifyCommand {
    static let flag = "--notify"

    static func requested() -> [String]? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        return Array(arguments[(index + 1)...])
    }

    static func run(_ parts: [String]) -> Never {
        Task.detached { exit(await post(parts) ? 0 : 1) }
        dispatchMain()
    }

    private static func post(_ parts: [String]) async -> Bool {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return false }
        let content = UNMutableNotificationContent()
        content.title = parts.first ?? "Ambaplay"
        if parts.count > 2 {
            content.subtitle = parts[1]
            content.body = parts[2...].joined(separator: " ")
        } else if parts.count == 2 {
            content.body = parts[1]
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        return (try? await center.add(request)) != nil
    }
}
