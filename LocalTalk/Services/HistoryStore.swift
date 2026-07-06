import Foundation
import Observation

@MainActor @Observable
final class HistoryStore {
    private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static var defaultFileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bulong", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("history.jsonl")
    }

    init(fileURL: URL = HistoryStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    private func load() {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = raw.split(separator: "\n").enumerated()
            .compactMap { offset, line -> (offset: Int, entry: HistoryEntry)? in
                guard let entry = try? decoder.decode(HistoryEntry.self, from: Data(line.utf8)) else {
                    return nil
                }
                return (offset, entry)
            }
            .sorted {
                if $0.entry.date == $1.entry.date {
                    return $0.offset > $1.offset
                }
                return $0.entry.date > $1.entry.date
            }
            .map(\.entry)
    }

    func append(_ entry: HistoryEntry) throws {
        entries.insert(entry, at: 0)
        var line = try encoder.encode(entry)
        line.append(contentsOf: "\n".utf8)

        if let parent = fileURL.deletingLastPathComponentIfNeeded {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: fileURL)
        }
    }

    func search(_ query: String) -> [HistoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
    }

    func exportPlainText() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return entries.reversed().map { entry in
            "[\(formatter.string(from: entry.date))] (\(entry.appName))\n\(entry.text)\n"
        }.joined(separator: "\n")
    }

    func clear() throws {
        entries = []
        try Data().write(to: fileURL)
    }
}

private extension URL {
    var deletingLastPathComponentIfNeeded: URL? {
        let parent = deletingLastPathComponent()
        return parent.path == path ? nil : parent
    }
}
