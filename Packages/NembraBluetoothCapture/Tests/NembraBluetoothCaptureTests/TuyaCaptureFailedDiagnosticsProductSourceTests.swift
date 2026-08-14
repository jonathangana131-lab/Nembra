import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture failed diagnostics product path")
struct TuyaCaptureFailedDiagnosticsProductSourceTests {
    @Test("both failed-state panels expose sanitized diagnostic preparation and share")
    func failedStatesExposeDiagnostics() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let recovery = String(try section(
            in: source,
            from: "private var failureRecoveryContextPanel: some View",
            to: "private var failurePanel: some View"
        ))
        let terminal = String(try section(
            in: source,
            from: "private var failurePanel: some View",
            to: "private var completionPanel: some View"
        ))
        let diagnostics = String(try section(
            in: source,
            from: "private var failureDiagnosticsControls: some View",
            to: "private var sdkAuthorizationPanel: some View"
        ))

        #expect(recovery.contains("failureDiagnosticsControls"))
        #expect(terminal.contains("failureDiagnosticsControls"))
        #expect(diagnostics.contains("test.prepareExport()"))
        #expect(diagnostics.contains("test.exportData"))
        #expect(diagnostics.contains("ShareLink"))
        #expect(diagnostics.contains("Share diagnostics"))
        #expect(diagnostics.contains("Prepare diagnostics"))
    }

    @Test("failed export remains mutable diagnostic evidence, never accepted artifact authority")
    func failedDiagnosticsUseMutableExportPathOnly() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let prepareExport = String(try section(
            in: source,
            from: "func prepareExport()",
            to: "private func abandonPackageCorrelation()"
        ))

        #expect(prepareExport.contains("if phase == .accepted"))
        #expect(prepareExport.contains("sealedAcceptedExport"))
        #expect(prepareExport.contains("makeExport("))
        #expect(prepareExport.contains("phase: phase"))
        #expect(prepareExport.contains("if phase != .failed"))
    }

    @Test("authoritative runbook explicitly expects failure diagnostics when available")
    func runbookAndProductStayCoupled() throws {
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        #expect(runbook.contains("On failure, share the sanitized diagnostic JSON if available and stop."))
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
