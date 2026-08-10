import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture current event custody source contract")
struct TuyaCaptureCurrentEventCustodySourceTests {
    @Test("view exit revokes operator membership copy with proof")
    func viewExitRevokesMembershipCopy() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let cleanup = String(try section(
            in: source,
            from: "func abandonCorrelationForViewExit()",
            to: "func appDidLoseForeground()"
        ))

        let proof = try requiredOffset(containing: "sdkDeviceMembershipVerified = false", in: cleanup)
        let status = try requiredOffset(containing: "membershipStatus = \"Exact scooter membership must be verified again for this Secure Link session.\"", in: cleanup)
        let request = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)
        #expect(proof < status)
        #expect(status < request)
        #expect(!cleanup.contains("membershipStatus = \"Exact scooter membership verified and leased to this current SDK account.\""))
    }

    @Test("foreground loss revokes operator membership copy before async authority")
    func foregroundLossRevokesMembershipCopy() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let cleanup = String(try section(
            in: source,
            from: "func appDidLoseForeground()",
            to: "var privateConfig: Bool"
        ))

        let proof = try requiredOffset(containing: "sdkDeviceMembershipVerified = false", in: cleanup)
        let status = try requiredOffset(containing: "membershipStatus = \"Exact scooter membership must be verified again for this Secure Link session.\"", in: cleanup)
        let request = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)
        #expect(proof < status)
        #expect(status < request)
    }

    @Test("accepted application events pass through package custody before logging")
    func applicationEventsUseTrustedCustody() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        #expect(receiver.contains("TuyaAuthenticatedApplicationEventCustody.eventDetails("))
        #expect(receiver.contains("applicationUpdate: update"))
        #expect(receiver.contains("trustedGeneration: String(token.diagnosticGeneration)"))
        #expect(receiver.contains("accountUID: membershipAccountUID"))
        #expect(receiver.contains("log(\"tuya_application_update\", eventDetails)"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update"))
    }

    @Test("driver secret key classifier remains narrow and deduplicated")
    func driverClassifierDoesNotBlanketRedactUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "private final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))
        let classifier = String(try section(
            in: driver,
            from: "private static let secretKeyFragments = [",
            to: "]\n\n    private static func redactApplicationSecrets"
        ))

        #expect(!classifier.contains("\"uid\""))
        #expect(classifier.components(separatedBy: "\"sessionkey\"").count - 1 == 1)
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
