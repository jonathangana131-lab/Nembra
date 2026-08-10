import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture navigation BLE lease retirement source contract")
struct TuyaNavigationBLELeaseRetirementSourceTests {
    @Test("leaving Secure Link revokes pending membership callbacks before any scanner early return")
    func secureLinkNavigationExitRetiresCorrelationLease() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let view = String(try section(
            in: source,
            from: "private struct SecureLinkView: View",
            to: "private extension SecureLinkView"
        ))
        let cleanup = String(try section(
            in: controller,
            from: "func abandonCorrelationForViewExit()",
            to: "var privateConfig: Bool"
        ))

        let revoke = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)
        let busyClear = try requiredOffset(containing: "membershipBusy = false", in: cleanup)
        let probeClear = try requiredOffset(containing: "membershipProbe = nil", in: cleanup)
        let noActiveCorrelationReturn = try requiredOffset(
            containing: "guard processCorrelationLease != nil || correlationSession != nil else { return }",
            in: cleanup
        )
        let abandon = try requiredOffset(containing: "abandonPackageCorrelation()", in: cleanup)

        // Leaving Secure Link must revoke an in-flight account-membership result even when OFF1
        // has not acquired a scanner/lease yet. Only after that revocation may cleanup discover
        // there is no active package transport to retire.
        #expect(revoke < noActiveCorrelationReturn)
        #expect(busyClear < noActiveCorrelationReturn)
        #expect(probeClear < noActiveCorrelationReturn)
        #expect(noActiveCorrelationReturn < abandon)
        #expect(!cleanup.contains("releasePackageCorrelationLease()"))
        #expect(cleanup.contains("target_correlation_abandoned_on_view_exit"))
        #expect(view.contains(".onDisappear"))
        #expect(view.contains("test.abandonCorrelationForViewExit()"))
    }

    @Test("one request generation gates both pre OFF1 and pre authentication membership completions")
    func membershipGenerationGatesBothHiddenStartPaths() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let verification = String(try section(
            in: controller,
            from: "func verifySDKMembership(completion:",
            to: "func retry()"
        ))
        let startBaseline = String(try section(
            in: controller,
            from: "func startBaseline()",
            to: "private func beginCorrelationSeries()"
        ))
        let authenticate = String(try section(
            in: controller,
            from: "func authenticate()",
            to: "private func beginOfficialConnection(candidate: Candidate)"
        ))

        #expect(verification.contains("let requestID = UUID()"))
        #expect(verification.contains("membershipRequestID = requestID"))
        #expect(verification.contains("guard let self, self.membershipRequestID == requestID else { return }"))

        // The pre-OFF1 membership completion is allowed to create package-owned scanning only
        // while this exact request generation remains current.
        #expect(startBaseline.contains("verifySDKMembership"))
        #expect(startBaseline.contains("self.beginCorrelationSeries()"))

        // The final selected-target membership recheck uses the same generation fence before it
        // may transfer ownership to the official Tuya driver. View-exit revocation therefore closes
        // both hidden-radio-start paths, not only OFF1.
        #expect(authenticate.contains("verifySDKMembership"))
        #expect(authenticate.contains("self.phase == .selected"))
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
        let transportRetirement = try requiredOffset(
            containing: "correlationSession?.abandonCurrentWindow()",
            in: abandon
        )
        let leaseRelease = try requiredOffset(containing: "releasePackageCorrelationLease()", in: abandon)
        #expect(transportRetirement < leaseRelease)
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
