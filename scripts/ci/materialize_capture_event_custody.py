from pathlib import Path

BASE = "8069c0ffec496cacbe263016d8a7f4ca15ddc64e"
source_path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = source_path.read_text(encoding="utf-8")

old_guard = """        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let driver else {"""
new_guard = """        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let acceptedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !acceptedAccountUID.isEmpty,
              let driver else {"""
if source.count(old_guard) != 1:
    raise SystemExit(f"expected one current source-authority guard, found {source.count(old_guard)}")
source = source.replace(old_guard, new_guard, 1)

old_log = """            await refreshLedgerSnapshot()
            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })"""
new_log = """            await refreshLedgerSnapshot()
            let eventUpdate = Self.redactingAccountUID(in: update, accountUID: acceptedAccountUID)
            log("tuya_application_update", eventUpdate.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { _, trusted in trusted })"""
if source.count(old_log) != 1:
    raise SystemExit(f"expected one current application event log, found {source.count(old_log)}")
source = source.replace(old_log, new_log, 1)

marker = "    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {\n"
if source.count(marker) != 1:
    raise SystemExit("startWatchdog insertion marker changed")
helper = """    private static func redactingAccountUID(
        in update: [String: String],
        accountUID: String
    ) -> [String: String] {
        func scrub(_ value: String) -> String {
            value.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
        }

        var redacted: [String: String] = [:]
        for key in update.keys.sorted() {
            let redactedKey = scrub(key)
            var uniqueKey = redactedKey
            var collisionIndex = 2
            while redacted[uniqueKey] != nil {
                uniqueKey = "\\(redactedKey)#redacted-\\(collisionIndex)"
                collisionIndex += 1
            }
            redacted[uniqueKey] = scrub(update[key] ?? "")
        }
        return redacted
    }

"""
source = source.replace(marker, helper + marker, 1)

duplicate = """        "refreshtoken",
        "sessionkey",
        "authkey","""
simplified = """        "refreshtoken",
        "authkey","""
if source.count(duplicate) != 1:
    raise SystemExit("duplicate sessionkey classifier shape changed")
source = source.replace(duplicate, simplified, 1)
source_path.write_text(source, encoding="utf-8")

precedence_test = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationEventMetadataPrecedenceSourceTests.swift")
if precedence_test.exists():
    raise SystemExit("generation precedence regression unexpectedly already exists")
precedence_test.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application event metadata precedence")
struct TuyaApplicationEventMetadataPrecedenceSourceTests {
    @Test("SDK application keys cannot overwrite Nembra generation provenance")
    func trustedGenerationWinsReservedKeyCollision() throws {
        let source = try entrypointSource()
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private static func redactingAccountUID("))

        #expect(receiver.contains("log(\"tuya_application_update\", eventUpdate.merging(["))
        #expect(receiver.contains("\"generation\": String(token.diagnosticGeneration)"))
        #expect(receiver.contains(") { _, trusted in trusted })"))
        #expect(!receiver.contains(") { current, _ in current })"))
    }

    private func entrypointSource() throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"), encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw ContractError.missing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private enum ContractError: Error { case missing }
}
''', encoding="utf-8")

uid_test = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationAccountUIDExportCustodySourceTests.swift")
if uid_test.exists():
    raise SystemExit("account UID custody regression unexpectedly already exists")
uid_test.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account-UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted application evidence binds the earned UID before event custody")
    func admissionRequiresAndScrubsVerifiedAccountUID() throws {
        let source = try entrypointSource()
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private static func redactingAccountUID("))

        let lease = try #require(receiver.range(of: "accountIdentityLeaseIsAuthorized"))
        let uid = try #require(receiver.range(of: "let acceptedAccountUID = membershipAccountUID?.trimmingCharacters"))
        let custody = try #require(receiver.range(of: "let eventUpdate = Self.redactingAccountUID(in: update, accountUID: acceptedAccountUID)"))
        let log = try #require(receiver.range(of: "log(\"tuya_application_update\", eventUpdate.merging(["))
        #expect(lease.lowerBound < uid.lowerBound)
        #expect(uid.lowerBound < custody.lowerBound)
        #expect(custody.lowerBound < log.lowerBound)
        #expect(!receiver.contains("log(\"tuya_application_update\", update.merging(["))
    }

    @Test("exact account UID is scrubbed from keys and values without banning generic uid fields")
    func exactValueBoundScrubberPreservesOpaqueUIDNamedEvidence() throws {
        let source = try entrypointSource()
        let helper = String(try section(in: source, from: "private static func redactingAccountUID(", to: "private func startWatchdog"))
        let driver = String(try section(in: source, from: "private static let secretKeyFragments = [", to: "private static func redactApplicationSecrets"))

        #expect(helper.contains("let redactedKey = scrub(key)"))
        #expect(helper.contains("redacted[uniqueKey] = scrub(update[key] ?? \"\")"))
        #expect(helper.contains("<redacted-account-uid>"))
        #expect(helper.contains("for key in update.keys.sorted()"))
        #expect(!driver.contains("\"uid\","))
        #expect(driver.components(separatedBy: "\"sessionkey\"").count - 1 == 1)
    }

    private func entrypointSource() throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"), encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw ContractError.missing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private enum ContractError: Error { case missing }
}
''', encoding="utf-8")

Path(".github/workflows/capture-event-custody-materialize.yml").unlink()
Path("scripts/ci/materialize_capture_event_custody.py").unlink()
