import Foundation

/// One-way, idempotent migration of LocalTalk-era data into the Bulong bundle identity.
enum MigrationService {
    static let markerKey = "didMigrateFromLocalTalk"
    /// Keys persisted by SettingsStore (keep in sync when SettingsStore adds keys pre-1.0).
    static let settingsKeys = [
        "language", "task", "hotkeyMode", "hotkey", "engineOverride",
        "pasteAfterTranscription", "playSounds", "hasCompletedOnboarding",
    ]

    static func migrateIfNeeded(
        from old: UserDefaults? = UserDefaults(suiteName: "com.armageddonvivas.LocalTalk"),
        to new: UserDefaults = .standard,
        oldSupportDir: URL = supportDir("LocalTalk"),
        newSupportDir: URL = supportDir("Bulong")
    ) {
        guard !new.bool(forKey: markerKey) else { return }
        defer { new.set(true, forKey: markerKey) }

        if let old {
            for key in settingsKeys where new.object(forKey: key) == nil {
                if let value = old.object(forKey: key) { new.set(value, forKey: key) }
            }
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: oldSupportDir.path), !fm.fileExists(atPath: newSupportDir.path) {
            try? fm.createDirectory(at: newSupportDir.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            try? fm.moveItem(at: oldSupportDir, to: newSupportDir)
        }
    }

    private static func supportDir(_ name: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name, isDirectory: true)
    }
}
