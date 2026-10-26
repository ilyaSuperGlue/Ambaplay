#if DEBUG
import AppKit
import SwiftUI

// Debug builds only: `.build/debug/AmbaplayApp --setup-preview [--fresh]` opens the Setup
// Assistant by itself for design review, then the main window once it closes. The assistant
// reads this Mac's state and only pretends to act (--fresh shows a Mac that still needs
// setup; --main skips straight to the main window; --run presses the step's button, so its
// progress can be captured; --pause then pauses its download after three seconds). The main window is the real one: its
// buttons do what they do in the app.
struct SetupPreviewApp: App {
    static let flag = "--setup-preview"

    @State private var status = SystemStatus()
    @State private var prefixes = PrefixesModel()
    @State private var pane: Pane = .status
    private static let mainFirst = CommandLine.arguments.contains("--main")
    private let preview: SetupAssistant.Preview =
        CommandLine.arguments.contains("--fresh") ? .fresh : .thisMac
    // --step 4 opens on Set Up; numbers match the wizard's "Step N of 5".
    private static let start: SetupAssistant.Step = {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--step"), index + 1 < arguments.count,
              let number = Int(arguments[index + 1]),
              let step = SetupAssistant.Step(rawValue: number - 1) else { return .mac }
        return step
    }()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApp.activate() }
    }

    var body: some Scene {
        Window("Ambaplay Setup", id: "setup-preview") {
            PreviewWizard(preview: preview, start: Self.start)
                .environment(status)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(Self.mainFirst ? .suppressed : .presented)
        .restorationBehavior(.disabled)

        Window("Ambaplay", id: "main-preview") {
            RootView(pane: $pane)
                .environment(status)
                .environment(prefixes)
                .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 900, height: 760)
        .defaultLaunchBehavior(Self.mainFirst ? .presented : .suppressed)
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Ambaplay") { AboutPanel.show() }
            }
        }
    }
}

private struct PreviewWizard: View {
    @State private var model: SetupAssistant
    private let start: SetupAssistant.Step
    @Environment(SystemStatus.self) private var status
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    init(preview: SetupAssistant.Preview, start: SetupAssistant.Step) {
        _model = State(initialValue: SetupAssistant(preview: preview, startAt: start))
        self.start = start
    }

    var body: some View {
        SetupAssistantView(model: model) {
            openWindow(id: "main-preview")
            dismissWindow(id: "setup-preview")
        }
        .task {
            guard CommandLine.arguments.contains("--run") else { return }
            if CommandLine.arguments.contains("--pause") {
                Task { try? await Task.sleep(for: .seconds(3)); DownloadMeter.shared.togglePause() }
            }
            switch start {
            case .steam: model.steamInstalled = false; await model.installSteam()
            case .finish: await model.finish(with: status)
            default: break
            }
        }
    }
}
#endif
