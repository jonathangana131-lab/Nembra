import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture current-head foreground integrity source contract")
struct TuyaCaptureForegroundIntegrityCurrentHeadSourceTests {
    @Test("Secure Link fails closed when app activity leaves foreground")
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

        let closeAdmission = try requiredOffset(containing: "acceptsViewScopedMembershipRequests = false", in: cleanup)
        let membershipRevoke = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)
        let officialRevoke = try requiredOffset(containing: "officialConnectionRequestID = UUID()", in: cleanup)
        let correlationCheck = try requiredOffset(
            containing: "if processCorrelationLease != nil || correlationSession != nil",
            in: cleanup
        )
        #expect(closeAdmission < membershipRevoke)
        #expect(membershipRevoke < correlationCheck)
        #expect(officialRevoke < correlationCheck)
        #expect(cleanup.contains("membershipBusy = false"))
        #expect(cleanup.contains("membershipProbe = nil"))
        #expect(cleanup.contains("watchdog?.cancel()"))

        #expect(cleanup.contains("abandonPackageCorrelation()"))
        #expect(cleanup.contains("foreground_integrity_lost_during_target_correlation"))
        #expect(!cleanup.contains("releasePackageCorrelationLease()"))

        #expect(cleanup.contains("invalidateObservationContinuity("))
        #expect(cleanup.contains("foreground_integrity_lost_during_observation"))
        #expect(cleanup.contains("invalidateInternalLifecycle("))
        #expect(cleanup.contains("foreground_integrity_lost_before_observation"))
        #expect(!cleanup.contains("recordObservedTransportLoss"))
        #expect(!cleanup.contains("endConnection"))
        #expect(!cleanup.contains("disconnectBLE"))
        #expect(!cleanup.contains("publishDps"))
        #expect(!cleanup.contains("queryDps"))
        #expect(!cleanup.contains("writeValue"))
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
