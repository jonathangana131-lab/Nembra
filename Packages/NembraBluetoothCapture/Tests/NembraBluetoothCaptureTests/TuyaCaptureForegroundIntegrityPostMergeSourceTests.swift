import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture foreground-integrity post-merge closure")
struct TuyaCaptureForegroundIntegrityPostMergeSourceTests {
    @Test("foreground loss preserves sealed acceptance and destroys correlated target authority")
    func foregroundLossCannotDemoteAcceptedOrReuseCorrelatedTarget() throws {
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

        #expect(cleanup.contains("guard phase != .accepted else { return }"))
        #expect(cleanup.contains("phase == .correlated || phase == .selected"))
        #expect(cleanup.contains("resetDiscoverySessionOnly()"))
        #expect(cleanup.contains("foreground_integrity_lost_after_target_correlation"))
    }

    @Test("foreground loss revokes operator-facing membership proof copy before request rotation")
    func foregroundLossCannotDisplayRevokedMembershipAsVerified() throws {
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

        let clearVerified = try requiredOffset(
            containing: "sdkDeviceMembershipVerified = false",
            in: cleanup
        )
        let resetStatus = try requiredOffset(
            containing: "membershipStatus =",
            in: cleanup
        )
        let rotateMembership = try requiredOffset(
            containing: "membershipRequestID = UUID()",
            in: cleanup
        )

        #expect(clearVerified < resetStatus)
        #expect(resetStatus < rotateMembership)
        #expect(
            cleanup.contains("must be verified again")
                || cleanup.contains("must be reverified")
                || cleanup.contains("re-verify")
        )
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw ContractError.missing
        }
        return range.lowerBound
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw ContractError.missing
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

    private enum ContractError: Error { case missing }
}
