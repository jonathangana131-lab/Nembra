\
import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture foreground integrity source contract")
struct TuyaCaptureForegroundIntegritySourceTests {
    @Test("Secure Link closes foreground evidence authority exactly once")
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
        let cleanup = String(try section(
            in: controller,
            from: "func appDidLoseForeground()",
            to: "var privateConfig: Bool"
        ))
        let activation = String(try section(
            in: controller,
            from: "func activateMembershipRequestsForView()",
            to: "func abandonCorrelationForViewExit()"
        ))

        #expect(controller.contains("private var foregroundIntegrityLost = false"))
        #expect(activation.contains("guard !foregroundIntegrityLost else { return }"))
        #expect(view.contains("@Environment(\\.scenePhase) private var scenePhase"))
        #expect(view.contains(".onChange(of: scenePhase)"))
        #expect(view.contains("if newPhase != .active"))
        #expect(view.contains("test.appDidLoseForeground()"))

        let oneShot = try requiredOffset(containing: "guard !foregroundIntegrityLost else { return }", in: cleanup)
        let closeAdmission = try requiredOffset(containing: "acceptsViewScopedMembershipRequests = false", in: cleanup)
        let clearVerified = try requiredOffset(containing: "sdkDeviceMembershipVerified = false", in: cleanup)
        let clearAccountLease = try requiredOffset(containing: "membershipAccountUID = nil", in: cleanup)
        let clearDeviceLease = try requiredOffset(containing: "membershipDeviceID = nil", in: cleanup)
        let statusReset = try requiredOffset(containing: "membershipStatus =", in: cleanup)
        let membershipRevoke = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)
        let officialRevoke = try requiredOffset(containing: "officialConnectionRequestID = UUID()", in: cleanup)
        let correlationCheck = try requiredOffset(
            containing: "if processCorrelationLease != nil || correlationSession != nil",
            in: cleanup
        )
        #expect(oneShot < closeAdmission)
        #expect(closeAdmission < clearVerified)
        #expect(clearVerified < membershipRevoke)
        #expect(clearAccountLease < membershipRevoke)
        #expect(clearDeviceLease < membershipRevoke)
        #expect(statusReset < membershipRevoke)
        #expect(membershipRevoke < officialRevoke)
        #expect(officialRevoke < correlationCheck)
        #expect(cleanup.contains("membershipBusy = false"))
        #expect(cleanup.contains("membershipProbe = nil"))
        #expect(cleanup.contains("watchdog?.cancel()"))

        #expect(cleanup.contains("abandonPackageCorrelation()"))
        #expect(cleanup.contains("foreground_integrity_lost_during_target_correlation"))
        #expect(!cleanup.contains("releasePackageCorrelationLease()"))

        #expect(cleanup.contains("Task { @MainActor [self] in"))
        #expect(!cleanup.contains("Task { @MainActor [weak self]"))
        #expect(cleanup.contains("invalidateObservationContinuity("))
        #expect(cleanup.contains("foreground_integrity_lost_during_observation"))
        #expect(cleanup.contains("invalidateInternalLifecycle("))
        #expect(cleanup.contains("foreground_integrity_lost_before_observation"))
        #expect(!cleanup.contains("recordObservedTransportLoss"))
        #expect(!cleanup.contains("endConnection"))
        #expect(!cleanup.contains(".disconnect("))
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
