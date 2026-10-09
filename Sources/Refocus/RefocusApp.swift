import AppKit
import SwiftUI

@main
struct RefocusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store.shared
    @StateObject private var engine = HidingEngine.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(store)
                .environmentObject(engine)
        } label: {
            Image(systemName: store.config.hidingPaused ? "pause.circle" : "wand.and.sparkles")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            _ = HidingEngine.shared // start watching right away, not when the menu first opens
            HotKeyCenter.shared.action = { Store.shared.cycleProfile() }
            HotKeyCenter.shared.register(Store.shared.config.cycleProfilesHotKey)
        }
    }
}
