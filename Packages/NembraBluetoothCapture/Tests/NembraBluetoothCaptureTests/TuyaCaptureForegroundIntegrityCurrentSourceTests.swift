import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture current foreground integrity")
struct TuyaCaptureForegroundIntegrityCurrentSourceTests {
    @Test("Secure Link owns scene-phase loss and fresh foreground return authority")
    func secureLinkOwnsForegroundLoss() throws {
        let source = try entrypointSource()
        let view = String(try section(in: source, from: "private struct SecureLinkView: View", to: "private var hero: some View"))
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))

        #expect(view.contains("@Environment(\\.scenePhase) private var scenePhase"))
        #expect(view.contains(".onChange(of: scenePhase)"))
        #expect(view.contains("if newPhase == .active"))
        #expect(view.contains("test.activateMembershipRequestsForView()"))
        #expect(view.contains("if sdkAccount.loggedIn { test.verifySDKMembership() }"))
        #expect(view.contains("test.appDidLoseForeground()"))
        #expect(controller.contains("func appDidLoseForeground()"))
    }

    @Test("foreground loss preserves sealed acceptance but revokes mutable authority before transport inspection")
    func foregroundLossRevokesMutableAuthority() throws {
        let source = try entrypointSource()
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let cleanup = String(try section(in: controller, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))

        #expect(cleanup.contains("guard phase != .accepted else { return }"))
        let membershipAdmissionClose = try requiredOffset("acceptsViewScopedMembershipRequests = false", in: cleanup)
        let proofClear = try requiredOffset("sdkDeviceMembershipVerified = false", in: cleanup)
        let statusReset = try requiredOffset("membershipStatus =", in: cleanup)
        let membershipRevoke = try requiredOffset("membershipRequestID = UUID()", in: cleanup)
        let officialRevoke = try requiredOffset("officialConnectionRequestID = UUID()", in: cleanup)
        let correlationCheck = try requiredOffset("if processCorrelationLease != nil || correlationSession != nil", in: cleanup)
        #expect(membershipAdmissionClose < correlationCheck)
        #expect(proofClear < correlationCheck)
        #expect(statusReset < correlationCheck)
        #expect(membershipRevoke < correlationCheck)
        #expect(officialRevoke < correlationCheck)
        #expect(cleanup.contains("membershipAccountUID = nil"))
        #expect(cleanup.contains("membershipDeviceID = nil"))
        #expect(cleanup.contains("membershipBusy = false"))
        #expect(cleanup.contains("membershipProbe = nil"))
        #expect(cleanup.contains("watchdog?.cancel()"))
        #expect(cleanup.contains("resetDiscoverySessionOnly()"))
        #expect(cleanup.contains("invalidateObservationContinuity("))
        #expect(cleanup.contains("invalidateInternalLifecycle("))
        #expect(cleanup.contains("Task { @MainActor [self] in"))
        #expect(!cleanup.contains("recordObservedTransportLoss"))
        #expect(!cleanup.contains("endConnection"))
        #expect(!cleanup.contains("disconnectBLE"))
        #expect(!cleanup.contains("releasePackageCorrelationLease()"))
    }

    @Test("already correlated target authority cannot cross foreground boundary")
    func correlatedTargetCannotCrossForegroundBoundary() throws {
        let source = try entrypointSource()
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let cleanup = String(try section(in: controller, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))
        #expect(cleanup.contains("phase == .correlated || phase == .selected"))
        #expect(cleanup.contains("resetDiscoverySessionOnly()"))
        #expect(cleanup.contains("foreground_integrity_lost_after_target_correlation"))
    }

    private func requiredOffset(_ token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else { throw ContractError.missing }
        return range.lowerBound
    }

    private func entrypointSource() throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"), encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { throw ContractError.missing }
        return source[a.lowerBound..<b.lowerBound]
    }

    private enum ContractError: Error { case missing }
}
