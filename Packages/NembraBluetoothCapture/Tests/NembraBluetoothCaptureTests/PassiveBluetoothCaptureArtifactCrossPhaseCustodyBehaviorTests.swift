import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive capture artifact cross-phase custody behavior")
struct PassiveBluetoothCaptureArtifactCrossPhaseCustodyBehaviorTests {
    @Test("publication rejects input pathname replacement after exact-byte admission")
    func rejectsInputPathReplacementAfterAdmission() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let capture = directory.appendingPathComponent("capture.json")
        let originalAlias = directory.appendingPathComponent("original-raw.json")
        let report = directory.appendingPathComponent("report.json")
        try Data("raw-A".utf8).write(to: capture)

        let receipt = try PassiveBluetoothCaptureArtifactInputPolicy.readExactArtifact(
            at: capture,
            maximumBytes: 1024
        )
        try FileManager.default.linkItem(at: capture, to: originalAlias)

        try FileManager.default.removeItem(at: capture)
        try Data("raw-B".utf8).write(to: capture)

        #expect(throws: PassiveBluetoothCaptureArtifactOutputPolicyError
            .inputSourceChangedSinceAdmission(capture.standardizedFileURL.resolvingSymlinksInPath().path)) {
            try PassiveBluetoothCaptureArtifactOutputPolicy.writeDerivedReport(
                Data("derived-from-A".utf8),
                inputURL: capture,
                inputReceipt: receipt,
                outputURL: report,
                allowReplacingExistingOutput: true
            )
        }

        #expect(String(decoding: try Data(contentsOf: originalAlias), as: UTF8.self) == "raw-A")
        #expect(String(decoding: try Data(contentsOf: capture), as: UTF8.self) == "raw-B")
        #expect(!FileManager.default.fileExists(atPath: report.path))
    }

    @Test("unchanged admitted source can publish a distinct report")
    func unchangedSourcePublishes() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let capture = directory.appendingPathComponent("capture.json")
        let report = directory.appendingPathComponent("report.json")
        try Data("raw".utf8).write(to: capture)

        let receipt = try PassiveBluetoothCaptureArtifactInputPolicy.readExactArtifact(
            at: capture,
            maximumBytes: 1024
        )
        try PassiveBluetoothCaptureArtifactOutputPolicy.writeDerivedReport(
            Data("derived".utf8),
            inputURL: capture,
            inputReceipt: receipt,
            outputURL: report,
            allowReplacingExistingOutput: false
        )

        #expect(String(decoding: try Data(contentsOf: capture), as: UTF8.self) == "raw")
        #expect(String(decoding: try Data(contentsOf: report), as: UTF8.self) == "derived")
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nembra-cross-phase-custody-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
