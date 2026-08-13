import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture membership-loss correlation authority revocation")
struct TuyaCaptureMembershipCorrelationAuthorityRevocationSourceTests {
    @Test("membership loss revokes completed target reuse without erasing sealed correlation evidence")
    func membershipLossRevokesTargetGrantAndPreservesEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let invalidation = String(try section(
            in: controller,
            from: "func invalidateSDKMembership()",
            to: "func verifySDKMembership"
        ))
        let completed = String(try section(
            in: invalidation,
            from: "if phase == .correlated || phase == .selected",
            to: "membershipStatus ="
        ))

        #expect(completed.contains("pendingCorrelatedTargetID = nil"))
        #expect(completed.contains("selectedID = nil"))
        #expect(completed.contains("targetCorrelationOperatorConfirmed = false"))
        #expect(completed.contains("phase = .failed"))
        #expect(completed.contains("sdk_membership_invalidated_after_target_correlation"))
        #expect(completed.contains("Restart from OFF1"))

        for forbidden in [
            "resetDiscoverySessionOnly()",
            "correlationProvenance = nil",
            "targetCorrelationMethod = nil",
            "targetCorrelationWindowCount = nil",
            "candidates.removeAll()",
        ] {
            #expect(!completed.contains(forbidden), "Membership loss must preserve sealed diagnostics: \(forbidden)")
        }
    }

    @Test("live in-progress correlation still owns scanner retirement")
    func liveCorrelationStillRetiresScanner() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let invalidation = String(try section(
            in: controller,
            from: "func invalidateSDKMembership()",
            to: "func verifySDKMembership"
        ))

        #expect(invalidation.contains("if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated"))
        #expect(invalidation.contains("abandonPackageCorrelation()"))
    }

    @Test("fresh OFF1 remains the explicit evidence reset boundary")
    func freshOFF1ResetsRetainedFailedAttemptEvidence() throws {
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
