import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture foreground post-correlation revocation")
struct TuyaCaptureForegroundPostCorrelationRevocationSourceTests {
    @Test("correlated and selected target authority cannot cross foreground loss")
    func foregroundLossClearsCompletedCorrelationAuthority() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let cleanup = String(try section(
            in: controller,
            from: "func appDidLoseForeground()",
            to: "var privateConfig: Bool"
        ))

        let completedCorrelationCheck = try requiredOffset(
            containing: "if phase == .correlated || phase == .selected",
            in: cleanup
        )
        let tokenCheck = try requiredOffset(
            containing: "guard let token = currentConnectionToken else",
            in: cleanup
        )
        #expect(completedCorrelationCheck < tokenCheck)

        let branch = String(try section(
            in: cleanup,
            from: "if phase == .correlated || phase == .selected",
            to: "guard let token = currentConnectionToken else"
        ))
        #expect(branch.contains("resetDiscoverySessionOnly()"))
        #expect(branch.contains("phase = .failed"))
        #expect(branch.contains("foreground_integrity_lost_after_target_correlation"))
        #expect(branch.contains("Restart from OFF1") || branch.contains("restart from OFF1"))

        #expect(cleanup.contains("guard !foregroundIntegrityLossHandled else { return }"))
        #expect(cleanup.contains("Task { @MainActor [self] in"))
    }

    @Test("discovery reset actually clears all mutable correlated target authority")
    func discoveryResetClearsCorrelationAndSelectionEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let reset = String(try section(
            in: controller,
            from: "private func resetDiscoverySessionOnly()",
            to: "private func failLocally"
        ))

        for token in [
            "correlationProvenance = nil",
            "targetCorrelationMethod = nil",
            "targetCorrelationWindowCount = nil",
            "targetCorrelationOperatorConfirmed = false",
            "byID.removeAll()",
            "candidates.removeAll()",
            "selectedID = nil",
            "pendingCorrelatedTargetID = nil"
        ] {
            #expect(reset.contains(token), "reset must revoke completed target authority: \(token)")
        }
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw SourceContractError.sectionMissing
        }
        return range.lowerBound
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
