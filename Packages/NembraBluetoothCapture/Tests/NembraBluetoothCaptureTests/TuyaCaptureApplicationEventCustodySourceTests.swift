import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture authenticated application-event custody")
struct TuyaCaptureApplicationEventCustodySourceTests {
    @Test("verified account UID is scrubbed before application event custody without blanket uid-key deletion")
    func accountUIDCannotEnterAcceptedApplicationEvents() throws {
        let source = try entrypointSource()
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))

        #expect(source.contains("private func redactVerifiedAccountUID("))
        #expect(source.contains("<redacted-account-uid>"))
        #expect(receiver.contains("let verifiedAccountUID = membershipAccountUID?.trimmingCharacters"))
        #expect(receiver.contains("accountUIDRedactedUpdate = redactVerifiedAccountUID("))
        #expect(receiver.contains("sdk_account_uid_authority_missing_during_observation"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update.merging(["))
        #expect(!driver.contains("\"uid\","))
        #expect(!driver.contains("\"uid\"\n"))
    }

    @Test("Nembra generation provenance wins application-key collisions")
    func applicationPayloadCannotForgeGeneration() throws {
        let source = try entrypointSource()
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        #expect(receiver.contains("\"generation\": String(token.diagnosticGeneration)"))
        #expect(receiver.contains(") { _, trusted in trusted })"))
        #expect(!receiver.contains(") { current, _ in current })"))
    }

    @Test("application event custody revalidates exact token and account lease after actor hops")
    func authorityIsRecheckedAfterLedgerAwait() throws {
        let source = try entrypointSource()
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))
        let refresh = try requiredOffset("await refreshLedgerSnapshot()", in: receiver)
        let postAwaitToken = try requiredOffset("guard currentConnectionToken == token,", in: receiver, after: refresh)
        let custody = try requiredOffset("log(\"tuya_application_update\"", in: receiver, after: postAwaitToken)

        #expect(refresh < postAwaitToken)
        #expect(postAwaitToken < custody)
        #expect(receiver.contains("membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines) == verifiedAccountUID"))
        #expect(receiver.contains("sdk_source_authority_changed_before_application_event_custody"))
    }

    @Test("export-promised application secret classifier contains each class exactly once")
    func secretClassifierHasNoMergeDuplicates() throws {
        let source = try entrypointSource()
        let classifier = String(try section(
            in: source,
            from: "private static let secretKeyFragments = [",
            to: "private static func redactApplicationSecrets"
        ))
        let expected = [
            "localkey", "sessionkey", "appkey", "appsecret", "password",
            "accounttoken", "accesstoken", "refreshtoken", "authkey", "seckey"
        ]
        for fragment in expected {
            #expect(
                classifier.components(separatedBy: "\"\(fragment)\"").count == 2,
                "credential classifier fragment must appear exactly once: \(fragment)"
            )
        }
    }

    private func entrypointSource() throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(
            contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw ContractError.missing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func requiredOffset(
        _ token: String,
        in source: String,
        after lowerBound: String.Index? = nil
    ) throws -> String.Index {
        let searchRange = (lowerBound ?? source.startIndex)..<source.endIndex
        guard let range = source.range(of: token, range: searchRange) else {
            Issue.record("Expected source token missing: \(token)")
            throw ContractError.missing
        }
        return range.lowerBound
    }

    private enum ContractError: Error { case missing }
}
