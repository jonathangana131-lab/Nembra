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
        let activeCorrelation = String(try section(
            in: cleanup,
            from: "if processCorrelationLease != nil || correlationSession != nil",
            to: "if phase == .correlated || phase == .selected"
        ))

        #expect(view.contains("@Environment(\\.scenePhase) private var scenePhase"))
        #expect(view.contains(".onChange(of: scenePhase)"))
        #expect(view.contains("if newPhase == .active"))
        #expect(view.contains("test.activateMembershipRequestsForView()"))
        #expect(view.contains("test.appDidLoseForeground()"))
        #expect(view.contains("if scenePhase == .active"))

        // Reactivation may not reopen view-scoped authority while the exact old authenticated
        // generation is still being terminally retired. Once official Tuya ownership has retired
        // package correlation for this process, an active transition also may not reopen admission.
        let retiredGenerationGate = try requiredOffset(
            containing: "guard currentConnectionToken == nil,",
            in: activation
        )
        let packageCorrelationOwnershipGate = try requiredOffset(
            containing: "OfficialTuyaFactory.packageCorrelationMayStart else { return }",
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
        #expect(retiredGenerationGate < packageCorrelationOwnershipGate)
        #expect(packageCorrelationOwnershipGate < resetForegroundFence)
        #expect(resetForegroundFence < reopenAdmission)
        #expect(viewExit.contains("if foregroundIntegrityLossHandled { return }"))

        let closeAdmission = try requiredOffset(
            containing: "acceptsViewScopedMembershipRequests = false",
            in: cleanup
        )
        let clearVerified = try requiredOffset(
            containing: "sdkDeviceMembershipVerified = false",
            in: cleanup
        )
        let clearAccountLease = try requiredOffset(
            containing: "membershipAccountUID = nil",
            in: cleanup
        )
        let clearDeviceLease = try requiredOffset(
            containing: "membershipDeviceID = nil",
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
        let correlationCheck = try requiredOffset(
            containing: "if processCorrelationLease != nil || correlationSession != nil",
            in: cleanup
        )
        let tokenCheck = try requiredOffset(
            containing: "guard let token = currentConnectionToken else",
            in: cleanup
        )

        #expect(closeAdmission < clearVerified)
        #expect(clearVerified < membershipRevoke)
        #expect(clearAccountLease < membershipRevoke)
        #expect(clearDeviceLease < membershipRevoke)
        #expect(membershipRevoke < officialRevoke)
        #expect(officialRevoke < correlationCheck)
        #expect(officialRevoke < tokenCheck)
        #expect(cleanup.contains("membershipBusy = false"))
        #expect(cleanup.contains("membershipProbe = nil"))
        #expect(cleanup.contains("watchdog?.cancel()"))
        #expect(cleanup.contains("foregroundIntegrityLossHandled = true"))

        // Active package correlation is retired through the full scanner-first discovery owner path.
        // That helper also erases actionable target-selection bits from the interrupted correlation.
        #expect(activeCorrelation.contains("resetDiscoverySessionOnly()"))
        #expect(activeCorrelation.contains("phase = .failed"))
        #expect(activeCorrelation.contains("foreground_integrity_lost_during_target_correlation"))
        #expect(activeCorrelation.contains("return"))
        #expect(!activeCorrelation.contains("releasePackageCorrelationLease("))

        // Any authenticated-generation terminal task must outlive StateObject teardown just like
        // the accepted view-exit retirement. Exact-token fencing still rejects stale generations.
        #expect(cleanup.contains("Task { @MainActor [self] in"))
        #expect(!cleanup.contains("Task { @MainActor [weak self] in"))
        #expect(cleanup.contains("guard self.currentConnectionToken == token else { return }"))
        #expect(cleanup.contains("invalidateObservationContinuity("))
        #expect(cleanup.contains("invalidateInternalLifecycle("))
        #expect(cleanup.contains("foreground_integrity_lost_during_observation"))
        #expect(cleanup.contains("foreground_integrity_lost_before_observation"))

        // Once OfficialTuyaFactory.make() has handed out the one process-global driver, package
        // OFF1 correlation cannot restart until relaunch. Recovery copy must not promise otherwise.
        #expect(cleanup.contains("Relaunch Capture before a new stationary read-only attempt"))
        #expect(!cleanup.contains("during authenticated observation. Restart from OFF1"))
        #expect(!cleanup.contains("before authenticated observation. Restart from OFF1"))

        // Foreground loss is an integrity/lifecycle event, never an inferred physical disconnect
        // or a reason to gain DP/query/write/control authority.
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
