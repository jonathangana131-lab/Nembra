import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive capture artifact output policy")
struct PassiveBluetoothCaptureArtifactOutputPolicyTests {
    @Test("derived report can never replace its raw input")
    func rejectsSameInputOutput() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let capture = directory.appendingPathComponent("capture.json")
        try Data("raw".utf8).write(to: capture)

        #expect(throws: PassiveBluetoothCaptureArtifactOutputPolicyError.outputMatchesInput(
            capture.standardizedFileURL.resolvingSymlinksInPath().path
        )) {
            try PassiveBluetoothCaptureArtifactOutputPolicy.validate(
                inputURL: capture,
                outputURL: capture,
                allowReplacingExistingOutput: true
            )
        }
    }

    @Test("symlink aliases cannot bypass raw-input protection")
    func rejectsSymlinkAliasOfInput() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let capture = directory.appendingPathComponent("capture.json")
        let alias = directory.appendingPathComponent("capture-alias.json")
        try Data("raw".utf8).write(to: capture)
        try FileManager.default.createSymbolicLink(
            at: alias,
            withDestinationURL: capture
        )

        #expect(throws: PassiveBluetoothCaptureArtifactOutputPolicyError.outputMatchesInput(
            capture.standardizedFileURL.resolvingSymlinksInPath().path
        )) {
            try PassiveBluetoothCaptureArtifactOutputPolicy.validate(
                inputURL: capture,
                outputURL: alias,
                allowReplacingExistingOutput: true
            )
        }
    }

    @Test("existing derived report is protected unless replacement is explicit")
    func protectsExistingReportByDefault() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let capture = directory.appendingPathComponent("capture.json")
        let report = directory.appendingPathComponent("report.json")
        try Data("raw".utf8).write(to: capture)
        try Data("old-report".utf8).write(to: report)

        #expect(throws: PassiveBluetoothCaptureArtifactOutputPolicyError.outputAlreadyExists(
            report.path
        )) {
            try PassiveBluetoothCaptureArtifactOutputPolicy.validate(
                inputURL: capture,
                outputURL: report,
                allowReplacingExistingOutput: false
            )
        }

        try PassiveBluetoothCaptureArtifactOutputPolicy.validate(
            inputURL: capture,
            outputURL: report,
            allowReplacingExistingOutput: true
        )
    }

    @Test("new distinct output path is accepted")
    func acceptsNewDistinctOutput() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let capture = directory.appendingPathComponent("capture.json")
        let report = directory.appendingPathComponent("report.json")
        try Data("raw".utf8).write(to: capture)

        try PassiveBluetoothCaptureArtifactOutputPolicy.validate(
            inputURL: capture,
            outputURL: report,
            allowReplacingExistingOutput: false
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nembra-report-policy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
