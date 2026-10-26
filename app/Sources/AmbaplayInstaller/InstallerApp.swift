import AppKit
import SwiftUI
import AmbaplayUI

@main
struct InstallerLaunch {
    @MainActor
    static func main() {
        if InstallerCleanup.runIfRequested() { return }
        if let index = CommandLine.arguments.firstIndex(of: "--icon"),
           CommandLine.arguments.indices.contains(index + 1) {
            InstallerScreenshot.icon(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--screenshot"),
           CommandLine.arguments.indices.contains(index + 1) {
            InstallerScreenshot.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            return
        }
        AmbaplayInstallerApp.main()
    }
}

struct AmbaplayInstallerApp: App {
    @NSApplicationDelegateAdaptor(InstallerDelegate.self) private var delegate
    @State private var model = InstallerModel()

    var body: some Scene {
        Window("Ambaplay Installer", id: "installer") {
            InstallerView(model: model)
                .onAppear { delegate.model = model }
                .task { await model.check() }
                .onDisappear { model.cancel() }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 780, height: 580)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

func tr(_ value: String.LocalizationValue) -> String {
    String(localized: value, bundle: InstallerResources.bundle)
}

@MainActor
private enum InstallerScreenshot {
    static func icon(to output: URL) {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: AmbaplayMark(size: 512).frame(width: 512, height: 512))
        host.frame = NSRect(x: 0, y: 0, width: 512, height: 512)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        do { try png.write(to: output) } catch { exit(1) }
    }

    static func render(to output: URL) {
        _ = NSApplication.shared
        let model = InstallerModel(preview: InstallerModel.previewArgument ?? "review")
        let host = NSHostingView(rootView: InstallerView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 580),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: .darkAqua)
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
        host.cacheDisplay(in: host.bounds, to: rep)
        do {
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
            try png.write(to: output)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
        window.orderOut(nil)
    }
}

@MainActor
final class InstallerDelegate: NSObject, NSApplicationDelegate {
    var model: InstallerModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model?.stage != .installing else { return .terminateCancel }
        model?.cancel()
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum InstallerResources {
    static var bundle: Bundle {
        if let resources = Bundle.main.resourceURL,
           let packaged = Bundle(url: resources.appendingPathComponent("AmbaplayApp_AmbaplayInstaller.bundle")) {
            return packaged
        }
        return .module
    }
}
