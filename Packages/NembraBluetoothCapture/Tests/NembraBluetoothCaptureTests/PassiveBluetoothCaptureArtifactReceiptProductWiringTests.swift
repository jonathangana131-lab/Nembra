import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive capture artifact receipt-bound publication")
struct PassiveBluetoothCaptureArtifactReceiptProductWiringTests {
    @Test("publication rejects input pathname replacement after admission")
    func rejectsInputPathReplacementAfterAdmission() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let capture = directory.appendingPathComponent("capture.json")
        let originalAlias = directory.appendingPathComponent("original-raw.json")
        let report = directory.appendingPathComponent("report.json")
        try Data("raw-A".utf8).write(to: capture)

        let receipt = try PassiveBluetoothCaptureArtifactInputPolicy.readExactReceipt(
            at: capture,
            maximumBytes: 1024
        )
        try FileManager.default.linkItem(at: capture, to: originalAlias)

        try FileManager.default.removeItem(at: capture)
        try Data("raw-B".utf8).write(to: capture)

        #expect(throws: PassiveBluetoothCaptureArtifactOutputPolicyError
            .inputChangedSinceAdmission(capture.standardizedFileURL.resolvingSymlinksInPath().path)) {
            try PassiveBluetoothCaptureArtifactOutputPolicy.writeDerivedReport(
                Data("derived-from-A".utf8),
                inputReceipt: receipt,
                inputURL: capture,
                outputURL: report,
                allowReplacingExistingOutput: true
            )
        }

        #expect(String(decoding: try Data(contentsOf: originalAlias), as: UTF8.self) == "raw-A")
        #expect(String(decoding: try Data(contentsOf: capture), as: UTF8.self) == "raw-B")
        #expect(!FileManager.default.fileExists(atPath: report.path))
    }

    @Test("unchanged receipt can publish a distinct report")
    func unchangedReceiptPublishes() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let capture = directory.appendingPathComponent("capture.json")
        let report = directory.appendingPathComponent("report.json")
        try Data("raw".utf8).write(to: capture)

        let receipt = try PassiveBluetoothCaptureArtifactInputPolicy.readExactReceipt(
            at: capture,
            maximumBytes: 1024
        )
        try PassiveBluetoothCaptureArtifactOutputPolicy.writeDerivedReport(
            Data("derived".utf8),
            inputReceipt: receipt,
            inputURL: capture,
            outputURL: report,
            allowReplacingExistingOutput: false
        )

        #expect(String(decoding: try Data(contentsOf: capture), as: UTF8.self) == "raw")
        #expect(String(decoding: try Data(contentsOf: report), as: UTF8.self) == "derived")
    }

    @Test("product command source carries one receipt from read through publication")
    func commandUsesReceiptPath() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let commandSource = try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraES80CaptureReport")
                .appendingPathComponent("main.swift"),
            encoding: .utf8
        )
        let outputSource = try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("PassiveBluetoothCaptureArtifactOutputPolicy.swift"),
            encoding: .utf8
        )

        #expect(commandSource.contains("readExactReceipt("))
        #expect(commandSource.contains("let artifactData = inputReceipt.bytes"))
        #expect(commandSource.contains("inputReceipt: inputReceipt"))

        let legacyPublicSignature = "public static func writeDerivedReport(\n        _ data: Data,\n        inputURL: URL,"
        #expect(!outputSource.contains(legacyPublicSignature))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nembra-receipt-publication-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
