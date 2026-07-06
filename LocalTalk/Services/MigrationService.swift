import Foundation
import os

/// One-way, idempotent migration of LocalTalk-era data into the Bulong bundle identity.
enum MigrationService {
    private static let logger = Logger(subsystem: "com.armageddonvivas.Bulong", category: "migration")

    static let markerKey = "didMigrateFromLocalTalk"
    /// Frozen snapshot of the keys the LocalTalk-era SettingsStore persisted.
    /// Do NOT add new Bulong-era keys here — they never existed in the old domain,
    /// so there is nothing to migrate for them.
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
            do {
                try fm.createDirectory(at: newSupportDir.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                try fm.moveItem(at: oldSupportDir, to: newSupportDir)
                logger.info("Moved support dir \(oldSupportDir.path, privacy: .public) -> \(newSupportDir.path, privacy: .public)")
            } catch {
                logger.error("Failed to move support dir \(oldSupportDir.path, privacy: .public) -> \(newSupportDir.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        } else {
            logger.info("No support dir to migrate (old exists: \(fm.fileExists(atPath: oldSupportDir.path)), new exists: \(fm.fileExists(atPath: newSupportDir.path)))")
        }
    }

    private static func supportDir(_ name: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name, isDirectory: true)
    }
}
