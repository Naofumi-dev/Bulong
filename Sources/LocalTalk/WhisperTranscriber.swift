import Foundation

enum WhisperTask: String {
    case transcribe
    case translate
}

struct WhisperOptions {
    let model: String
    let task: WhisperTask
    let language: String?
    let searchPath: String
}

struct WhisperTranscriber {
    let executablePath: String

    func transcribe(audioURL: URL, options: WhisperOptions) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let outputDirectory = fileManager.temporaryDirectory
                .appendingPathComponent("LocalTalk/Transcripts", isDirectory: true)
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

            let outputURL = outputDirectory
                .appendingPathComponent(audioURL.deletingPathExtension().lastPathComponent)
                .appendingPathExtension("txt")
            try? fileManager.removeItem(at: outputURL)

            let process = Process()
            let whisperArguments = makeArguments(
                audioURL: audioURL,
                outputDirectory: outputDirectory,
                options: options
            )

            if executablePath.contains("/") {
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = whisperArguments
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [executablePath] + whisperArguments
            }

            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = options.searchPath
            process.environment = environment

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            try process.run()
            let processOutput = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let output = String(data: processOutput, encoding: .utf8) ?? ""
                throw WhisperTranscriberError.processFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            guard fileManager.fileExists(atPath: outputURL.path) else {
                let output = String(data: processOutput, encoding: .utf8) ?? ""
                throw WhisperTranscriberError.missingTranscript(output.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            return try String(contentsOf: outputURL, encoding: .utf8)
        }.value
    }

    private func makeArguments(audioURL: URL, outputDirectory: URL, options: WhisperOptions) -> [String] {
        var arguments = [
            audioURL.path,
            "--model", options.model,
            "--task", options.task.rawValue,
            "--output_format", "txt",
            "--output_dir", outputDirectory.path,
            "--verbose", "False",
            "--fp16", "False"
        ]

        if let language = options.language, !language.isEmpty {
            arguments += ["--language", language]
        }

        return arguments
    }
}

enum WhisperTranscriberError: LocalizedError {
    case processFailed(String)
    case missingTranscript(String)

    var errorDescription: String? {
        switch self {
        case .processFailed(let output):
            return output.isEmpty ? "Whisper failed" : "Whisper failed: \(output)"
        case .missingTranscript(let output):
            return output.isEmpty ? "Whisper did not write a transcript" : "Whisper did not write a transcript: \(output)"
        }
    }
}

enum WhisperLocator {
    static let defaultSearchPath = [
        "/Library/Frameworks/Python.framework/Versions/3.14/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ].joined(separator: ":")

    static func defaultWhisperExecutable() -> String {
        let candidates = [
            "/Library/Frameworks/Python.framework/Versions/3.14/bin/whisper",
            "/opt/homebrew/bin/whisper",
            "/usr/local/bin/whisper"
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        return "whisper"
    }
}
