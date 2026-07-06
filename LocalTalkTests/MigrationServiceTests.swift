import XCTest
@testable import Bulong

final class MigrationServiceTests: XCTestCase {
    private var oldDefaults: UserDefaults!
    private var newDefaults: UserDefaults!
    private var oldDir: URL!
    private var newDir: URL!

    override func setUp() {
        oldDefaults = UserDefaults(suiteName: "MigrationOld")!
        newDefaults = UserDefaults(suiteName: "MigrationNew")!
        oldDefaults.removePersistentDomain(forName: "MigrationOld")
        newDefaults.removePersistentDomain(forName: "MigrationNew")
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-\(UUID().uuidString)")
        oldDir = base.appendingPathComponent("LocalTalk")
        newDir = base.appendingPathComponent("Bulong")
    }

    func testCopiesDefaultsAndMovesSupportDirOnce() throws {
        oldDefaults.set("tl", forKey: "language")
        oldDefaults.set(true, forKey: "hasCompletedOnboarding")
        try FileManager.default.createDirectory(at: oldDir, withIntermediateDirectories: true)
        try "x".write(to: oldDir.appendingPathComponent("history.jsonl"), atomically: true, encoding: .utf8)

        MigrationService.migrateIfNeeded(from: oldDefaults, to: newDefaults,
                                         oldSupportDir: oldDir, newSupportDir: newDir)

        XCTAssertEqual(newDefaults.string(forKey: "language"), "tl")
        XCTAssertTrue(newDefaults.bool(forKey: "hasCompletedOnboarding"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newDir.appendingPathComponent("history.jsonl").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldDir.path))
        XCTAssertTrue(newDefaults.bool(forKey: "didMigrateFromLocalTalk"))
    }

    func testDoesNotOverwriteExistingNewData() throws {
        newDefaults.set("en", forKey: "language")
        newDefaults.set(true, forKey: "didMigrateFromLocalTalk")
        oldDefaults.set("tl", forKey: "language")

        MigrationService.migrateIfNeeded(from: oldDefaults, to: newDefaults,
                                         oldSupportDir: oldDir, newSupportDir: newDir)

        XCTAssertEqual(newDefaults.string(forKey: "language"), "en") // marker set -> untouched
    }

    func testSilentWhenNothingToMigrate() {
        MigrationService.migrateIfNeeded(from: oldDefaults, to: newDefaults,
                                         oldSupportDir: oldDir, newSupportDir: newDir)
        XCTAssertTrue(newDefaults.bool(forKey: "didMigrateFromLocalTalk")) // marker still set (idempotence)
    }
}
