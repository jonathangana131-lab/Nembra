from pathlib import Path

SOURCE_PATH = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST_PATH = Path(
    "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/"
    "TuyaCaptureApplicationEventCustodySourceTests.swift"
)

source = SOURCE_PATH.read_text(encoding="utf-8")


def require_once(haystack: str, needle: str, label: str) -> None:
    count = haystack.count(needle)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")


def replace_once(haystack: str, old: str, new: str, label: str) -> str:
    require_once(haystack, old, label)
    return haystack.replace(old, new, 1)


# 1. Bind accepted application-event custody to the already-earned account UID lease.
receiver_anchor = "    private func receivedApplicationUpdate(\n"
require_once(source, receiver_anchor, "application receiver anchor")

uid_helper = '''    private func redactVerifiedAccountUID(
        from update: [String: String],
        verifiedAccountUID: String
    ) -> [String: String] {
        let marker = "<redacted-account-uid>"
        var sanitized: [String: String] = [:]

        // Deterministic ordering makes key-collision handling stable without retaining the UID.
        for (key, value) in update.sorted(by: { $0.key < $1.key }) {
            let redactedKey = key.replacingOccurrences(
                of: verifiedAccountUID,
                with: marker,
                options: [.caseInsensitive, .literal]
            )
            let redactedValue = value.replacingOccurrences(
                of: verifiedAccountUID,
                with: marker,
                options: [.caseInsensitive, .literal]
            )

            var admittedKey = redactedKey
            var collisionOrdinal = 2
            while sanitized[admittedKey] != nil {
                admittedKey = "\\(redactedKey)#\\(collisionOrdinal)"
                collisionOrdinal += 1
            }
            sanitized[admittedKey] = redactedValue
        }
        return sanitized
    }

'''
if "private func redactVerifiedAccountUID(" in source:
    raise SystemExit("account UID redactor unexpectedly already exists")
source = source.replace(receiver_anchor, uid_helper + receiver_anchor, 1)

receiver_start = source.index(receiver_anchor)
receiver_end = source.index("    private func startWatchdog", receiver_start)
receiver = source[receiver_start:receiver_end]

source_authority_guard = '''        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let driver else {
            await invalidateSourceAuthority(
                token: token,
                message: "SDK account/device source authority changed before application evidence arrived.",
                kind: "sdk_source_authority_changed_during_observation"
            )
            return
        }
        guard driver.isLocallyConnected(uuid: tuyaUUID) else {'''

source_authority_guard_repaired = '''        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let driver else {
            await invalidateSourceAuthority(
                token: token,
                message: "SDK account/device source authority changed before application evidence arrived.",
                kind: "sdk_source_authority_changed_during_observation"
            )
            return
        }
        guard let verifiedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !verifiedAccountUID.isEmpty else {
            await invalidateSourceAuthority(
                token: token,
                message: "Verified Tuya account identity was unavailable before application evidence custody.",
                kind: "sdk_account_uid_authority_missing_during_observation"
            )
            return
        }
        let accountUIDRedactedUpdate = redactVerifiedAccountUID(
            from: update,
            verifiedAccountUID: verifiedAccountUID
        )
        guard driver.isLocallyConnected(uuid: tuyaUUID) else {'''
receiver = replace_once(
    receiver,
    source_authority_guard,
    source_authority_guard_repaired,
    "pre-await source/account authority guard",
)

old_custody = '''            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)
            await refreshLedgerSnapshot()
            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })'''

new_custody = '''            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)
            await refreshLedgerSnapshot()

            // Actor hops above may allow account/session authority to change. Never let a callback
            // admitted under an old lease enter immutable event custody after that lease is gone.
            guard currentConnectionToken == token,
                  phase == .observing,
                  sdkAccountLoggedIn,
                  sdkDeviceMembershipVerified,
                  accountIdentityLeaseIsAuthorized,
                  membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines) == verifiedAccountUID else {
                if currentConnectionToken == token {
                    await invalidateSourceAuthority(
                        token: token,
                        message: "SDK account/device authority changed before application evidence could enter event custody.",
                        kind: "sdk_source_authority_changed_before_application_event_custody"
                    )
                }
                return
            }

            log("tuya_application_update", accountUIDRedactedUpdate.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { _, trusted in trusted })'''
receiver = replace_once(receiver, old_custody, new_custody, "trusted application event custody")
source = source[:receiver_start] + receiver + source[receiver_end:]

# 2. Remove the merge-created duplicate classifier entry while preserving every promised class.
duplicate_sequence = '''        "accesstoken",
        "refreshtoken",
        "sessionkey",
        "authkey",'''
replacement_sequence = '''        "accesstoken",
        "refreshtoken",
        "authkey",'''
source = replace_once(
    source,
    duplicate_sequence,
    replacement_sequence,
    "duplicate sessionkey classifier entry",
)

SOURCE_PATH.write_text(source, encoding="utf-8")

# 3. Add one coherent current-product source contract covering all converged invariants.
if TEST_PATH.exists():
    raise SystemExit(f"unexpected existing test path: {TEST_PATH}")
TEST_PATH.write_text(
    r'''import Foundation
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
''',
    encoding="utf-8",
)

# Materializer self-checks before its workflow commits anything.
materialized = SOURCE_PATH.read_text(encoding="utf-8")
assert materialized.count("private func redactVerifiedAccountUID(") == 1
assert "<redacted-account-uid>" in materialized
assert "accountUIDRedactedUpdate.merging([" in materialized
assert "]) { _, trusted in trusted })" in materialized
assert "sdk_source_authority_changed_before_application_event_custody" in materialized
assert "log(\"tuya_application_update\", update.merging([" not in materialized

classifier_start = materialized.index("    private static let secretKeyFragments = [")
classifier_end = materialized.index("    private static func redactApplicationSecrets", classifier_start)
classifier = materialized[classifier_start:classifier_end]
for fragment in [
    "localkey", "sessionkey", "appkey", "appsecret", "password",
    "accounttoken", "accesstoken", "refreshtoken", "authkey", "seckey",
]:
    count = classifier.count(f'"{fragment}"')
    if count != 1:
        raise SystemExit(f"{fragment} classifier count {count}, expected 1")

print("capture event custody materialization: PASS")
