import os
import SwiftUI

private let appDelegateLogger = Logger(subsystem: "com.alexpianoroom.PianoRoom", category: "app")

@main
struct PianoRoomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .preferredColorScheme(.light)
                .frame(minWidth: 1080, minHeight: 760)
                .onAppear {
                    appDelegate.onTerminate = state.onTerminate
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(state)
                .preferredColorScheme(.light)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onTerminate: (() -> Void)?

    func applicationWillTerminate(_ notification: Notification) {
        appDelegateLogger.info("Приложение завершается: возвращаем звук пианино")
        onTerminate?()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
