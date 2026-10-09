import Foundation
import SQLite3

/// Reads the settings of the original Hocus Focus app, which keeps its
/// profiles in a Core Data SQLite store and a few flags in its defaults domain.
enum LegacyImporter {
    struct ImportError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static let bundleID = "com.uglyapps.HocusFocus"

    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(bundleID)/HocusFocus.db")
    }

    static var isAvailable: Bool { FileManager.default.fileExists(atPath: databaseURL.path) }

    static func load() throws -> Config {
        guard isAvailable else { throw ImportError(message: "No Hocus Focus settings found.") }
        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            defer { sqlite3_close(db) }
            throw ImportError(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_close(db) }

        var order: [Int64] = []
        var profiles: [Int64: Profile] = [:]
        try query(db, "SELECT Z_PK, ZNAME, ZGUID, ZDEFAULTTIMEOUT, ZDEFAULTHIDEIMMEDIATELY FROM ZUAPROFILE ORDER BY Z_PK") { s in
            let pk = sqlite3_column_int64(s, 0)
            let name = text(s, 1) ?? "Profile \(pk)"
            let id = text(s, 2).flatMap(UUID.init(uuidString:)) ?? UUID()
            profiles[pk] = Profile(id: id, name: name,
                                   defaultTimeout: Int(sqlite3_column_int64(s, 3)),
                                   defaultHideImmediately: sqlite3_column_int(s, 4) != 0)
            order.append(pk)
        }
        try query(db, "SELECT ZPROFILE, ZBUNDLEID, ZTIMEOUT, ZHIDEIMMEDIATELY FROM ZUAAPPLICATION") { s in
            let pk = sqlite3_column_int64(s, 0)
            guard let bid = text(s, 1), profiles[pk] != nil else { return }
            profiles[pk]!.rules[bid] = AppRule(timeout: Int(sqlite3_column_int64(s, 2)),
                                               hideImmediately: sqlite3_column_int(s, 3) != 0)
        }

        let list = order.compactMap { profiles[$0] }
        guard !list.isEmpty else { throw ImportError(message: "Hocus Focus has no profiles.") }

        let legacy = UserDefaults(suiteName: bundleID)
        let activeID = legacy?.string(forKey: "kActiveProfileGUIDKey").flatMap(UUID.init(uuidString:))
        var cfg = Config(profiles: list,
                         activeProfileID: list.contains { $0.id == activeID } ? activeID! : list[0].id)
        cfg.hidingPaused = legacy?.bool(forKey: "kDisableApplicationHidingKey") ?? false
        cfg.totalHidden = legacy?.integer(forKey: "kTotalApplicationsHiddenCount") ?? 0
        return cfg
    }

    private static func text(_ s: OpaquePointer?, _ col: Int32) -> String? {
        sqlite3_column_text(s, col).map { String(cString: $0) }
    }

    private static func query(_ db: OpaquePointer?, _ sql: String, _ row: (OpaquePointer?) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ImportError(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW { row(stmt) }
    }
}
