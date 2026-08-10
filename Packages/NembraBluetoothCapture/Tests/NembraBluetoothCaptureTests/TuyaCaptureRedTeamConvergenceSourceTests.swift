import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture current red-team convergence")
struct TuyaCaptureRedTeamConvergenceSourceTests {
    @Test("view exit revokes operator-facing membership status with proof")
    func viewExitRevokesMembershipStatusSynchronously() throws {
        let source = try entrypointSource()
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

        let clearVerified = try offset("sdkDeviceMembershipVerified = false", in: exit)
        let resetStatus = try offset("membershipStatus = \"Exact scooter membership must be verified again for this Secure Link session.\"", in: exit)
        let revokeRequest = try offset("membershipRequestID = UUID()", in: exit)
        #expect(clearVerified < resetStatus)
        #expect(resetStatus < revokeRequest)
        #expect(!exit.contains("membershipStatus = \"Exact scooter membership verified and leased to this current SDK account.\""))
    }

    @Test("application evidence cannot override Nembra-owned generation provenance")
    func trustedGenerationWinsApplicationKeyCollision() throws {
        let source = try entrypointSource()
        let receipt = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        #expect(receipt.contains("let custodySafeUpdate = Self.redactVerifiedAccountUID("))
        #expect(receipt.contains("log(\"tuya_application_update\", custodySafeUpdate.merging(["))
        #expect(receipt.contains("\"generation\": String(token.diagnosticGeneration)"))
        #expect(receipt.contains("]) { _, trusted in trusted })"))
        #expect(!receipt.contains("log(\"tuya_application_update\", update.merging(["))
        #expect(!receipt.contains("{ current, _ in current }"))
    }

    @Test("verified account UID is scrubbed from application keys and values before event custody")
    func accountUIDCannotEnterAcceptedApplicationEvent() throws {
        let source = try entrypointSource()
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let receipt = String(try section(
            in: controller,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))
        let secretFragments = String(try section(
            in: driver,
            from: "private static let secretKeyFragments = [",
            to: "private static func redactApplicationSecrets"
        ))

        #expect(controller.contains("<redacted-account-uid>"))
        #expect(controller.contains("private static func redactVerifiedAccountUID("))
        #expect(controller.contains("redactAccountUIDOccurrences(in: key, accountUID: accountUID)"))
        #expect(controller.contains("redactAccountUIDOccurrences(in: value, accountUID: accountUID)"))
        #expect(receipt.contains("let verifiedAccountUID = membershipAccountUID"))
        #expect(receipt.contains("let custodySafeUpdate = Self.redactVerifiedAccountUID("))
        #expect(!receipt.contains("log(\"tuya_application_update\", update.merging(["))

        #expect(!secretFragments.contains("\"uid\""))
        #expect(secretFragments.components(separatedBy: "\"sessionkey\"").count - 1 == 1)
    }

    @Test("foreground loss preserves sealed acceptance and invalidates post-correlation target authority")
    func foregroundLossClosesEveryMutableTargetState() throws {
        let source = try entrypointSource()
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

        let acceptedGuard = try offset("guard phase != .accepted else { return }", in: cleanup)
        let duplicateFence = try offset("guard !foregroundIntegrityLossHandled else { return }", in: cleanup)
        let closeAdmission = try offset("acceptsViewScopedMembershipRequests = false", in: cleanup)
        #expect(acceptedGuard < duplicateFence)
        #expect(duplicateFence < closeAdmission)

        let clearVerified = try offset("sdkDeviceMembershipVerified = false", in: cleanup)
        let resetStatus = try offset("membershipStatus = \"Exact scooter membership authority was revoked when Capture left the foreground; verify it again after returning to Capture.\"", in: cleanup)
        let revokeMembership = try offset("membershipRequestID = UUID()", in: cleanup)
        let revokeOfficial = try offset("officialConnectionRequestID = UUID()", in: cleanup)
        #expect(clearVerified < resetStatus)
        #expect(resetStatus < revokeMembership)
        #expect(revokeMembership < revokeOfficial)

        #expect(cleanup.contains("if phase == .correlated || phase == .selected"))
        #expect(cleanup.contains("resetDiscoverySessionOnly()"))
        #expect(cleanup.contains("foreground_integrity_lost_after_target_correlation"))
        #expect(cleanup.contains("abandonPackageCorrelation()"))
        #expect(cleanup.contains("invalidateObservationContinuity("))
        #expect(cleanup.contains("invalidateInternalLifecycle("))
        #expect(cleanup.contains("Task { @MainActor [self] in"))

        for forbidden in [
            "recordObservedTransportLoss",
            "endConnection(",
            "disconnectBLE",
            "writeValue",
            "publishDps",
            "queryDps",
            "releasePackageCorrelationLease("
        ] {
            #expect(!cleanup.contains(forbidden), "foreground loss gained forbidden authority: \(forbidden)")
        }
    }

    private func offset(_ token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw ContractError.missing
        }
        return range.lowerBound
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw ContractError.missing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func entrypointSource() throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(
            contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
    }

    private enum ContractError: Error { case missing }
}
