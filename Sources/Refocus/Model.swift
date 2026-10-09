import AppKit
import Foundation

/// Hiding behaviour for one application. `timeout` is in seconds; 0 disables hiding.
struct AppRule: Codable, Hashable {
    var timeout: Int
    var hideImmediately: Bool

    var isDisabled: Bool { timeout <= 0 }
}

/// A named set of hiding rules, e.g. "Default" or "Focus Mode".
struct Profile: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var defaultTimeout: Int
    var defaultHideImmediately: Bool
    /// Per-application overrides keyed by bundle identifier.
    var rules: [String: AppRule]

    init(id: UUID = UUID(), name: String, defaultTimeout: Int = 120,
         defaultHideImmediately: Bool = false, rules: [String: AppRule] = [:]) {
        self.id = id
        self.name = name
        self.defaultTimeout = defaultTimeout
        self.defaultHideImmediately = defaultHideImmediately
        self.rules = rules
    }

    var defaultRule: AppRule { AppRule(timeout: defaultTimeout, hideImmediately: defaultHideImmediately) }

    func rule(for bundleID: String) -> AppRule { rules[bundleID] ?? defaultRule }
}

struct HotKeyCombo: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon modifier flags (cmdKey, optionKey, ...).
    var modifiers: UInt32
    var display: String
}

struct Config: Codable {
    var profiles: [Profile]
    var activeProfileID: UUID
    var hidingPaused = false
    var totalHidden = 0
    var cycleProfilesHotKey: HotKeyCombo?
    /// Freeze countdowns while the screen is locked, the Mac sleeps or the user is idle.
    var pauseWhileAway = true
    /// Seconds without keyboard/mouse input that count as away; 0 = only lock/sleep/screensaver.
    var idleThreshold = 120

    static func fresh() -> Config {
        let p = Profile(name: "Default", defaultTimeout: 120)
        return Config(profiles: [p], activeProfileID: p.id)
    }
}

extension Config {
    // Tolerates config files written by older versions that lack newer keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try c.decode([Profile].self, forKey: .profiles)
        activeProfileID = try c.decode(UUID.self, forKey: .activeProfileID)
        hidingPaused = try c.decodeIfPresent(Bool.self, forKey: .hidingPaused) ?? false
        totalHidden = try c.decodeIfPresent(Int.self, forKey: .totalHidden) ?? 0
        cycleProfilesHotKey = try c.decodeIfPresent(HotKeyCombo.self, forKey: .cycleProfilesHotKey)
        pauseWhileAway = try c.decodeIfPresent(Bool.self, forKey: .pauseWhileAway) ?? true
        idleThreshold = try c.decodeIfPresent(Int.self, forKey: .idleThreshold) ?? 120
    }
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var config: Config {
        didSet {
            save()
            if oldValue.cycleProfilesHotKey != config.cycleProfilesHotKey {
                HotKeyCenter.shared.register(config.cycleProfilesHotKey)
            }
        }
    }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Refocus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let cfg = try? JSONDecoder().decode(Config.self, from: data), !cfg.profiles.isEmpty {
            config = cfg
        } else if let imported = try? LegacyImporter.load() {
            // First launch on a Mac that still has Hocus Focus settings: take them over.
            config = imported
            save()
        } else {
            config = .fresh()
            save()
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(config) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    // MARK: Profiles

    var activeProfile: Profile {
        config.profiles.first { $0.id == config.activeProfileID } ?? config.profiles[0]
    }

    func updateProfile(_ id: UUID, _ change: (inout Profile) -> Void) {
        guard let i = config.profiles.firstIndex(where: { $0.id == id }) else { return }
        change(&config.profiles[i])
    }

    func setRule(_ rule: AppRule?, for bundleID: String, in profileID: UUID? = nil) {
        updateProfile(profileID ?? activeProfile.id) { $0.rules[bundleID] = rule }
    }

    func activate(_ id: UUID) {
        guard id != config.activeProfileID, let p = config.profiles.first(where: { $0.id == id }) else { return }
        config.activeProfileID = id
        HUD.show("Switched to \(p.name) profile")
    }

    func cycleProfile() {
        let ps = config.profiles
        guard ps.count > 1, let i = ps.firstIndex(where: { $0.id == activeProfile.id }) else { return }
        activate(ps[(i + 1) % ps.count].id)
    }

    @discardableResult
    func addProfile(copying source: Profile? = nil) -> Profile {
        var p = source ?? Profile(name: "New Profile")
        p.id = UUID()
        p.name = source.map { "\($0.name) copy" } ?? p.name
        config.profiles.append(p)
        return p
    }

    func deleteProfile(_ id: UUID) {
        guard config.profiles.count > 1 else { return }
        config.profiles.removeAll { $0.id == id }
        if config.activeProfileID == id { config.activeProfileID = config.profiles[0].id }
    }

    func resetAll() {
        let total = config.totalHidden
        config = .fresh()
        config.totalHidden = total
    }
}

// MARK: - Formatting

enum TimeoutFormat {
    /// Slider stops, in seconds. 0 = never hide.
    static let steps = [0, 5, 10, 15, 20, 30, 45, 60, 90, 120, 150, 180, 240, 300, 450,
                        600, 900, 1200, 1800, 2700, 3600]

    static func nearestStep(_ seconds: Int) -> Int {
        steps.indices.min { abs(steps[$0] - seconds) < abs(steps[$1] - seconds) } ?? 0
    }

    static func describe(_ seconds: Int) -> String {
        if seconds <= 0 { return "Never" }
        if seconds < 60 { return "\(seconds) s" }
        if seconds >= 3600, seconds % 3600 == 0 { return "\(seconds / 3600) h" }
        let m = seconds / 60, s = seconds % 60
        return s == 0 ? "\(m) min" : "\(m) min \(s) s"
    }

    static func countdown(_ interval: TimeInterval) -> String {
        let t = Int(interval.rounded(.up))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

extension Bundle {
    static func appInfo(for bundleID: String) -> (name: String, icon: NSImage) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            return (name, NSWorkspace.shared.icon(forFile: url.path))
        }
        return (bundleID, NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage())
    }
}
