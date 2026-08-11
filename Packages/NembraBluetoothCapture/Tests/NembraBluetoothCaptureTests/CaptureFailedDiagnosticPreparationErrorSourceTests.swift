import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture failed-attempt diagnostic preparation error separation")
struct CaptureFailedDiagnosticPreparationErrorSourceTests {
    @Test("diagnostic encoding failure cannot replace the stopped-attempt cause")
    func failedAttemptPrimaryFailureRemainsPrimary() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let prepare = String(try section(
            in: source,
            from: "func prepareExport()",
            to: "private func abandonPackageCorrelation()"
        ))
        let catchRange = try #require(prepare.range(of: "} catch {"))
        let failureCatch = String(prepare[catchRange.lowerBound...])

        #expect(source.contains("diagnosticExportError"))
        #expect(failureCatch.contains("diagnosticExportError"))
        #expect(!failureCatch.contains("message = \"Diagnostic export failed:"))
        #expect(prepare.contains("phase == .failed"))
    }

    @Test("failed diagnostics surface exposes the secondary preparation error separately")
    func failedDiagnosticsUIKeepsBothTruthsVisible() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let failurePanel = String(try section(
            in: source,
            from: "private var failurePanel: some View",
            to: "private var completionPanel: some View"
        ))

        #expect(failurePanel.contains("Text(test.message)"))
        #expect(failurePanel.contains("test.diagnosticExportError"))
        #expect(failurePanel.contains("Prepare diagnostics"))
        #expect(failurePanel.contains("stopped attempt"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
