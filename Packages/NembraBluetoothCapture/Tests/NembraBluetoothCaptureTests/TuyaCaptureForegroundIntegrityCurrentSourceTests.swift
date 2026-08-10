import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture current foreground integrity")
struct TuyaCaptureForegroundIntegrityCurrentSourceTests {
    @Test("foreground loss revokes view authority and retires the exact generation once")
    func foregroundLossFailsClosedWithoutCompetingViewExitTerminal() throws {
        let source = try repositorySource()
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let cleanup = String(try section(in: controller, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))
        let exit = String(try section(in: controller, from: "func abandonCorrelationForViewExit()", to: "func appDidLoseForeground()"))
        let view = String(try section(in: source, from: "private struct SecureLinkView: View", to: "private var hero: some View"))

        #expect(view.contains("@Environment(\\.scenePhase) private var scenePhase"))
        #expect(view.contains(".onChange(of: scenePhase)"))
        #expect(view.contains("if newPhase != .active"))
        #expect(view.contains("test.appDidLoseForeground()"))
        #expect(view.contains("if scenePhase != .active {"))
        #expect(view.contains("if scenePhase == .active, sdkAccount.loggedIn"))

        let closeAdmission = try offset("acceptsViewScopedMembershipRequests = false", in: cleanup)
        let revokeProof = try offset("sdkDeviceMembershipVerified = false", in: cleanup)
        let revokeMembershipRequest = try offset("membershipRequestID = UUID()", in: cleanup)
        let revokeOfficialRequest = try offset("officialConnectionRequestID = UUID()", in: cleanup)
        let inspectCorrelation = try offset("if processCorrelationLease != nil || correlationSession != nil", in: cleanup)
        #expect(closeAdmission < revokeProof)
        #expect(revokeProof < revokeMembershipRequest)
        #expect(revokeMembershipRequest < inspectCorrelation)
        #expect(revokeOfficialRequest < inspectCorrelation)
        #expect(cleanup.contains("membershipAccountUID = nil"))
        #expect(cleanup.contains("membershipDeviceID = nil"))
        #expect(cleanup.contains("membershipStatus = \"Exact scooter membership authority was revoked when Capture left the foreground; it must be freshly verified before use.\""))
        #expect(cleanup.contains("guard hadViewAuthority else { return }"))

        #expect(cleanup.contains("foregroundIntegrityRequiresRelaunch = true"))
        #expect(cleanup.contains("foregroundRetirementToken = token"))
        #expect(cleanup.contains("abandonPackageCorrelation()"))
        #expect(cleanup.contains("invalidateObservationContinuity("))
        #expect(cleanup.contains("invalidateInternalLifecycle("))
        #expect(cleanup.contains("Task { @MainActor [self] in"))
        #expect(!cleanup.contains("Task { @MainActor [weak self]"))
        #expect(!cleanup.contains("recordObservedTransportLoss"))
        #expect(!cleanup.contains("endConnection("))
        #expect(!cleanup.contains("disconnectBLE("))

        let joined = try offset("if foregroundRetirementToken == token", in: exit)
        let viewExitTerminal = try offset("Task { @MainActor [self] in", in: exit)
        #expect(exit.contains("view_exit_joined_foreground_retirement"))
        #expect(joined < viewExitTerminal)
    }

    @Test("only a foreground-integrity failure blocks scene reactivation membership admission")
    func foregroundRelaunchLatchIsSpecific() throws {
        let source = try repositorySource()
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let activation = String(try section(in: controller, from: "func activateMembershipRequestsForView()", to: "func abandonCorrelationForViewExit()"))
        #expect(activation.contains("guard !foregroundIntegrityRequiresRelaunch else { return }"))
        #expect(!activation.contains("guard phase != .failed"))
    }

    private func offset(_ token: String, in source: String) throws -> String.Index {
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

    private func repositorySource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
