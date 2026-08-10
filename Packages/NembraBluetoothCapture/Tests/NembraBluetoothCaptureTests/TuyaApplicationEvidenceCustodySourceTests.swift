import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application evidence custody")
struct TuyaApplicationEvidenceCustodySourceTests {
    @Test("accepted application evidence binds UID scrubbing to the verified membership lease")
    func acceptedApplicationEvidenceUsesVerifiedAccountUIDBeforeCustody() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        let leasedUID = try requiredOffset(
            containing: "let verifiedAccountUID = membershipAccountUID?.trimmingCharacters",
            in: receiver
        )
        let redact = try requiredOffset(
            containing: "Self.redactVerifiedAccountUID(",
            in: receiver
        )
        let ledgerAdmission = try requiredOffset(
            containing: "sessionLedger.recordApplicationUpdate",
            in: receiver
        )
        let eventCustody = try requiredOffset(
            containing: "log(\"tuya_application_update\"",
            in: receiver
        )

        #expect(leasedUID < redact)
        #expect(redact < ledgerAdmission)
        #expect(ledgerAdmission < eventCustody)
        #expect(receiver.contains("verifiedAccountUID: verifiedAccountUID"))
        #expect(receiver.contains("acceptedApplicationUpdate.merging(["))
        #expect(receiver.contains(") { _, trusted in trusted })"))
        #expect(!receiver.contains("update.merging(["))
        #expect(!receiver.contains(") { current, _ in current })"))
    }

    @Test("verified account UID is removed from both application keys and values")
    func verifiedAccountUIDCannotEscapeThroughMalformedApplicationContent() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let scrubber = String(try section(
            in: source,
            from: "private static let redactedAccountUIDMarker",
            to: "private func receivedApplicationUpdate("
        ))

        #expect(scrubber.contains("<redacted-account-uid>"))
        #expect(scrubber.contains("<redacted-account-uid-key-collision>"))
        #expect(scrubber.contains("key.replacingOccurrences("))
        #expect(scrubber.contains("value.replacingOccurrences("))
        #expect(scrubber.components(separatedBy: "of: verifiedAccountUID").count - 1 == 2)
        #expect(scrubber.contains("redacted[safeKey] == nil"))
        #expect(scrubber.contains("redactedAccountUIDKeyCollisionMarker"))
    }

    @Test("account identity custody does not become a blanket generic uid-key classifier")
    func accountUIDCustodyPreservesGenericUIDNamedApplicationFields() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))

        #expect(!driver.contains("\"uid\","))
        #expect(!driver.contains("\"uid\"\n"))
        #expect(driver.components(separatedBy: "\"sessionkey\"").count - 1 == 1)
        for required in [
            "\"localkey\"",
            "\"sessionkey\"",
            "\"appkey\"",
            "\"appsecret\"",
            "\"password\"",
            "\"accounttoken\"",
            "\"accesstoken\"",
            "\"refreshtoken\"",
            "\"authkey\"",
            "\"seckey\"",
        ] {
            #expect(driver.contains(required))
        }
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
