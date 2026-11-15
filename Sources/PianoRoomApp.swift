import os
import SwiftUI

private let appDelegateLogger = Logger(subsystem: "com.alexpianoroom.PianoRoom", category: "app")

@main
struct PianoRoomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState()

    init() {
        AppFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(state)
                .preferredColorScheme(.light)
                .frame(minWidth: 1080, minHeight: 760)
                .task {
                    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
                       ProcessInfo.processInfo.environment["PIANOROOM_TESTING"] != "1" {
                        state.start()
                    }
                }
                .onAppear {
                    appDelegate.onShutdown = { await state.shutdown() }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environment(state)
                .preferredColorScheme(.light)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onShutdown: (@MainActor () async -> Void)?
    private var shutdownTask: Task<Void, Never>?
    private var didFinishShutdown = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !didFinishShutdown, let onShutdown else { return .terminateNow }
        guard shutdownTask == nil else { return .terminateLater }
        appDelegateLogger.info("Приложение завершается: возвращаем звук пианино")
        shutdownTask = Task { @MainActor in
            await onShutdown()
            self.didFinishShutdown = true
            self.shutdownTask = nil
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
