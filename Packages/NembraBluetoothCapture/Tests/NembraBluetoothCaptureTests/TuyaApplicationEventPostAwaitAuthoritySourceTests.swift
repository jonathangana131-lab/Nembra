import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application event post-await source authority")
struct TuyaApplicationEventPostAwaitAuthoritySourceTests {
    @Test("application evidence revalidates account and membership authority after recorder suspension")
    func revalidatesAuthorityBeforeImmutableEventCustody() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        let refresh = try requiredOffset(containing: "await refreshLedgerSnapshot()", in: receiver)
        let postAwaitAuthority = try requiredOffset(
            containing: "sdk_source_authority_changed_before_application_event_custody",
            in: receiver
        )
        let eventLog = try requiredOffset(containing: "log(\"tuya_application_update\"", in: receiver)

        #expect(refresh < postAwaitAuthority)
        #expect(postAwaitAuthority < eventLog)
        #expect(receiver.contains("membershipAccountUID"))
        #expect(receiver.contains("accountIdentityLeaseIsAuthorized"))
    }

    @Test("event redaction cannot fall back to raw SDK details when account UID authority disappears")
    func redactionHasNoRawFallback() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = String(try section(
            in: source,
            from: "private func redactedApplicationEventDetails(",
            to: "private func startWatchdog"
        ))

        #expect(helper.contains("verifiedAccountUID"))
        #expect(!helper.contains("return update"))
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
