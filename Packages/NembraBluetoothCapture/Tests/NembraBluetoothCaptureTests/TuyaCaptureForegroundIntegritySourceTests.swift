import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture foreground-integrity source contract")
struct TuyaCaptureForegroundIntegritySourceTests {
    @Test("Secure Link fail-closes foreground loss and re-earns membership only while active")
    func secureLinkOwnsForegroundIntegrity() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let view = String(try section(
            in: source,
            from: "private struct SecureLinkView: View",
            to: "private var hero: some View"
        ))
        let activation = String(try section(
            in: controller,
            from: "func activateMembershipRequestsForView()",
            to: "func abandonCorrelationForViewExit()"
        ))
        let viewExit = String(try section(
            in: controller,
            from: "func abandonCorrelationForViewExit()",
            to: "func appDidLoseForeground()"
        ))
        let cleanup = String(try section(
            in: controller,
            from: "func appDidLoseForeground()",
            to: "var privateConfig: Bool"
        ))

        #expect(view.contains("@Environment(\\.scenePhase) private var scenePhase"))
        #expect(view.contains(".onChange(of: scenePhase)"))
        #expect(view.contains("if newPhase == .active"))
        #expect(view.contains("test.activateMembershipRequestsForView()"))
        #expect(view.contains("test.appDidLoseForeground()"))
        #expect(view.contains("if scenePhase == .active"))

        let retiredGenerationGate = try requiredOffset(
            containing: "guard currentConnectionToken == nil else { return }",
            in: activation
        )
        let resetForegroundFence = try requiredOffset(
            containing: "foregroundIntegrityLossHandled = false",
            in: activation
        )
        let reopenAdmission = try requiredOffset(
            containing: "acceptsViewScopedMembershipRequests = true",
            in: activation
        )
        #expect(retiredGenerationGate < resetForegroundFence)
        #expect(resetForegroundFence < reopenAdmission)
        #expect(viewExit.contains("if foregroundIntegrityLossHandled { return }"))

        let acceptedGuard = try requiredOffset(
            containing: "guard phase != .accepted else { return }",
            in: cleanup
        )
        let setForegroundFence = try requiredOffset(
            containing: "foregroundIntegrityLossHandled = true",
            in: cleanup
        )
        let closeAdmission = try requiredOffset(
            containing: "acceptsViewScopedMembershipRequests = false",
            in: cleanup
        )
        let clearVerified = try requiredOffset(
            containing: "sdkDeviceMembershipVerified = false",
            in: cleanup
        )
        let membershipRevoke = try requiredOffset(
            containing: "membershipRequestID = UUID()",
            in: cleanup
        )
        let officialRevoke = try requiredOffset(
            containing: "officialConnectionRequestID = UUID()",
            in: cleanup
        )
        #expect(acceptedGuard < setForegroundFence)
        #expect(setForegroundFence < closeAdmission)
        #expect(closeAdmission < clearVerified)
        #expect(clearVerified < membershipRevoke)
        #expect(membershipRevoke < officialRevoke)
        #expect(cleanup.contains("membershipAccountUID = nil"))
        #expect(cleanup.contains("membershipDeviceID = nil"))
        #expect(cleanup.contains("membershipBusy = false"))
        #expect(cleanup.contains("membershipProbe = nil"))
        #expect(cleanup.contains("watchdog?.cancel()"))

        // Foreground loss after a fully sealed correlation, but before official Tuya handoff,
        // must not let correlated/selected target authority cross the interruption.
        #expect(cleanup.contains("phase == .correlated || phase == .selected"))
        #expect(cleanup.contains("resetDiscoverySessionOnly()"))
        #expect(cleanup.contains("foreground_integrity_lost_after_target_correlation"))
        let postCorrelationReset = try requiredOffset(
            containing: "resetDiscoverySessionOnly()",
            in: cleanup
        )
        let tokenCheck = try requiredOffset(
            containing: "guard let token = currentConnectionToken else",
            in: cleanup
        )
        #expect(postCorrelationReset < tokenCheck)

        // In-flight package target correlation still retires scanner-first.
        #expect(cleanup.contains("abandonPackageCorrelation()"))
        #expect(cleanup.contains("foreground_integrity_lost_during_target_correlation"))
        #expect(!cleanup.contains("releasePackageCorrelationLease("))

        // Authenticated-generation retirement keeps exact-token fencing and strong lifetime.
        #expect(cleanup.contains("Task { @MainActor [self] in"))
        #expect(!cleanup.contains("Task { @MainActor [weak self] in"))
        #expect(cleanup.contains("guard self.currentConnectionToken == token else { return }"))
        #expect(cleanup.contains("invalidateObservationContinuity("))
        #expect(cleanup.contains("invalidateInternalLifecycle("))
        #expect(cleanup.contains("Relaunch Capture before a new stationary read-only attempt"))

        for forbidden in [
            "recordObservedTransportLoss",
            "endConnection(",
            "disconnectBLE",
            "writeValue",
            "publishDps",
            "queryDps",
        ] {
            #expect(!cleanup.contains(forbidden))
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

    private enum SourceContractError: Error { case sectionMissing }
}
