import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture foreground integrity source contract")
struct TuyaCaptureForegroundIntegritySourceTests {
    @Test("Secure Link fail-closes foreground loss without reopening post-handoff authority")
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
        let loss = String(try section(
            in: controller,
            from: "func appDidLoseForeground()",
            to: "func appDidRegainForeground()"
        ))
        let regain = String(try section(
            in: controller,
            from: "func appDidRegainForeground()",
            to: "var privateConfig: Bool"
        ))
        let exit = String(try section(
            in: controller,
            from: "func abandonCorrelationForViewExit()",
            to: "func appDidLoseForeground()"
        ))

        #expect(view.contains("@Environment(\\.scenePhase) private var scenePhase"))
        #expect(view.contains(".onChange(of: scenePhase)"))
        #expect(view.contains("test.appDidLoseForeground()"))
        #expect(view.contains("test.appDidRegainForeground()"))

        // Initial view construction is also a foreground boundary. A task that unconditionally
        // opens membership authority before scenePhase is known would recreate the hidden-start race.
        let initialTask = String(try section(in: view, from: ".task {", to: ".onDisappear {"))
        let activeGuard = try requiredOffset(containing: "if scenePhase == .active", in: initialTask)
        let admissionOpen = try requiredOffset(containing: "test.activateMembershipRequestsForView()", in: initialTask)
        #expect(activeGuard < admissionOpen)
        #expect(initialTask.contains("else {"))
        #expect(initialTask.contains("test.appDidLoseForeground()"))
        #expect(initialTask.contains("if scenePhase == .active, sdkAccount.loggedIn { test.verifySDKMembership() }"))

        // Foreground loss first closes all screen-scoped account/membership admission and proof.
        let admissionClose = try requiredOffset(containing: "acceptsViewScopedMembershipRequests = false", in: loss)
        let membershipRevoke = try requiredOffset(containing: "membershipRequestID = UUID()", in: loss)
        let officialRevoke = try requiredOffset(containing: "officialConnectionRequestID = UUID()", in: loss)
        let correlationCheck = try requiredOffset(containing: "if processCorrelationLease != nil || correlationSession != nil", in: loss)
        #expect(admissionClose < membershipRevoke)
        #expect(membershipRevoke < correlationCheck)
        #expect(officialRevoke < correlationCheck)
        #expect(loss.contains("sdkDeviceMembershipVerified = false"))
        #expect(loss.contains("membershipAccountUID = nil"))
        #expect(loss.contains("membershipDeviceID = nil"))
        #expect(loss.contains("membershipBusy = false"))
        #expect(loss.contains("membershipProbe = nil"))
        #expect(loss.contains("watchdog?.cancel()"))

        // Package correlation may be discarded and restarted from a fresh OFF1 before Tuya handoff.
        #expect(loss.contains("abandonPackageCorrelation()"))
        #expect(loss.contains("Restart from OFF1"))
        #expect(!loss.contains("releasePackageCorrelationLease()"))

        // Any post-handoff generation requires process relaunch, and lifecycle hooks share one
        // exact-token retirement admission so inactive→background/onDisappear cannot double-retire.
        #expect(controller.contains("private var lifecycleRetirementToken: TuyaReadOnlyConnectionToken?"))
        #expect(loss.contains("lifecycleRetirementToken == token"))
        #expect(exit.contains("lifecycleRetirementToken == token"))
        #expect(loss.contains("lifecycleRetirementToken = token"))
        #expect(exit.contains("lifecycleRetirementToken = token"))
        #expect(loss.contains("Task { @MainActor [self] in"))
        #expect(exit.contains("Task { @MainActor [self] in"))
        #expect(!loss.contains("[weak self]"))
        #expect(loss.contains("Relaunch before another authenticated stationary read-only attempt"))
        let tokenSection = String(loss[(try requiredRange(containing: "guard let token = currentConnectionToken", in: loss)).lowerBound...])
        #expect(!tokenSection.contains("Restart from OFF1"))
        #expect(loss.contains("invalidateObservationContinuity("))
        #expect(loss.contains("invalidateInternalLifecycle("))
        #expect(!loss.contains("recordObservedTransportLoss"))
        #expect(!loss.contains("endConnection"))

        // Returning active can reopen membership admission only while package correlation is still
        // process-legal; a prior official driver handoff permanently keeps that path closed.
        #expect(regain.contains("OfficialTuyaFactory.packageCorrelationMayStart"))
        #expect(regain.contains("currentConnectionToken == nil"))
        #expect(regain.contains("driver == nil"))
        #expect(regain.contains("acceptsViewScopedMembershipRequests = true"))
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw SourceContractError.sectionMissing
        }
        return range.lowerBound
    }

    private func requiredRange(containing token: String, in source: String) throws -> Range<String.Index> {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw SourceContractError.sectionMissing
        }
        return range
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
