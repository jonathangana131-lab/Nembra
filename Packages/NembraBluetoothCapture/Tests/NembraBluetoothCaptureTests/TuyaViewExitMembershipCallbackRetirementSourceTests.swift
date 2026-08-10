import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Secure Link exit membership callback retirement")
struct TuyaViewExitMembershipCallbackRetirementSourceTests {
    @Test("view exit revokes pending membership callbacks before any no-scanner early return")
    func viewExitRevokesMembershipGenerationBeforeCorrelationGuard() throws {
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

        let requestRotation = try requiredRange("membershipRequestID = UUID()", in: cleanup)
        let busyClear = try requiredRange("membershipBusy = false", in: cleanup)
        let probeClear = try requiredRange("membershipProbe = nil", in: cleanup)
        let activeCorrelationGuard = try requiredRange(
            "guard processCorrelationLease != nil || correlationSession != nil else { return }",
            in: cleanup
        )
        let abandon = try requiredRange("abandonPackageCorrelation()", in: cleanup)

        #expect(requestRotation.lowerBound < activeCorrelationGuard.lowerBound)
        #expect(busyClear.lowerBound < activeCorrelationGuard.lowerBound)
        #expect(probeClear.lowerBound < activeCorrelationGuard.lowerBound)
        #expect(activeCorrelationGuard.lowerBound < abandon.lowerBound)
        #expect(!cleanup.contains("releasePackageCorrelationLease()"))
    }

    @Test("the same membership generation guards both hidden OFF1 and hidden Tuya connection starts")
    func generationFenceCoversBaselineAndFinalMembershipCallbacks() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let verify = String(try section(
            in: controller,
            from: "func verifySDKMembership(completion:",
            to: "func retry()"
        ))
        let baseline = String(try section(
            in: controller,
            from: "func startBaseline()",
            to: "private func beginCorrelationSeries()"
        ))
        let authenticate = String(try section(
            in: controller,
            from: "func authenticate()",
            to: "private func beginOfficialConnection(candidate:"
        ))

        #expect(verify.contains("self.membershipRequestID == requestID"))
        #expect(baseline.contains("verifySDKMembership"))
        #expect(baseline.contains("self.beginCorrelationSeries()"))
        #expect(authenticate.contains("verifySDKMembership"))
        #expect(authenticate.contains("self.beginOfficialConnection(candidate: candidate)"))
    }

    @Test("view-exit repair remains lifecycle-only")
    func viewExitRepairHasNoScooterTransportMutation() throws {
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
        for forbidden in ["connectBLE", "publishDps", "queryDps", "writeValue", "disconnectBLE"] {
            #expect(!cleanup.contains(forbidden))
        }
        #expect(cleanup.contains("abandonPackageCorrelation()"))
    }

    private func requiredRange(_ needle: String, in source: String) throws -> Range<String.Index> {
        guard let range = source.range(of: needle) else {
            Issue.record("Expected source contract missing: \(needle)")
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

    private enum SourceContractError: Error { case sectionMissing }
}
