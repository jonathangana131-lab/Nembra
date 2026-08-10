import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture current foreground integrity")
struct TuyaCaptureForegroundIntegrityCurrentSourceTests {
    @Test("Secure Link owns scene-phase loss as explicit fail-closed authority")
    func secureLinkOwnsForegroundLoss() throws {
        let source = try entrypointSource()
        let view = String(try section(
            in: source,
            from: "private struct SecureLinkView: View",
            to: "private var hero: some View"
        ))
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))

        #expect(view.contains("@Environment(\\.scenePhase) private var scenePhase"))
        #expect(view.contains(".onChange(of: scenePhase)"))
        #expect(view.contains("if newPhase == .active"))
        #expect(view.contains("test.activateMembershipRequestsForView()"))
        #expect(view.contains("if sdkAccount.loggedIn { test.verifySDKMembership() }"))
        #expect(view.contains("test.appDidLoseForeground()"))
        #expect(controller.contains("func appDidLoseForeground()"))
    }

    @Test("foreground loss preserves sealed acceptance but revokes mutable evidence authority")
    func foregroundLossRevokesMutableAuthority() throws {
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

        #expect(cleanup.contains("guard phase != .accepted else { return }"))
        for proof in [
            "sdkDeviceMembershipVerified = false",
            "membershipAccountUID = nil",
            "membershipDeviceID = nil",
            "membershipRequestID = UUID()",
            "officialConnectionRequestID = UUID()"
        ] {
            #expect(cleanup.contains(proof), "foreground loss must revoke view/account authority: \(proof)")
        }
        #expect(cleanup.contains("watchdog?.cancel()"))
        #expect(cleanup.contains("abandonPackageCorrelation()"))
        #expect(cleanup.contains("invalidateObservationContinuity("))
        #expect(cleanup.contains("invalidateInternalLifecycle("))
        #expect(cleanup.contains("Task { @MainActor [self] in"))
        #expect(!cleanup.contains("recordObservedTransportLoss"))
        #expect(!cleanup.contains("endConnection"))
        #expect(!cleanup.contains("disconnectBLE"))
        #expect(!cleanup.contains("releasePackageCorrelationLease()"))
    }

    @Test("foreground loss invalidates already-correlated target state before retry")
    func correlatedTargetCannotCrossForegroundBoundary() throws {
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

        #expect(cleanup.contains("phase == .correlated || phase == .selected"))
        #expect(cleanup.contains("resetDiscoverySessionOnly()"))
        #expect(cleanup.contains("foreground_integrity_lost_after_target_correlation"))
    }

    private func entrypointSource() throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(
            contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw ContractError.missing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private enum ContractError: Error { case missing }
}
