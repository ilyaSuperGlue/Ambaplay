import Foundation
import Sparkle

@MainActor
final class AppUpdater {

    // One updater for the app: the menu and the Status page's Refresh share it.
    static let shared = AppUpdater()

    private let controller: SPUStandardUpdaterController
    // Sparkle holds its delegate weakly.
    private let finder: ReleaseFinder

    init() {
        #if DEBUG
        let scheduling = false
        #else
        let scheduling = true
        #endif
        finder = ReleaseFinder()
        controller = SPUStandardUpdaterController(
            startingUpdater: scheduling,
            updaterDelegate: finder,
            userDriverDelegate: nil
        )
    }

    func check() {
        #if !DEBUG
        controller.checkForUpdates(nil)
        #endif
    }

}

@MainActor
private final class ReleaseFinder: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        LatestRelease.record(build: item.versionString, version: item.displayVersionString)
    }
}

// The newest release Sparkle has found, so a play report can say the player was behind.
enum LatestRelease {
    static let buildKey = "LatestReleaseBuild"
    static let versionKey = "LatestReleaseVersion"

    static func record(build: String, version: String, defaults: UserDefaults = .standard) {
        defaults.set(build, forKey: buildKey)
        defaults.set(version, forKey: versionKey)
    }

    // "0.7.38 (55)" when the release found is newer than `build`; releases are ordered by
    // build, never by the version label.
    static func newer(than build: String?, defaults: UserDefaults = .standard) -> String? {
        guard let found = defaults.string(forKey: buildKey), let foundBuild = Int(found),
              let build = build.flatMap({ Int($0) }), foundBuild > build else { return nil }
        let version = defaults.string(forKey: versionKey) ?? ""
        return version.isEmpty ? "build \(found)" : "\(version) (\(found))"
    }
}
