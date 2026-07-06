import XCTest
@testable import LocalTalk

final class HistoryStoreTests: XCTestCase {
    private var tmpFile: URL!

    override func setUp() {
        tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).jsonl")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpFile)
    }

    private func entry(_ text: String, app: String = "TextEdit") -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            text: text,
            date: Date(),
            appName: app,
            engine: .parakeet,
            language: "en",
            durationSeconds: 2.5
        )
    }

    @MainActor func testAppendAndReloadFromDisk() throws {
        let s1 = HistoryStore(fileURL: tmpFile)
        try s1.append(entry("hello world"))
        try s1.append(entry("second item"))
        let s2 = HistoryStore(fileURL: tmpFile)
        XCTAssertEqual(s2.entries.count, 2)
        XCTAssertEqual(s2.entries.first?.text, "second item")
    }

    @MainActor func testSearchIsCaseInsensitive() throws {
        let s = HistoryStore(fileURL: tmpFile)
        try s.append(entry("Meeting notes for Tuesday"))
        try s.append(entry("grocery list"))
        XCTAssertEqual(s.search("MEETING").count, 1)
        XCTAssertEqual(s.search("").count, 2)
    }

    @MainActor func testExportPlainText() throws {
        let s = HistoryStore(fileURL: tmpFile)
        try s.append(entry("alpha"))
        try s.append(entry("beta"))
        let text = s.exportPlainText()
        XCTAssertTrue(text.contains("alpha"))
        XCTAssertTrue(text.contains("beta"))
        XCTAssertTrue(text.contains("TextEdit"))
    }

    @MainActor func testClearRemovesFileContents() throws {
        let s = HistoryStore(fileURL: tmpFile)
        try s.append(entry("to be removed"))
        try s.clear()
        XCTAssertTrue(s.entries.isEmpty)
        let s2 = HistoryStore(fileURL: tmpFile)
        XCTAssertTrue(s2.entries.isEmpty)
    }

    @MainActor func testCorruptLinesAreSkippedNotFatal() throws {
        try "not json\n".write(to: tmpFile, atomically: true, encoding: .utf8)
        let s = HistoryStore(fileURL: tmpFile)
        XCTAssertTrue(s.entries.isEmpty)
        try s.append(entry("still works"))
        XCTAssertEqual(s.entries.count, 1)
    }
}
