import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture navigation BLE lease retirement source contract")
struct TuyaNavigationBLELeaseRetirementSourceTests {
    @Test("leaving Secure Link revokes pending membership callbacks before any early return")
    func secureLinkNavigationExitRevokesPendingStartsAndRetiresCorrelationLease() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let cleanup = String(try section(
            in: controller,
            from: "func abandonCorrelationForViewExit()",
            to: "var privateConfig: Bool"
        ))
        let view = String(try section(
            in: source,
            from: "private struct SecureLinkView: View",
            to: "private extension SecureLinkView"
        ))

        let revokeRequest = try requiredLine(containing: "membershipRequestID = UUID()", in: cleanup)
        let clearBusy = try requiredLine(containing: "membershipBusy = false", in: cleanup)
        let retireProbe = try requiredLine(containing: "membershipProbe = nil", in: cleanup)
        let earlyReturn = try requiredLine(
            containing: "guard processCorrelationLease != nil || correlationSession != nil else { return }",
            in: cleanup
        )
        let abandon = try requiredLine(containing: "abandonPackageCorrelation()", in: cleanup)
        let failedState = try requiredLine(containing: "phase = .failed", in: cleanup)

        #expect(revokeRequest < earlyReturn)
        #expect(clearBusy < earlyReturn)
        #expect(retireProbe < earlyReturn)
        #expect(earlyReturn < abandon)
        #expect(abandon < failedState)
        #expect(cleanup.contains("target_correlation_abandoned_on_view_exit"))
        #expect(!cleanup.contains("releasePackageCorrelationLease()"))
        #expect(view.contains(".onDisappear"))
        #expect(view.contains("test.abandonCorrelationForViewExit()"))
    }

    @Test("membership request generation fences both OFF1 and final Tuya connection starts")
    func oneGenerationFenceCoversBothMembershipCompletionStarts() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let membership = String(try section(
            in: controller,
            from: "func verifySDKMembership(completion:",
            to: "func retry()"
        ))
        let authenticate = String(try section(
            in: controller,
            from: "func authenticate()",
            to: "private func beginOfficialConnection"
        ))
        let baseline = String(try section(
            in: controller,
            from: "func startBaseline()",
            to: "private func beginCorrelationSeries()"
        ))

        #expect(membership.contains("let requestID = UUID()"))
        #expect(membership.contains("membershipRequestID = requestID"))
        #expect(membership.contains("guard let self, self.membershipRequestID == requestID else { return }"))
        #expect(baseline.contains("verifySDKMembership"))
        #expect(baseline.contains("beginCorrelationSeries()"))
        #expect(authenticate.contains("verifySDKMembership"))
        #expect(authenticate.contains("self.beginOfficialConnection(candidate: candidate)"))
    }

    @Test("cleanup reuses transport-first package abandonment path")
    func packageTransportRetirementPrecedesLeaseRelease() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let abandon = String(try section(
            in: source,
            from: "private func abandonPackageCorrelation()",
            to: "private func releasePackageCorrelationLease()"
        ))
        let abandonLine = try requiredLine(containing: "correlationSession?.abandonCurrentWindow()", in: abandon)
        let releaseLine = try requiredLine(containing: "releasePackageCorrelationLease()", in: abandon)
        #expect(abandonLine < releaseLine)
    }

    private func requiredLine(containing token: String, in source: String) throws -> Int {
        guard let index = source.components(separatedBy: "\n").firstIndex(where: { $0.contains(token) }) else {
            Issue.record("Expected source token missing: \(token)")
            throw SourceContractError.sectionMissing
        }
        return index
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
