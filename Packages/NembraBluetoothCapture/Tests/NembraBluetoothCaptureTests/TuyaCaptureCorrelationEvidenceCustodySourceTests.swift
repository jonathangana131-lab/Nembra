import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture sealed correlation evidence custody")
struct TuyaCaptureCorrelationEvidenceCustodySourceTests {
    @Test("foreground loss revokes sealed target authority without erasing correlation evidence")
    func foregroundLossPreservesSealedEvidence() throws {
        let source = try entrypointSource()
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let cleanup = String(try section(
            in: controller,
            from: "if phase == .correlated || phase == .selected",
            to: "guard let token = currentConnectionToken else"
        ))

        #expect(!cleanup.contains("resetDiscoverySessionOnly()"))
        #expect(!cleanup.contains("correlationProvenance = nil"))
        #expect(!cleanup.contains("targetCorrelationMethod = nil"))
        #expect(!cleanup.contains("targetCorrelationWindowCount = nil"))
        #expect(!cleanup.contains("candidates.removeAll()"))
        #expect(cleanup.contains("pendingCorrelatedTargetID = nil"))
        #expect(cleanup.contains("selectedID = nil"))
        #expect(cleanup.contains("targetCorrelationOperatorConfirmed = false"))
        #expect(cleanup.contains("phase = .failed"))
        #expect(cleanup.contains("foreground_integrity_lost_after_target_correlation"))
        #expect(cleanup.contains("Restart from OFF1"))
    }

    @Test("view exit owns one terminal and preserves already-sealed correlation evidence")
    func viewExitRevokesAuthorityWithoutErasingEvidence() throws {
        let source = try entrypointSource()
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let cleanup = String(try section(
            in: controller,
            from: "func abandonCorrelationForViewExit()",
            to: "func appDidLoseForeground()"
        ))

        let terminalOwnership = String(try section(
            in: cleanup,
            from: "if foregroundIntegrityLossHandled { return }",
            to: "if let token = currentConnectionToken"
        ))
        #expect(terminalOwnership.contains("foregroundIntegrityLossHandled = true"))
        #expect(terminalOwnership.components(separatedBy: "foregroundIntegrityLossHandled = true").count == 2)

        let active = String(try section(
            in: cleanup,
            from: "if processCorrelationLease != nil || correlationSession != nil",
            to: "if phase == .correlated || phase == .selected"
        ))
        #expect(active.contains("abandonPackageCorrelation()"))
        #expect(active.contains("target_correlation_abandoned_on_view_exit"))

        let sealed = String(try section(
            in: cleanup,
            from: "if phase == .correlated || phase == .selected",
            to: "\n    }\n\n    func appDidLoseForeground()"
        ))
        #expect(!sealed.contains("resetDiscoverySessionOnly()"))
        #expect(!sealed.contains("correlationProvenance = nil"))
        #expect(!sealed.contains("targetCorrelationMethod = nil"))
        #expect(!sealed.contains("targetCorrelationWindowCount = nil"))
        #expect(!sealed.contains("candidates.removeAll()"))
        #expect(sealed.contains("pendingCorrelatedTargetID = nil"))
        #expect(sealed.contains("selectedID = nil"))
        #expect(sealed.contains("targetCorrelationOperatorConfirmed = false"))
        #expect(sealed.contains("target_correlation_retired_on_view_exit"))
    }

    @Test("failed diagnostic export retains sealed correlation provenance and fresh OFF1 owns reset")
    func exportAndFreshAttemptKeepCorrectBoundaries() throws {
        let source = try entrypointSource()
        let exportBuilder = String(try section(
            in: source,
            from: "private func makeExport(exportedAt:",
            to: "func prepareExport()"
        ))
        let begin = String(try section(
            in: source,
            from: "private func beginCorrelationSeries()",
            to: "func startNextCorrelationWindow()"
        ))

        #expect(exportBuilder.contains("targetCorrelationMethod: targetCorrelationMethod"))
        #expect(exportBuilder.contains("targetCorrelationWindowCount: targetCorrelationWindowCount"))
        #expect(exportBuilder.contains("targetCorrelationOperatorConfirmed: targetCorrelationOperatorConfirmed"))
        #expect(exportBuilder.contains("targetCorrelationProvenance: correlationProvenance"))
        #expect(exportBuilder.contains("candidates: candidates"))
        #expect(begin.contains("resetDiscoverySessionOnly()"))
    }

    private func entrypointSource() throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"), encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceError.missing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private enum SourceError: Error { case missing }
}