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
        let correlationRevocation = String(try section(
            in: controller,
            from: "private func revokeTargetCorrelationAuthorityForForegroundLoss()",
            to: "private func releasePackageCorrelationLease()"
        ))

        #expect(view.contains("@Environment(\\.scenePhase) private var scenePhase"))
        #expect(view.contains(".onChange(of: scenePhase)"))
        #expect(view.contains("if newPhase == .active"))
        #expect(view.contains("test.activateMembershipRequestsForView()"))
        #expect(view.contains("test.appDidLoseForeground()"))
        #expect(view.contains("if scenePhase == .active"))

        // Reactivation may not reopen view-scoped authority while the exact old authenticated
        // generation is still being terminally retired. Otherwise an active transition can reset
        // the duplicate-retirement fence before a following onDisappear arrives.
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

        // View exit revokes both authority and its operator-facing status synchronously.
        let viewExitClearVerified = try requiredOffset(
            containing: "sdkDeviceMembershipVerified = false",
            in: viewExit
        )
        let viewExitStatusReset = try requiredOffset(
            containing: "membershipStatus = \"Exact scooter membership must be verified again for this Secure Link session.\"",
            in: viewExit
        )
        let viewExitMembershipRevoke = try requiredOffset(
            containing: "membershipRequestID = UUID()",
            in: viewExit
        )
        #expect(viewExitClearVerified < viewExitStatusReset)
        #expect(viewExitStatusReset < viewExitMembershipRevoke)
        #expect(!viewExit.contains("verified and leased"))

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
        let statusReset = try requiredOffset(
            containing: "membershipStatus = \"Exact scooter membership must be verified again for this Secure Link session.\"",
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
        let correlatedAuthorityCheck = try requiredOffset(
            containing: "if phase == .correlated || phase == .selected || correlationProvenance != nil || selectedID != nil || pendingCorrelatedTargetID != nil",
            in: cleanup
        )
        let tokenCheck = try requiredOffset(
            containing: "guard let token = currentConnectionToken else",
            in: cleanup
        )

        #expect(closeAdmission < clearVerified)
        #expect(clearVerified < statusReset)
        #expect(clearAccountLease < statusReset)
        #expect(clearDeviceLease < statusReset)
        #expect(statusReset < membershipRevoke)
        #expect(membershipRevoke < officialRevoke)
        #expect(officialRevoke < correlationCheck)
        #expect(correlationCheck < correlatedAuthorityCheck)
        #expect(correlatedAuthorityCheck < tokenCheck)
        #expect(cleanup.contains("membershipBusy = false"))
        #expect(cleanup.contains("membershipProbe = nil"))
        #expect(cleanup.contains("watchdog?.cancel()"))
        #expect(cleanup.contains("foregroundIntegrityLossHandled = true"))

        // Both in-flight and already-completed/selected package correlation authority are retired.
        #expect(cleanup.contains("revokeTargetCorrelationAuthorityForForegroundLoss()"))
        #expect(cleanup.contains("foreground_integrity_lost_during_target_correlation"))
        #expect(cleanup.contains("foreground_integrity_lost_after_target_correlation"))
        #expect(!cleanup.contains("releasePackageCorrelationLease("))

        // Correlation revocation must stop package transport first, then erase every target-authority
        // projection that could otherwise survive a StateObject foreground interruption.
        let stopPackage = try requiredOffset(containing: "abandonPackageCorrelation()", in: correlationRevocation)
        let clearProvenance = try requiredOffset(containing: "correlationProvenance = nil", in: correlationRevocation)
        let clearMethod = try requiredOffset(containing: "targetCorrelationMethod = nil", in: correlationRevocation)
        let clearWindowCount = try requiredOffset(containing: "targetCorrelationWindowCount = nil", in: correlationRevocation)
        let clearConfirmation = try requiredOffset(containing: "targetCorrelationOperatorConfirmed = false", in: correlationRevocation)
        let clearCandidateMap = try requiredOffset(containing: "byID.removeAll()", in: correlationRevocation)
        let clearCandidates = try requiredOffset(containing: "candidates.removeAll()", in: correlationRevocation)
        let clearSelected = try requiredOffset(containing: "selectedID = nil", in: correlationRevocation)
        let clearPending = try requiredOffset(containing: "pendingCorrelatedTargetID = nil", in: correlationRevocation)
        #expect(stopPackage < clearProvenance)
        #expect(clearProvenance < clearMethod)
        #expect(clearMethod < clearWindowCount)
        #expect(clearWindowCount < clearConfirmation)
        #expect(clearConfirmation < clearCandidateMap)
        #expect(clearCandidateMap < clearCandidates)
        #expect(clearCandidates < clearSelected)
        #expect(clearSelected < clearPending)

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
