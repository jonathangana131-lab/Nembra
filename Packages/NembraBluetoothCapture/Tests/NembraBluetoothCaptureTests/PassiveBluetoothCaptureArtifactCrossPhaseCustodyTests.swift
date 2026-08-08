import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive capture artifact cross-phase custody")
struct PassiveBluetoothCaptureArtifactCrossPhaseCustodyTests {
    @Test("derived report publication rejects source-path replacement after admission")
    func rejectsSourceReplacementAfterAdmission() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("nembra-cross-phase-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let inputURL = root.appendingPathComponent("capture.json")
        let admittedBackupURL = root.appendingPathComponent("capture-admitted.json")
        let outputURL = root.appendingPathComponent("report.json")
        let admittedBytes = Data("{\"capture\":\"admitted\"}".utf8)
        let replacementBytes = Data("{\"capture\":\"replacement\"}".utf8)
        try admittedBytes.write(to: inputURL)

        let inputReceipt = try PassiveBluetoothCaptureArtifactInputPolicy.readExactReceipt(
            at: inputURL,
            maximumBytes: 1024
        )
        #expect(inputReceipt.bytes == admittedBytes)

        try fileManager.moveItem(at: inputURL, to: admittedBackupURL)
        try replacementBytes.write(to: inputURL)

        #expect(throws: PassiveBluetoothCaptureArtifactOutputPolicyError.self) {
            try PassiveBluetoothCaptureArtifactOutputPolicy.writeDerivedReport(
                Data("{\"derived\":true}".utf8),
                inputReceipt: inputReceipt,
                inputURL: inputURL,
                outputURL: outputURL,
                allowReplacingExistingOutput: true
            )
        }
        #expect(!fileManager.fileExists(atPath: outputURL.path))
        #expect(try Data(contentsOf: admittedBackupURL) == admittedBytes)
        #expect(try Data(contentsOf: inputURL) == replacementBytes)
    }

    @Test("derived report publication remains allowed for the exact admitted source")
    func publishesWhenSourceIdentityIsUnchanged() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("nembra-cross-phase-stable-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let inputURL = root.appendingPathComponent("capture.json")
        let outputURL = root.appendingPathComponent("report.json")
        let admittedBytes = Data("{\"capture\":\"stable\"}".utf8)
        let reportBytes = Data("{\"derived\":true}".utf8)
        try admittedBytes.write(to: inputURL)

        let inputReceipt = try PassiveBluetoothCaptureArtifactInputPolicy.readExactReceipt(
            at: inputURL,
            maximumBytes: 1024
        )
        try PassiveBluetoothCaptureArtifactOutputPolicy.writeDerivedReport(
            reportBytes,
            inputReceipt: inputReceipt,
            inputURL: inputURL,
            outputURL: outputURL,
            allowReplacingExistingOutput: false
        )

        #expect(try Data(contentsOf: inputURL) == admittedBytes)
        #expect(try Data(contentsOf: outputURL) == reportBytes)
    }
}