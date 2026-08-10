import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture membership-loss correlation authority revocation")
struct TuyaCaptureMembershipCorrelationAuthorityRevocationSourceTests {
    @Test("membership loss revokes completed target reuse without erasing sealed evidence")
    func membershipLossRevokesTargetGrantAndPreservesEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let invalidation = String(try section(in: controller, from: "func invalidateSDKMembership()", to: "func verifySDKMembership"))
        let completed = String(try section(in: invalidation, from: "if phase == .correlated || phase == .selected", to: "membershipStatus ="))
        for required in ["pendingCorrelatedTargetID = nil", "selectedID = nil", "targetCorrelationOperatorConfirmed = false", "phase = .failed", "sdk_membership_invalidated_after_target_correlation", "Restart from OFF1"] {
            #expect(completed.contains(required))
        }
        for forbidden in ["resetDiscoverySessionOnly()", "correlationProvenance = nil", "targetCorrelationMethod = nil", "targetCorrelationWindowCount = nil", "candidates.removeAll()"] {
            #expect(!completed.contains(forbidden))
        }
        #expect(invalidation.contains("abandonPackageCorrelation()"))
    }

    @Test("fresh OFF1 remains the completed-evidence reset boundary")
    func freshOFF1OwnsReset() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let begin = String(try section(in: controller, from: "private func beginCorrelationSeries()", to: "func startNextCorrelationWindow()"))
        #expect(begin.contains("resetDiscoverySessionOnly()"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { throw SourceContractError.sectionMissing }
        return source[a.lowerBound..<b.lowerBound]
    }
    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
    private enum SourceContractError: Error { case sectionMissing }
}
