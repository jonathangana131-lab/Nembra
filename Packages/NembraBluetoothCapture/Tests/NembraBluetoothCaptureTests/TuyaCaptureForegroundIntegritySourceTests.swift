import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture foreground integrity source contract")
struct TuyaCaptureForegroundIntegritySourceTests {
    @Test("Secure Link treats inactive and background as authority loss")
    func sceneActivityOwnsEvidenceAdmission() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let view = String(try section(
            in: source,
            from: "private struct SecureLinkView: View",
            to: "private var hero: some View"
        ))

        #expect(view.contains("@Environment(\\.scenePhase) private var scenePhase"))
        #expect(view.contains(".onChange(of: scenePhase)"))
        #expect(view.contains("if newPhase == .active"))
        #expect(view.contains("test.activateMembershipRequestsForView()"))
        #expect(view.contains("test.appDidLoseForeground()"))

        let sceneChange = String(try section(
            in: view,
            from: ".onChange(of: scenePhase)",
            to: ".onChange(of: sdkAccount.loggedIn)"
        ))
        let reopen = try requiredOffset(containing: "if newPhase == .active", in: sceneChange)
        let reverify = try requiredOffset(containing: "test.verifySDKMembership()", in: sceneChange)
        let failClosed = try requiredOffset(containing: "test.appDidLoseForeground()", in: sceneChange)
        #expect(reopen < reverify)
        #expect(reverify < failClosed)
    }

    @Test("foreground loss closes fresh membership admission before revoking issued grants")
    func foregroundLossClosesMembershipAdmissionFirst() throws {
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

        let closeAdmission = try requiredOffset(containing: "acceptsViewScopedMembershipRequests = false", in: cleanup)
        let membershipRevoke = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)
        let officialRevoke = try requiredOffset(containing: "officialConnectionRequestID = UUID()", in: cleanup)
        let correlationCheck = try requiredOffset(
            containing: "if processCorrelationLease != nil || correlationSession != nil",
            in: cleanup
        )
        #expect(closeAdmission < membershipRevoke)
        #expect(membershipRevoke < officialRevoke)
        #expect(officialRevoke < correlationCheck)
        #expect(cleanup.contains("sdkDeviceMembershipVerified = false"))
        #expect(cleanup.contains("membershipAccountUID = nil"))
        #expect(cleanup.contains("membershipDeviceID = nil"))
        #expect(cleanup.contains("watchdog?.cancel()"))
    }

    @Test("foreground loss uses truth-specific terminals and never claims disconnect")
    func foregroundLossUsesContinuityVsLifecycleTerminals() throws {
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

        #expect(cleanup.contains("abandonPackageCorrelation()"))
        #expect(cleanup.contains("foreground_integrity_lost_during_target_correlation"))
        #expect(cleanup.contains("let wasObserving = phase == .observing"))
        #expect(cleanup.contains("invalidateObservationContinuity("))
        #expect(cleanup.contains("invalidateInternalLifecycle("))
        #expect(cleanup.contains("foreground_integrity_lost_during_observation"))
        #expect(cleanup.contains("foreground_integrity_lost_before_observation"))
        #expect(!cleanup.contains("releasePackageCorrelationLease()"))
        #expect(!cleanup.contains("recordObservedTransportLoss"))
        #expect(!cleanup.contains("endConnection"))
        #expect(!cleanup.contains("disconnectBLE"))
    }

    @Test("initial task cannot bootstrap membership while the scene is already inactive")
    func initialTaskChecksCurrentSceneBeforeBootstrap() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let view = String(try section(
            in: source,
            from: "private struct SecureLinkView: View",
            to: "private var hero: some View"
        ))
        let task = String(try section(in: view, from: ".task {", to: ".onDisappear {"))
        let activate = try requiredOffset(containing: "test.activateMembershipRequestsForView()", in: task)
        let activeCheck = try requiredOffset(containing: "if scenePhase == .active", in: task)
        let bootstrap = try requiredOffset(containing: "sdkAccount.bootstrap()", in: task)
        let inactiveCleanup = try requiredOffset(containing: "test.appDidLoseForeground()", in: task)
        #expect(activate < activeCheck)
        #expect(activeCheck < bootstrap)
        #expect(bootstrap < inactiveCleanup)
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