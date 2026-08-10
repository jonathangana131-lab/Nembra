import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted event snapshots verified account identity before any suspension")
    func acceptedEventSnapshotsIdentityBeforeAwait() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        let snapshot = try #require(receiver.range(
            of: "let verifiedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines)"
        ))
        let custody = try #require(receiver.range(
            of: "guard let eventDetails = TuyaApplicationEventCustody.admittedDetails("
        ))
        let inFlight = try #require(receiver.range(of: "applicationUpdateAdmissionsInFlight += 1"))
        let firstAwait = try #require(receiver.range(of: "try await sessionLedger.recordApplicationUpdate"))

        #expect(snapshot.lowerBound < custody.lowerBound)
        #expect(custody.lowerBound < inFlight.lowerBound)
        #expect(inFlight.lowerBound < firstAwait.lowerBound)
        #expect(receiver.contains("verifiedAccountUID: verifiedAccountUID"))
        #expect(receiver.contains("application_event_custody_authority_unavailable"))
        #expect(!receiver.contains("redactedApplicationEventDetails"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update"))
    }

    @Test("package custody removes exact account identity without blanket generic uid classification")
    func packageCustodyPreservesGenericUIDEvidence() throws {
        let custody = try readRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaApplicationEventCustody.swift"
        )

        #expect(custody.contains("redactedAccountUIDMarker = \"<redacted-account-uid>\""))
        #expect(custody.contains("redactExactAccountUID(in: key, accountUID: accountUID)"))
        #expect(custody.contains("redactExactAccountUID(in: value, accountUID: accountUID)"))
        #expect(custody.contains("options: [.literal]"))
        #expect(!custody.contains("secretKeyFragments"))
        #expect(!custody.contains("\"uid\","))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
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
