from pathlib import Path
import sys

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
UID_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationAccountUIDAdmissionSnapshotSourceTests.swift")
LEASE_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAccountIdentityLeaseAppSourceIntegrationTests.swift")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def apply() -> None:
    source = APP.read_text(encoding="utf-8")
    source = replace_once(
        source,
        "            sdkIsLoggedIn: sdkAccountLoggedIn,",
        "            isLoggedIn: sdkAccountLoggedIn,",
        "identity lease initializer label",
    )

    old_receiver = '''        applicationUpdateAdmissionsInFlight += 1
        defer { applicationUpdateAdmissionsInFlight -= 1 }

        do {
            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)
            await refreshLedgerSnapshot()
            var eventDetails = redactedApplicationEventDetails(update)
            eventDetails["generation"] = String(token.diagnosticGeneration)
            log("tuya_application_update", eventDetails)
'''
    new_receiver = '''        guard let admittedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !admittedAccountUID.isEmpty else {
            await invalidateSourceAuthority(
                token: token,
                message: "The account-bound membership identity disappeared before application evidence could enter event custody.",
                kind: "sdk_membership_uid_unavailable_before_application_custody"
            )
            return
        }
        var eventDetails = redactedApplicationEventDetails(update, accountUID: admittedAccountUID)
        eventDetails["generation"] = String(token.diagnosticGeneration)

        applicationUpdateAdmissionsInFlight += 1
        defer { applicationUpdateAdmissionsInFlight -= 1 }

        do {
            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)
            await refreshLedgerSnapshot()
            log("tuya_application_update", eventDetails)
'''
    source = replace_once(source, old_receiver, new_receiver, "pre-suspension event custody")

    old_helper = '''    private func redactedApplicationEventDetails(_ update: [String: String]) -> [String: String] {
        guard let accountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accountUID.isEmpty else {
            return update
        }

        var redacted: [String: String] = [:]
        redacted.reserveCapacity(update.count)
        for (key, value) in update {
            let redactedKey = key.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
            redacted[redactedKey] = value.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
        }
        return redacted
    }
'''
    new_helper = '''    private func redactedApplicationEventDetails(
        _ update: [String: String],
        accountUID rawAccountUID: String
    ) -> [String: String] {
        let accountUID = rawAccountUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountUID.isEmpty else { return [:] }

        var redacted: [String: String] = [:]
        redacted.reserveCapacity(update.count)
        for (key, value) in update {
            var redactedKey = key.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
            let redactedValue = value.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
            if redacted[redactedKey] != nil {
                var suffix = 2
                while redacted["\\(redactedKey)#\\(suffix)"] != nil {
                    suffix += 1
                }
                redactedKey = "\\(redactedKey)#\\(suffix)"
            }
            redacted[redactedKey] = redactedValue
        }
        return redacted
    }
'''
    source = replace_once(source, old_helper, new_helper, "explicit admitted UID redactor")
    APP.write_text(source, encoding="utf-8")

    UID_TEST.write_text('''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account-UID admission snapshot")
struct TuyaApplicationAccountUIDAdmissionSnapshotSourceTests {
    @Test("leased account UID and export-safe details are frozen before actor suspension")
    func accountUIDCustodyPrecedesLedgerAwait() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        let snapshot = try requiredOffset(containing: "let admittedAccountUID = membershipAccountUID?", in: receiver)
        let custody = try requiredOffset(containing: "redactedApplicationEventDetails(update, accountUID: admittedAccountUID)", in: receiver)
        let generation = try requiredOffset(containing: "eventDetails[\\"generation\\"] = String(token.diagnosticGeneration)", in: receiver)
        let firstAwait = try requiredOffset(containing: "try await sessionLedger.recordApplicationUpdate", in: receiver)
        let log = try requiredOffset(containing: "log(\\"tuya_application_update\\", eventDetails)", in: receiver)
        #expect(snapshot < custody)
        #expect(custody < generation)
        #expect(generation < firstAwait)
        #expect(firstAwait < log)
        let tail = receiver[firstAwait...]
        #expect(!tail.contains("membershipAccountUID"))
        #expect(!tail.contains("redactedApplicationEventDetails(update"))
    }

    @Test("redactor consumes explicit admitted UID and fails closed for an empty identity")
    func redactorDoesNotReachBackIntoMembershipState() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = String(try section(in: source, from: "private func redactedApplicationEventDetails(", to: "private func startWatchdog"))
        #expect(helper.contains("accountUID rawAccountUID: String"))
        #expect(!helper.contains("membershipAccountUID"))
        #expect(helper.contains("guard !accountUID.isEmpty else { return [:] }"))
        #expect(helper.contains("while redacted[\\"\\\\(redactedKey)#\\\\(suffix)\\"] != nil"))
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else { throw SourceContractError.sectionMissing }
        return range.lowerBound
    }
    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { throw SourceContractError.sectionMissing }
        return source[a.lowerBound..<b.lowerBound]
    }
    private func readRepositoryFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
    private enum SourceContractError: Error { case sectionMissing }
}
''', encoding="utf-8")

    LEASE_TEST.write_text('''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya account identity lease app-source integration")
struct TuyaAccountIdentityLeaseAppSourceIntegrationTests {
    @Test("Secure Link uses the package identity-lease public initializer label")
    func appCallSiteMatchesPackageInitializer() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let gate = try readRepositoryFile("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaSDKAccountIdentityLeaseGate.swift")
        #expect(gate.contains("public init(\\n            isLoggedIn: Bool,"))
        #expect(app.contains("isLoggedIn: sdkAccountLoggedIn"))
        #expect(!app.contains("sdkIsLoggedIn: sdkAccountLoggedIn"))
    }
    private func readRepositoryFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
''', encoding="utf-8")


def verify() -> None:
    source = APP.read_text(encoding="utf-8")
    if "sdkIsLoggedIn: sdkAccountLoggedIn" in source:
        raise SystemExit("stale identity-lease label remains")
    if source.count("isLoggedIn: sdkAccountLoggedIn") != 1:
        raise SystemExit("expected exactly one corrected identity-lease label")
    a = source.index("private func receivedApplicationUpdate(")
    b = source.index("private func startWatchdog", a)
    receiver = source[a:b]
    await_pos = receiver.index("try await sessionLedger.recordApplicationUpdate")
    for token in (
        "let admittedAccountUID = membershipAccountUID?",
        "redactedApplicationEventDetails(update, accountUID: admittedAccountUID)",
        'eventDetails["generation"] = String(token.diagnosticGeneration)',
    ):
        if receiver.index(token) >= await_pos:
            raise SystemExit(f"event custody token occurs after suspension: {token}")
    tail = receiver[await_pos:]
    if "membershipAccountUID" in tail or "redactedApplicationEventDetails(update" in tail:
        raise SystemExit("post-suspension event custody still depends on mutable membership state")
    helper = source[source.index("private func redactedApplicationEventDetails(", a):b]
    if "accountUID rawAccountUID: String" not in helper or "membershipAccountUID" in helper:
        raise SystemExit("event redactor is not explicitly bound to admitted account UID")
    if "guard !accountUID.isEmpty else { return [:] }" not in helper:
        raise SystemExit("empty admitted identity does not fail closed")
    if not UID_TEST.exists() or not LEASE_TEST.exists():
        raise SystemExit("required regressions were not materialized")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "verify"
    if mode == "apply":
        apply()
    elif mode == "verify":
        verify()
    else:
        raise SystemExit(f"unknown mode: {mode}")
