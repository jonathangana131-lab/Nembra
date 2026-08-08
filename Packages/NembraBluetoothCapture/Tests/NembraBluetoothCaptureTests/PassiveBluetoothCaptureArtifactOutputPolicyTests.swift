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
            try PassiveBluetoothCaptureArtifactOutputPolicy.writeDerivedReport(
                Data("derived".utf8), inputURL: capture, outputURL: capture,
                allowReplacingExistingOutput: true
            )
        }
        #expect(String(decoding: try Data(contentsOf: capture), as: UTF8.self) == "raw")
    }

    @Test("symlink aliases cannot bypass raw-input protection")
    func rejectsSymlinkAliasOfInput() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let capture = directory.appendingPathComponent("capture.json")
        let alias = directory.appendingPathComponent("capture-alias.json")
        try Data("raw".utf8).write(to: capture)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: capture)
        #expect(throws: PassiveBluetoothCaptureArtifactOutputPolicyError.outputMatchesInput(
            capture.standardizedFileURL.resolvingSymlinksInPath().path
        )) {
            try PassiveBluetoothCaptureArtifactOutputPolicy.writeDerivedReport(
                Data("derived".utf8), inputURL: capture, outputURL: alias,
                allowReplacingExistingOutput: true
            )
        }
        #expect(String(decoding: try Data(contentsOf: capture), as: UTF8.self) == "raw")
    }

    @Test("hard-link aliases cannot bypass raw-input protection")
    func rejectsHardLinkAliasOfInput() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let capture = directory.appendingPathComponent("capture.json")
        let alias = directory.appendingPathComponent("capture-hardlink.json")
        try Data("raw".utf8).write(to: capture)
        try FileManager.default.linkItem(at: capture, to: alias)
        #expect(throws: PassiveBluetoothCaptureArtifactOutputPolicyError.outputMatchesInput(
            capture.standardizedFileURL.resolvingSymlinksInPath().path
        )) {
            try PassiveBluetoothCaptureArtifactOutputPolicy.writeDerivedReport(
                Data("derived".utf8), inputURL: capture, outputURL: alias,
                allowReplacingExistingOutput: true
            )
        }
        #expect(String(decoding: try Data(contentsOf: capture), as: UTF8.self) == "raw")
        #expect(String(decoding: try Data(contentsOf: alias), as: UTF8.self) == "raw")
    }

    @Test("existing derived report remains byte-for-byte unchanged without force")
    func protectsExistingReportByDefault() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let capture = directory.appendingPathComponent("capture.json")
        let report = directory.appendingPathComponent("report.json")
        try Data("raw".utf8).write(to: capture)
        try Data("old-report".utf8).write(to: report)
        #expect(throws: PassiveBluetoothCaptureArtifactOutputPolicyError.outputAlreadyExists(report.path)) {
            try PassiveBluetoothCaptureArtifactOutputPolicy.writeDerivedReport(
                Data("new-report".utf8), inputURL: capture, outputURL: report,
                allowReplacingExistingOutput: false
            )
        }
        #expect(String(decoding: try Data(contentsOf: report), as: UTF8.self) == "old-report")
    }

    @Test("protected publication never follows an existing output symlink")
    func protectedPublicationDoesNotFollowOutputSymlink() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let capture = directory.appendingPathComponent("capture.json")
        let protectedTarget = directory.appendingPathComponent("protected.json")
        let report = directory.appendingPathComponent("report.json")
        try Data("raw".utf8).write(to: capture)
        try Data("protected".utf8).write(to: protectedTarget)
        try FileManager.default.createSymbolicLink(at: report, withDestinationURL: protectedTarget)
        #expect(throws: PassiveBluetoothCaptureArtifactOutputPolicyError.outputAlreadyExists(report.path)) {
            try PassiveBluetoothCaptureArtifactOutputPolicy.writeDerivedReport(
                Data("derived".utf8), inputURL: capture, outputURL: report,
                allowReplacingExistingOutput: false
            )
        }
        #expect(String(decoding: try Data(contentsOf: protectedTarget), as: UTF8.self) == "protected")
        #expect(FileManager.default.destinationOfSymbolicLink(atPath: report.path) == protectedTarget.path)
    }

    @Test("explicit force replaces only a distinct derived report")
    func forceReplacesDistinctReport() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let capture = directory.appendingPathComponent("capture.json")
        let report = directory.appendingPathComponent("report.json")
        try Data("raw".utf8).write(to: capture)
        try Data("old-report".utf8).write(to: report)
        try PassiveBluetoothCaptureArtifactOutputPolicy.writeDerivedReport(
            Data("new-report".utf8), inputURL: capture, outputURL: report,
            allowReplacingExistingOutput: true
        )
        #expect(String(decoding: try Data(contentsOf: capture), as: UTF8.self) == "raw")
        #expect(String(decoding: try Data(contentsOf: report), as: UTF8.self) == "new-report")
    }

    @Test("force replaces an output symlink entry without mutating its target")
    func forceReplacesSymlinkEntryNotTarget() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let capture = directory.appendingPathComponent("capture.json")
        let protectedTarget = directory.appendingPathComponent("protected.json")
        let report = directory.appendingPathComponent("report.json")
        try Data("raw".utf8).write(to: capture)
        try Data("protected".utf8).write(to: protectedTarget)
        try FileManager.default.createSymbolicLink(at: report, withDestinationURL: protectedTarget)
        try PassiveBluetoothCaptureArtifactOutputPolicy.writeDerivedReport(
            Data("derived".utf8), inputURL: capture, outputURL: report,
            allowReplacingExistingOutput: true
        )
        #expect(String(decoding: try Data(contentsOf: capture), as: UTF8.self) == "raw")
        #expect(String(decoding: try Data(contentsOf: protectedTarget), as: UTF8.self) == "protected")
        #expect(String(decoding: try Data(contentsOf: report), as: UTF8.self) == "derived")
    }

    @Test("new distinct output is published and temporary siblings are cleaned")
    func publishesNewDistinctOutput() throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let capture = directory.appendingPathComponent("capture.json")
        let report = directory.appendingPathComponent("report.json")
        try Data("raw".utf8).write(to: capture)
        try PassiveBluetoothCaptureArtifactOutputPolicy.writeDerivedReport(
            Data("derived".utf8), inputURL: capture, outputURL: report,
            allowReplacingExistingOutput: false
        )
        #expect(String(decoding: try Data(contentsOf: report), as: UTF8.self) == "derived")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names.sorted() == ["capture.json", "report.json"])
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nembra-report-policy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
