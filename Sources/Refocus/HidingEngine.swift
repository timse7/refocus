import AppKit
import CoreGraphics

struct AppRow: Identifiable {
    enum State {
        case active
        case counting(TimeInterval)
        case offscreen          // running, not hidden, but no window on the current Space
        case hidden
        case disabled
    }

    let app: NSRunningApplication
    let bundleID: String
    let name: String
    let icon: NSImage
    let state: State
    let isCustom: Bool

    var id: pid_t { app.processIdentifier }
}

/// Watches application activation and hides apps that stayed in the background
/// longer than their timeout, or as soon as they lose focus when configured so.
@MainActor
final class HidingEngine: ObservableObject {
    static let shared = HidingEngine(store: .shared)

    @Published private(set) var rows: [AppRow] = []

    private let store: Store
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    /// When each app was last in front (refreshed every tick while it is).
    private var lastActive: [pid_t: Date] = [:]
    /// The app the user is working in. Our own popover never counts as that.
    private var currentApp: NSRunningApplication?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    private init(store: Store) {
        self.store = store
        let now = Date()
        for app in NSWorkspace.shared.runningApplications { lastActive[app.processIdentifier] = now }
        currentApp = NSWorkspace.shared.frontmostApplication

        let nc = NSWorkspace.shared.notificationCenter
        func observe(_ name: Notification.Name, _ handler: @escaping @MainActor (HidingEngine, NSRunningApplication) -> Void) {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated {
                    guard let self else { return }
                    handler(self, app)
                    self.tick()
                }
            })
        }
        observe(NSWorkspace.didActivateApplicationNotification) { $0.didActivate($1) }
        observe(NSWorkspace.didLaunchApplicationNotification) { $0.lastActive[$1.processIdentifier] = Date() }
        observe(NSWorkspace.didUnhideApplicationNotification) { $0.lastActive[$1.processIdentifier] = Date() }
        observe(NSWorkspace.didHideApplicationNotification) { _, _ in }
        observe(NSWorkspace.didTerminateApplicationNotification) { $0.lastActive[$1.processIdentifier] = nil }

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    private func didActivate(_ app: NSRunningApplication) {
        guard app.processIdentifier != ownPID else { return }
        let now = Date()
        lastActive[app.processIdentifier] = now
        if let prev = currentApp, prev.processIdentifier != app.processIdentifier, !prev.isTerminated {
            lastActive[prev.processIdentifier] = now
            if !store.config.hidingPaused, let bid = prev.bundleIdentifier {
                let rule = store.activeProfile.rule(for: bid)
                if rule.hideImmediately, !rule.isDisabled { hide(prev) }
            }
        }
        currentApp = app
    }

    private func hide(_ app: NSRunningApplication) {
        if app.hide() { store.config.totalHidden += 1 }
    }

    func tick() {
        let now = Date()
        let profile = store.activeProfile
        let paused = store.config.hidingPaused
        let onScreen = Self.pidsWithOnScreenWindows()
        if let cur = currentApp, !cur.isTerminated { lastActive[cur.processIdentifier] = now }

        var result: [AppRow] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != ownPID {
            guard let bid = app.bundleIdentifier else { continue }
            let pid = app.processIdentifier
            let rule = profile.rule(for: bid)
            let state: AppRow.State
            if rule.isDisabled {
                state = .disabled
            } else if app.isHidden {
                state = .hidden
            } else if pid == currentApp?.processIdentifier {
                state = .active
            } else if !onScreen.contains(pid) {
                state = .offscreen
            } else {
                let remaining = Double(rule.timeout) - now.timeIntervalSince(lastActive[pid] ?? now)
                if !paused && remaining <= 0 {
                    hide(app)
                    state = .hidden
                } else {
                    state = .counting(max(0, remaining))
                }
            }
            result.append(AppRow(app: app, bundleID: bid, name: app.localizedName ?? bid,
                                 icon: app.icon ?? NSImage(), state: state,
                                 isCustom: profile.rules[bid] != nil))
        }
        rows = result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// PIDs owning a normal, visible window on the current Space. Owner PIDs are
    /// available without the Screen Recording permission (only titles are not).
    static func pidsWithOnScreenWindows() -> Set<pid_t> {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        var pids = Set<pid_t>()
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t else { continue }
            if let b = w[kCGWindowBounds as String] as? [String: Double],
               (b["Width"] ?? 0) < 2 || (b["Height"] ?? 0) < 2 { continue }
            pids.insert(pid)
        }
        return pids
    }
}
