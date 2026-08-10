import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted event scrubs the exact admitted account UID from untrusted keys and values")
    func acceptedEventScrubsExactAdmittedAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func redactedApplicationEventDetails"
        ))
        let scrubber = String(try section(
            in: source,
            from: "private func redactedApplicationEventDetails",
            to: "private func startWatchdog"
        ))

        let leaseCapture = try requiredOffset(containing: "let verifiedAccountUID = membershipAccountUID", in: receiver)
        let firstAwait = try requiredOffset(containing: "try await sessionLedger.recordApplicationUpdate", in: receiver)
        let scrubCall = try requiredOffset(containing: "verifiedAccountUID: verifiedAccountUID", in: receiver)

        #expect(leaseCapture < firstAwait)
        #expect(firstAwait < scrubCall)
        #expect(receiver.contains("!verifiedAccountUID.isEmpty"))
        #expect(receiver.contains("eventDetails[\"generation\"] = String(token.diagnosticGeneration)"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update"))

        #expect(scrubber.contains("verifiedAccountUID: String"))
        #expect(!scrubber.contains("membershipAccountUID"))
        #expect(scrubber.contains("key.replacingOccurrences("))
        #expect(scrubber.contains("value.replacingOccurrences("))
        #expect(scrubber.contains("<redacted-account-uid>"))
        #expect(scrubber.contains("options: [.caseInsensitive, .literal]"))
    }

    @Test("redacted event custody preserves colliding keys deterministically")
    func redactedEventCustodyPreservesCollisionEvidenceDeterministically() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let scrubber = String(try section(
            in: source,
            from: "private func redactedApplicationEventDetails",
            to: "private func startWatchdog"
        ))

        #expect(scrubber.contains("update.sorted(by: { $0.key < $1.key })"))
        #expect(scrubber.contains("if redacted[redactedKey] != nil"))
        #expect(scrubber.contains("var suffix = 2"))
        #expect(scrubber.contains("redactedKey = \"\\(redactedKey)#\\(suffix)\""))
        #expect(!scrubber.contains("return update"))
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw Error.sectionMissing
        }
        return range.lowerBound
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw Error.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private enum Error: Swift.Error { case sectionMissing }
}
