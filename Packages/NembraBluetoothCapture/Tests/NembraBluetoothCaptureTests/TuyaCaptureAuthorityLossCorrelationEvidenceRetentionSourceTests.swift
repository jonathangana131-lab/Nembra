import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture sealed correlation evidence retention")
struct TuyaCaptureAuthorityLossCorrelationEvidenceRetentionSourceTests {
    @Test("foreground loss after sealed correlation revokes reuse authority without erasing evidence")
    func foregroundLossPreservesSealedCorrelationEvidence() throws {
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
        let completed = String(try section(
            in: foreground,
            from: "if phase == .correlated || phase == .selected",
            to: "guard let token = currentConnectionToken else"
        ))

        expectAuthorityRevokedWithoutEvidenceErasure(completed)
        #expect(completed.contains("revokeCompletedCorrelationReuseAuthority()"))
        #expect(completed.contains("foreground_integrity_lost_after_target_correlation"))
        #expect(completed.contains("Restart from OFF1"))
    }

    @Test("view exit after sealed correlation also revokes reuse authority without erasing evidence")
    func viewExitPreservesSealedCorrelationEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let exit = String(try section(
            in: controller,
            from: "func abandonCorrelationForViewExit()",
            to: "func appDidLoseForeground()"
        ))
        let completed = String(try section(
            in: exit,
            from: "if phase == .correlated || phase == .selected",
            to: "guard processCorrelationLease != nil || correlationSession != nil"
        ))

        expectAuthorityRevokedWithoutEvidenceErasure(completed)
        #expect(completed.contains("revokeCompletedCorrelationReuseAuthority()"))
        #expect(completed.contains("target_correlation_abandoned_on_view_exit"))
        #expect(completed.contains("Restart from OFF1"))
    }

    @Test("authority-only helper preserves completed proof and catalog while clearing reuse grants")
    func authorityOnlyHelperPreservesProofBytes() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let helper = String(try section(
            in: controller,
            from: "private func revokeCompletedCorrelationReuseAuthority()",
            to: "private func abandonPackageCorrelation()"
        ))

        #expect(helper.contains("pendingCorrelatedTargetID = nil"))
        #expect(helper.contains("selectedID = nil"))
        #expect(helper.contains("targetCorrelationOperatorConfirmed = false"))
        for forbidden in [
            "resetDiscoverySessionOnly()",
            "correlationProvenance = nil",
            "targetCorrelationMethod = nil",
            "targetCorrelationWindowCount = nil",
            "byID.removeAll()",
            "candidates.removeAll()",
            "abandonPackageCorrelation()",
        ] {
            #expect(!helper.contains(forbidden), "Authority-only revocation must preserve completed proof: \(forbidden)")
        }
    }

    @Test("failed diagnostic export retains completed correlation provenance")
    func failedExportRetainsCompletedCorrelationEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let exportBuilder = String(try section(
            in: source,
            from: "private func makeExport(exportedAt:",
            to: "func prepareExport()"
        ))

        #expect(exportBuilder.contains("targetCorrelationMethod: targetCorrelationMethod"))
        #expect(exportBuilder.contains("targetCorrelationWindowCount: targetCorrelationWindowCount"))
        #expect(exportBuilder.contains("targetCorrelationOperatorConfirmed: targetCorrelationOperatorConfirmed"))
        #expect(exportBuilder.contains("targetCorrelationProvenance: correlationProvenance"))
        #expect(exportBuilder.contains("candidates: candidates"))
        #expect(exportBuilder.contains("selectedPeripheralID: selectedID?.uuidString"))
    }

    @Test("fresh OFF1 remains the deliberate boundary that clears retained failed-attempt proof")
    func freshOFF1OwnsCorrelationResetBoundary() throws {
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

        #expect(begin.contains("resetDiscoverySessionOnly()"))
        #expect(begin.contains("OfficialTuyaFactory.packageCorrelationMayStart"))
    }

    private func expectAuthorityRevokedWithoutEvidenceErasure(_ source: String) {
        #expect(source.contains("phase = .failed"))
        for forbidden in [
            "resetDiscoverySessionOnly()",
            "correlationProvenance = nil",
            "targetCorrelationMethod = nil",
            "targetCorrelationWindowCount = nil",
            "candidates.removeAll()",
        ] {
            #expect(!source.contains(forbidden), "Completed correlation evidence must survive authority loss: \(forbidden)")
        }
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
