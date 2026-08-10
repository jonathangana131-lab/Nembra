from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
BRIDGE = Path("NembraApp/Features/Research/TuyaAccountBridge.swift")
META_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaMetadataSecretRedactionSourceTests.swift")
STATUS_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSecureLinkViewMembershipStatusRevocationSourceTests.swift")
UID_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationAccountUIDExportCustodySourceTests.swift")
PROVENANCE_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationEventMetadataPrecedenceSourceTests.swift")

FRAGMENTS = (
    "localkey", "sessionkey", "appkey", "appsecret", "password",
    "accounttoken", "accesstoken", "refreshtoken", "authkey", "seckey",
)
STATUS_COPY = "Exact scooter membership must be verified again for this Secure Link session."


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def apply() -> None:
    app = APP.read_text(encoding="utf-8")

    duplicated = '''    private static let secretKeyFragments = [
        "localkey",
        "sessionkey",
        "appkey",
        "appsecret",
        "password",
        "accounttoken",
        "accesstoken",
        "refreshtoken",
        "sessionkey",
        "authkey",
        "seckey",
    ]
'''
    canonical = '''    private static let secretKeyFragments = [
        "localkey",
        "sessionkey",
        "appkey",
        "appsecret",
        "password",
        "accounttoken",
        "accesstoken",
        "refreshtoken",
        "authkey",
        "seckey",
    ]
'''
    app = replace_once(app, duplicated, canonical, "deduplicate application secret classifier")

    revoked = '''        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipRequestID = UUID()
'''
    revoked_with_status = f'''        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = "{STATUS_COPY}"
        membershipRequestID = UUID()
'''
    count = app.count(revoked)
    if count != 2:
        raise SystemExit(f"membership authority revocation blocks: expected two, found {count}")
    app = app.replace(revoked, revoked_with_status)

    old_log = '''            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })
'''
    new_log = '''            var eventDetails = redactedApplicationEventDetails(update)
            eventDetails["generation"] = String(token.diagnosticGeneration)
            log("tuya_application_update", eventDetails)
'''
    app = replace_once(app, old_log, new_log, "accepted application event provenance")

    helper_marker = "\n    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {"
    helper = r'''
    private func redactedApplicationEventDetails(_ update: [String: String]) -> [String: String] {
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
    app = replace_once(app, helper_marker, helper + helper_marker, "account UID event redactor")
    APP.write_text(app, encoding="utf-8")

    bridge = BRIDGE.read_text(encoding="utf-8")
    old_bridge = '            let secretKeyFragments = ["localkey", "accesstoken", "refreshtoken", "sessionkey", "seckey", "authkey"]\n'
    new_bridge = '            let secretKeyFragments = ["localkey", "sessionkey", "appkey", "appsecret", "password", "accounttoken", "accesstoken", "refreshtoken", "authkey", "seckey"]\n'
    BRIDGE.write_text(replace_once(bridge, old_bridge, new_bridge, "metadata classifier parity"), encoding="utf-8")

    meta_test = META_TEST.read_text(encoding="utf-8")
    old_assertions = '''        #expect(body.contains("localkey"))
        #expect(body.contains("accesstoken"))
        #expect(body.contains("refreshtoken"))
        #expect(body.contains("sessionkey"))
        #expect(body.contains("authkey"))
        #expect(body.contains("seckey"))
'''
    new_assertions = '''        for fragment in [
            "localkey",
            "sessionkey",
            "appkey",
            "appsecret",
            "password",
            "accounttoken",
            "accesstoken",
            "refreshtoken",
            "authkey",
            "seckey",
        ] {
            #expect(body.contains("\\\"\\(fragment)\\\""), "Metadata sanitizer must redact every export-promised credential key: \\(fragment)")
        }
'''
    META_TEST.write_text(replace_once(meta_test, old_assertions, new_assertions, "metadata classifier regression"), encoding="utf-8")

    if STATUS_TEST.exists() or UID_TEST.exists() or PROVENANCE_TEST.exists():
        raise SystemExit("expected-red regression path unexpectedly already exists on exact product parent")

    STATUS_TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Secure Link revoked membership presentation")
struct TuyaSecureLinkViewMembershipStatusRevocationSourceTests {
    @Test("both view exit and foreground loss revoke positive membership copy with proof")
    func revokedMembershipStatusTracksAuthority() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let viewExit = String(try section(in: source, from: "func abandonCorrelationForViewExit()", to: "func appDidLoseForeground()"))
        let foreground = String(try section(in: source, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))
        for cleanup in [viewExit, foreground] {
            let clearProof = try #require(cleanup.range(of: "sdkDeviceMembershipVerified = false"))
            let resetStatus = try #require(cleanup.range(of: "membershipStatus = \"Exact scooter membership must be verified again for this Secure Link session.\""))
            let revokeRequest = try #require(cleanup.range(of: "membershipRequestID = UUID()"))
            #expect(clearProof.lowerBound < resetStatus.lowerBound)
            #expect(resetStatus.lowerBound < revokeRequest.lowerBound)
            #expect(!cleanup.contains("membershipStatus = \"Exact scooter membership verified and leased to this current SDK account.\""))
        }
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start), let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }
    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
    private enum SourceContractError: Error { case sectionMissing }
}
''', encoding="utf-8")

    UID_TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted event scrubs the exact leased account UID from keys and values")
    func acceptedApplicationEventScrubsExactAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        #expect(receiver.contains("redactedApplicationEventDetails(update)"))
        #expect(receiver.contains("membershipAccountUID?.trimmingCharacters"))
        #expect(receiver.contains("<redacted-account-uid>"))
        #expect(receiver.contains("let redactedKey = key.replacingOccurrences("))
        #expect(receiver.contains("value.replacingOccurrences("))
        #expect(receiver.contains("options: [.caseInsensitive, .literal]"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start), let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else { throw SourceContractError.sectionMissing }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }
    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
    private enum SourceContractError: Error { case sectionMissing }
}
''', encoding="utf-8")

    PROVENANCE_TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya accepted application-event provenance")
struct TuyaApplicationEventMetadataPrecedenceSourceTests {
    @Test("trusted Nembra generation is stamped after untrusted event redaction")
    func trustedGenerationWinsReservedCollision() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        let redaction = try #require(receiver.range(of: "var eventDetails = redactedApplicationEventDetails(update)"))
        let generation = try #require(receiver.range(of: "eventDetails[\"generation\"] = String(token.diagnosticGeneration)"))
        let log = try #require(receiver.range(of: "log(\"tuya_application_update\", eventDetails)"))
        #expect(redaction.lowerBound < generation.lowerBound)
        #expect(generation.lowerBound < log.lowerBound)
        #expect(!receiver.contains("update.merging(["))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start), let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else { throw SourceContractError.sectionMissing }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }
    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
    private enum SourceContractError: Error { case sectionMissing }
}
''', encoding="utf-8")


def verify() -> None:
    app = APP.read_text(encoding="utf-8")
    for start, end in (("func abandonCorrelationForViewExit()", "func appDidLoseForeground()"), ("func appDidLoseForeground()", "var privateConfig: Bool")):
        a = app.index(start); b = app.index(end, a); cleanup = app[a:b]
        order = [
            "sdkDeviceMembershipVerified = false",
            f'membershipStatus = "{STATUS_COPY}"',
            "membershipRequestID = UUID()",
        ]
        offsets = [cleanup.index(token) for token in order]
        if offsets != sorted(offsets):
            raise SystemExit(f"membership presentation revocation order invalid in {start}")

    receiver_start = app.index("private func receivedApplicationUpdate(")
    receiver_end = app.index("private func startWatchdog", receiver_start)
    receiver = app[receiver_start:receiver_end]
    required = (
        "var eventDetails = redactedApplicationEventDetails(update)",
        'eventDetails["generation"] = String(token.diagnosticGeneration)',
        'log("tuya_application_update", eventDetails)',
        "membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines)",
        "let redactedKey = key.replacingOccurrences(",
        "value.replacingOccurrences(",
        'with: "<redacted-account-uid>"',
        "options: [.caseInsensitive, .literal]",
    )
    for token in required:
        if token not in receiver:
            raise SystemExit(f"accepted event custody token missing: {token}")
    if "update.merging([" in receiver or 'log("tuya_application_update", update' in receiver:
        raise SystemExit("untrusted-first accepted event custody survived")
    if receiver.index("redactedApplicationEventDetails(update)") >= receiver.index('eventDetails["generation"]'):
        raise SystemExit("UID redaction must precede trusted generation stamping")

    smart_start = app.index("private static let secretKeyFragments = [", app.index("private final class SmartLifeDriver"))
    smart_end = app.index("private static func redactApplicationSecrets", smart_start)
    app_classifier = app[smart_start:smart_end]
    bridge = BRIDGE.read_text(encoding="utf-8")
    meta_start = bridge.index("private static func redactSecrets(_ object: Any) -> Any")
    meta_end = bridge.index("private static func remoteMessage", meta_start)
    meta = bridge[meta_start:meta_end]
    for fragment in FRAGMENTS:
        token = f'"{fragment}"'
        if app_classifier.count(token) != 1:
            raise SystemExit(f"application classifier must contain {fragment} exactly once")
        if meta.count(token) != 1:
            raise SystemExit(f"metadata classifier must contain {fragment} exactly once")
    if "array.map(redactSecrets)" not in meta or "array.map(redactApplicationSecrets)" not in app:
        raise SystemExit("recursive array redaction missing")

    for path, marker in (
        (STATUS_TEST, "revokedMembershipStatusTracksAuthority"),
        (UID_TEST, "acceptedApplicationEventScrubsExactAccountUID"),
        (PROVENANCE_TEST, "trustedGenerationWinsReservedCollision"),
    ):
        if marker not in path.read_text(encoding="utf-8"):
            raise SystemExit(f"regression marker missing: {marker}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
