import XCTest
@testable import Bulong

@MainActor
final class ModelManagerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Builds one compiled-model bundle the way a finished download leaves it.
    private func writeBundle(_ name: String, coremldata: Bool = true, weights: Bool = true) throws {
        let bundle = root.appendingPathComponent(name, isDirectory: true)
        let weightsDir = bundle.appendingPathComponent("weights", isDirectory: true)
        try FileManager.default.createDirectory(at: weightsDir, withIntermediateDirectories: true)
        if coremldata {
            try Data("x".utf8).write(to: bundle.appendingPathComponent("coremldata.bin"))
        }
        if weights {
            try Data("x".utf8).write(to: weightsDir.appendingPathComponent("weight.bin"))
        }
    }

    private func writeCompleteModel() throws {
        try writeBundle("AudioEncoder.mlmodelc")
        try writeBundle("MelSpectrogram.mlmodelc")
        try writeBundle("TextDecoder.mlmodelc")
    }

    func testCompleteModelReadsAsComplete() throws {
        try writeCompleteModel()
        XCTAssertTrue(ModelManager.whisperModelIsComplete(at: root))
    }

    /// The bug: readiness was a bare fileExists on the FOLDER, so a download
    /// killed partway through reported "Ready" forever and every dictation
    /// after it failed with no way to repair the model from inside the app.
    func testFolderThatMerelyExistsIsNotComplete() {
        XCTAssertFalse(ModelManager.whisperModelIsComplete(at: root),
                       "an empty model folder must never report ready")
    }

    func testInterruptedDownloadMissingABundleIsNotComplete() throws {
        try writeBundle("AudioEncoder.mlmodelc")
        try writeBundle("MelSpectrogram.mlmodelc")
        // TextDecoder never arrived — connection dropped.
        XCTAssertFalse(ModelManager.whisperModelIsComplete(at: root))
    }

    func testBundleWithoutItsCompiledMarkerIsNotComplete() throws {
        try writeCompleteModel()
        try FileManager.default.removeItem(
            at: root.appendingPathComponent("TextDecoder.mlmodelc/coremldata.bin"))
        XCTAssertFalse(ModelManager.whisperModelIsComplete(at: root))
    }

    func testBundleWithEmptyWeightsIsNotComplete() throws {
        try writeBundle("AudioEncoder.mlmodelc")
        try writeBundle("MelSpectrogram.mlmodelc")
        try writeBundle("TextDecoder.mlmodelc", weights: false)
        XCTAssertFalse(ModelManager.whisperModelIsComplete(at: root))
    }

    // MARK: - What a refresh poll may overwrite

    /// refresh() runs every ~2s while the main window is open. It used to
    /// flatten .failed back to .notDownloaded, so a download error and its
    /// Retry button vanished about a second after appearing.
    func testPollKeepsAFailureVisible() {
        let next = ModelManager.nextState(current: .failed("no network"), isComplete: false)
        XCTAssertEqual(next, .failed("no network"))
    }

    func testPollNeverInterruptsAnInFlightDownload() {
        XCTAssertEqual(ModelManager.nextState(current: .downloading(0.4), isComplete: false),
                       .downloading(0.4))
        XCTAssertEqual(ModelManager.nextState(current: .downloading(0.9), isComplete: true),
                       .downloading(0.9))
    }

    func testFailureClearsOnceTheModelIsActuallyPresent() {
        XCTAssertEqual(ModelManager.nextState(current: .failed("disk full"), isComplete: true), .ready)
    }

    func testMissingModelReadsAsNotDownloaded() {
        XCTAssertEqual(ModelManager.nextState(current: .ready, isComplete: false), .notDownloaded)
    }
}
