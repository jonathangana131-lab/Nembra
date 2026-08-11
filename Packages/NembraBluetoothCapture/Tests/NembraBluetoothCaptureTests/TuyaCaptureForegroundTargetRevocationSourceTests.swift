import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture foreground target-authority revocation")
struct TuyaCaptureForegroundTargetRevocationSourceTests {
    @Test("foreground loss preserves sealed correlation evidence while revoking mutable target authority")
    func foregroundLossCannotCarryCorrelatedTargetAcrossBoundary() throws {
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
        let activeCorrelation = String(try section(
            in: cleanup,
            from: "if processCorrelationLease != nil || correlationSession != nil",
            to: "if phase == .correlated || phase == .selected"
        ))
        let sealedCorrelation = String(try section(
            in: cleanup,
            from: "if phase == .correlated || phase == .selected",
            to: "guard let token = currentConnectionToken else"
        ))

        #expect(cleanup.contains("guard phase != .accepted else { return }"))

        #expect(activeCorrelation.contains("resetDiscoverySessionOnly()"))
        #expect(activeCorrelation.contains("phase = .failed"))
        #expect(activeCorrelation.contains("foreground_integrity_lost_during_target_correlation"))

        #expect(!sealedCorrelation.contains("resetDiscoverySessionOnly()"))
        #expect(sealedCorrelation.contains("pendingCorrelatedTargetID = nil"))
        #expect(sealedCorrelation.contains("selectedID = nil"))
        #expect(sealedCorrelation.contains("targetCorrelationOperatorConfirmed = false"))
        #expect(sealedCorrelation.contains("phase = .failed"))
        #expect(sealedCorrelation.contains("foreground_integrity_lost_after_target_correlation"))
        #expect(sealedCorrelation.contains("Completed correlation evidence remains available for diagnostics."))

        #expect(!cleanup.contains("releasePackageCorrelationLease()"))
    }

    @Test("membership copy is revoked with proof before request generations rotate")
    func membershipStatusCannotRemainVerifiedAfterViewOrForegroundRevocation() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))

        for (start, end) in [
            ("func abandonCorrelationForViewExit()", "func appDidLoseForeground()"),
            ("func appDidLoseForeground()", "var privateConfig: Bool")
        ] {
            let cleanup = String(try section(in: controller, from: start, to: end))
            let clearVerified = try #require(cleanup.range(of: "sdkDeviceMembershipVerified = false"))
            let resetStatus = try #require(cleanup.range(of: "membershipStatus = \"Exact scooter membership must be verified again"))
            let rotateRequest = try #require(cleanup.range(of: "membershipRequestID = UUID()"))
            #expect(clearVerified.lowerBound < resetStatus.lowerBound)
            #expect(resetStatus.lowerBound < rotateRequest.lowerBound)
            #expect(!cleanup.contains("membershipStatus = \"Exact scooter membership verified and leased to this current SDK account.\""))
        }
    }

    @Test("foreground reactivation cannot reopen membership after official driver handoff")
    func reactivationRequiresPackageCorrelationAuthority() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let activation = String(try section(
            in: controller,
            from: "func activateMembershipRequestsForView()",
            to: "func abandonCorrelationForViewExit()"
        ))

        #expect(activation.contains("guard currentConnectionToken == nil,"))
        #expect(activation.contains("OfficialTuyaFactory.packageCorrelationMayStart else { return }"))
        #expect(activation.range(of: "OfficialTuyaFactory.packageCorrelationMayStart")!.lowerBound < activation.range(of: "acceptsViewScopedMembershipRequests = true")!.lowerBound)
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

    private enum SourceContractError: Error { case sectionMissing }
}
