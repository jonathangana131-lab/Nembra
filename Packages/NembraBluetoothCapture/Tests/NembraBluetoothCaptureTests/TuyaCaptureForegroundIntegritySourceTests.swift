import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture foreground integrity source contract")
struct TuyaCaptureForegroundIntegritySourceTests {
    @Test("Secure Link observes scene activity and fails closed when the app leaves foreground")
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

        #expect(view.contains("@Environment(\\.scenePhase) private var scenePhase"))
        #expect(view.contains(".onChange(of: scenePhase)"))
        #expect(view.contains("if newPhase != .active"))
        #expect(view.contains("test.appDidLoseForeground()"))

        // Close the screen-lifetime admission boundary before rotating any already-issued grant.
        let admissionClose = try requiredOffset(containing: "acceptsViewScopedMembershipRequests = false", in: cleanup)
        let membershipRevoke = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)
        let officialRevoke = try requiredOffset(containing: "officialConnectionRequestID = UUID()", in: cleanup)
        let correlationCheck = try requiredOffset(
            containing: "if processCorrelationLease != nil || correlationSession != nil",
            in: cleanup
        )
        #expect(admissionClose < membershipRevoke)
        #expect(membershipRevoke < correlationCheck)
        #expect(officialRevoke < correlationCheck)
        #expect(cleanup.contains("membershipBusy = false"))
        #expect(cleanup.contains("membershipProbe = nil"))
        #expect(cleanup.contains("watchdog?.cancel()"))

        // Package-owned target correlation is interrupted through the existing scanner-first,
        // owner-token path; foreground loss never directly releases the process lease.
        #expect(cleanup.contains("abandonPackageCorrelation()"))
        #expect(cleanup.contains("foreground_integrity_lost_during_target_correlation"))
        #expect(!cleanup.contains("releasePackageCorrelationLease()"))

        // A bounded terminal task must keep the controller alive until exact-generation retirement
        // completes, matching the view-exit lifetime invariant already accepted by the product.
        #expect(cleanup.contains("Task { @MainActor [self] in"))
        #expect(!cleanup.contains("Task { @MainActor [weak self]"))

        // An authenticated observing generation loses continuity authority; an auth-acquisition
        // generation is retired as an internal lifecycle failure. Neither path invents transport loss.
        #expect(cleanup.contains("invalidateObservationContinuity("))
        #expect(cleanup.contains("foreground_integrity_lost_during_observation"))
        #expect(cleanup.contains("invalidateInternalLifecycle("))
        #expect(cleanup.contains("foreground_integrity_lost_before_observation"))
        #expect(!cleanup.contains("recordObservedTransportLoss"))
        #expect(!cleanup.contains("endConnection("))
        #expect(!cleanup.contains("disconnectBLE("))

        // After official driver handoff, failure recovery requires a relaunch rather than implying
        // the package correlation path can simply restart in the same process.
        #expect(cleanup.contains("Relaunch Capture before another authenticated attempt"))
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
