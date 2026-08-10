import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture failed diagnostics product path")
struct TuyaCaptureFailedDiagnosticsProductSourceTests {
    @Test("every failed-state composition exposes sanitized diagnostic preparation and share")
    func failedStatesExposeDiagnostics() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let primarySurface = String(try section(
            in: source,
            from: "private var primarySurface: some View",
            to: "private var preflightPanel: some View"
        ))
        let diagnostics = String(try section(
            in: source,
            from: "private var failureDiagnosticsControls: some View",
            to: "private var sdkAuthorizationPanel: some View"
        ))

        #expect(primarySurface.contains("case .failed:"))
        #expect(primarySurface.components(separatedBy: "failureDiagnosticsControls").count - 1 >= 3)
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
