import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture foreground integrity source contract")
struct TuyaCaptureForegroundIntegritySourceTests {
    @Test("Secure Link scene activity fences view-scoped request and capture authority")
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
            to: "func appDidBecomeActiveForView()"
        ))
        let active = String(try section(
            in: controller,
            from: "func appDidBecomeActiveForView()",
            to: "var privateConfig: Bool"
        ))

        #expect(view.contains("@Environment(\\.scenePhase) private var scenePhase"))
        #expect(view.contains(".onChange(of: scenePhase)"))
        #expect(view.contains("test.appDidLoseForeground()"))
        #expect(view.contains("test.appDidBecomeActiveForView()"))
        #expect(view.contains("if sdkAccount.loggedIn { test.verifySDKMembership() }"))

        #expect(loss.contains("guard foregroundIntegrityIsActive else { return }"))
        #expect(loss.contains("foregroundIntegrityIsActive = false"))
        #expect(loss.contains("acceptsViewScopedMembershipRequests = false"))
        #expect(loss.contains("sdkDeviceMembershipVerified = false"))
        #expect(loss.contains("membershipAccountUID = nil"))
        #expect(loss.contains("membershipDeviceID = nil"))

        let admissionClose = try requiredOffset(containing: "acceptsViewScopedMembershipRequests = false", in: loss)
        let membershipRevoke = try requiredOffset(containing: "membershipRequestID = UUID()", in: loss)
        let officialRevoke = try requiredOffset(containing: "officialConnectionRequestID = UUID()", in: loss)
        let correlationCheck = try requiredOffset(containing: "if processCorrelationLease != nil || correlationSession != nil", in: loss)
        #expect(admissionClose < membershipRevoke)
        #expect(membershipRevoke < correlationCheck)
        #expect(officialRevoke < correlationCheck)
        #expect(loss.contains("membershipBusy = false"))
        #expect(loss.contains("membershipProbe = nil"))
        #expect(loss.contains("watchdog?.cancel()"))

        #expect(loss.contains("abandonPackageCorrelation()"))
        #expect(loss.contains("foreground_integrity_lost_during_target_correlation"))
        #expect(!loss.contains("releasePackageCorrelationLease()"))

        #expect(loss.contains("Task { @MainActor [self] in"))
        #expect(!loss.contains("Task { @MainActor [weak self] in"))
        #expect(loss.contains("self.currentConnectionToken == token"))
        #expect(loss.contains("invalidateObservationContinuity("))
        #expect(loss.contains("foreground_integrity_lost_during_observation"))
        #expect(loss.contains("invalidateInternalLifecycle("))
        #expect(loss.contains("foreground_integrity_lost_before_observation"))
        #expect(!loss.contains("recordObservedTransportLoss"))
        #expect(!loss.contains("endConnection"))
        #expect(!loss.contains("disconnect"))

        // Returning active can only reopen view-scoped membership request admission. It must not
        // recreate evidence/transport authority or restore the revoked membership proof itself.
        #expect(active.contains("foregroundIntegrityIsActive = true"))
        #expect(active.contains("acceptsViewScopedMembershipRequests = true"))
        for forbidden in [
            "sdkDeviceMembershipVerified = true",
            "membershipAccountUID =",
            "membershipDeviceID =",
            "beginCorrelationSeries",
            "beginOfficialConnection",
            "connectBLE",
            "currentConnectionToken =",
            "processCorrelationLease ="
        ] {
            #expect(!active.contains(forbidden), "foreground recovery must not restore authority: \(forbidden)")
        }
    }

    @Test("initial Secure Link task obeys current scene activity")
    func initialViewAdmissionIsSceneAware() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let view = String(try section(
            in: source,
            from: "private struct SecureLinkView: View",
            to: "private var hero: some View"
        ))
        let task = String(try section(in: view, from: ".task {", to: ".onDisappear {"))

        #expect(task.contains("if scenePhase == .active"))
        #expect(task.contains("test.appDidBecomeActiveForView()"))
        #expect(task.contains("test.appDidLoseForeground()"))
        #expect(task.contains("if scenePhase == .active, sdkAccount.loggedIn"))
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
