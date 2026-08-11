import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture foreground correlation evidence retention")
struct TuyaCaptureForegroundCorrelationEvidenceRetentionSourceTests {
    @Test("post-correlation foreground loss revokes target authority without erasing sealed evidence")
    func postCorrelationForegroundLossPreservesEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let foreground = String(try section(
            in: controller,
            from: "func appDidLoseForeground()",
            to: "var privateConfig: Bool"
        ))
        let cleanup = String(try section(
            in: foreground,
            from: "if phase == .correlated || phase == .selected",
            to: "guard let token = currentConnectionToken else"
        ))

        // Completed OFF1→ON1→OFF2→ON2 receipts are legitimate failed-attempt evidence.
        // Foreground loss must revoke reuse authority without deleting those receipts before export.
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

    @Test("post-correlation view exit revokes reuse authority without erasing sealed evidence")
    func postCorrelationViewExitPreservesEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
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
        #expect(cleanup.contains("phase == .correlated || phase == .selected"))
        #expect(cleanup.contains("pendingCorrelatedTargetID = nil"))
        #expect(cleanup.contains("selectedID = nil"))
        #expect(cleanup.contains("targetCorrelationOperatorConfirmed = false"))
        let completed = String(try section(
            in: cleanup,
            from: "if phase == .correlated || phase == .selected",
            to: "guard processCorrelationLease != nil || correlationSession != nil"
        ))
        #expect(!completed.contains("resetDiscoverySessionOnly()"))
        #expect(!completed.contains("correlationProvenance = nil"))
        #expect(!completed.contains("candidates.removeAll()"))
        #expect(completed.contains("target_correlation_abandoned_on_view_exit"))
    }

    @Test("failed diagnostic export still carries completed correlation provenance")
    func failedExportRetainsCompletedCorrelationEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let exportBuilder = String(try section(
            in: source,
            from: "private func makeExport(exportedAt:",
            to: "func prepareExport()"
        ))
        let prepareExport = String(try section(
            in: source,
            from: "func prepareExport()",
            to: "private func abandonPackageCorrelation()"
        ))

        #expect(exportBuilder.contains("targetCorrelationMethod: targetCorrelationMethod"))
        #expect(exportBuilder.contains("targetCorrelationWindowCount: targetCorrelationWindowCount"))
        #expect(exportBuilder.contains("targetCorrelationOperatorConfirmed: targetCorrelationOperatorConfirmed"))
        #expect(exportBuilder.contains("targetCorrelationProvenance: correlationProvenance"))
        #expect(exportBuilder.contains("candidates: candidates"))
        #expect(prepareExport.contains("makeExport("))
    }

    @Test("fresh OFF1 attempt remains the boundary that may clear prior failed-attempt correlation state")
    func freshAttemptOwnsCorrelationResetBoundary() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let begin = String(try section(
            in: controller,
            from: "private func beginCorrelationSeries()",
            to: "func startNextCorrelationWindow()"
        ))
        let retryAuthority = String(try section(
            in: controller,
            from: "var failedAttemptCanRestartFromOFF1: Bool",
            to: "func consumeCorrelationAsyncInvalidation()"
        ))

        #expect(begin.contains("resetDiscoverySessionOnly()"))
        #expect(retryAuthority.contains("OfficialTuyaFactory.packageCorrelationMayStart"))
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
