from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
BRIDGE = Path("NembraApp/Features/Research/TuyaAccountBridge.swift")
META_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaMetadataSecretRedactionSourceTests.swift")
UID_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationAccountUIDExportCustodySourceTests.swift")
PROVENANCE_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationEventMetadataPrecedenceSourceTests.swift")

FRAGMENTS = (
    "localkey", "sessionkey", "appkey", "appsecret", "password",
    "accounttoken", "accesstoken", "refreshtoken", "authkey", "seckey",
)


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

    old_log = '''            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })
'''
    new_log = '''            var eventDetails = redactedApplicationEventDetails(update)
            eventDetails["generation"] = String(token.diagnosticGeneration)
            log("tuya_application_update", eventDetails)
'''
    app = replace_once(app, old_log, new_log, "accepted application event provenance")

    marker = "\n    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {"
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
    app = replace_once(app, marker, helper + marker, "leased account UID event redactor")
    APP.write_text(app, encoding="utf-8")

    bridge = BRIDGE.read_text(encoding="utf-8")
    old_bridge = '            let secretKeyFragments = ["localkey", "accesstoken", "refreshtoken", "sessionkey", "seckey", "authkey"]\n'
    new_bridge = '            let secretKeyFragments = ["localkey", "sessionkey", "appkey", "appsecret", "password", "accounttoken", "accesstoken", "refreshtoken", "authkey", "seckey"]\n'
    BRIDGE.write_text(replace_once(bridge, old_bridge, new_bridge, "metadata classifier parity"), encoding="utf-8")

    test = META_TEST.read_text(encoding="utf-8")
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
    META_TEST.write_text(replace_once(test, old_assertions, new_assertions, "metadata classifier regression"), encoding="utf-8")

    if UID_TEST.exists() or PROVENANCE_TEST.exists():
        raise SystemExit("expected-red regression file unexpectedly exists on exact product parent")

    UID_TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted event scrubs the exact leased account UID from untrusted keys and values")
    func acceptedEventScrubsExactLeasedAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        #expect(receiver.contains("redactedApplicationEventDetails(update)"))
        #expect(receiver.contains("membershipAccountUID?.trimmingCharacters"))
        #expect(receiver.contains("let redactedKey = key.replacingOccurrences("))
        #expect(receiver.contains("value.replacingOccurrences("))
        #expect(receiver.contains("<redacted-account-uid>"))
        #expect(receiver.contains("options: [.caseInsensitive, .literal]"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { throw Error.sectionMissing }
        return source[a.lowerBound..<b.lowerBound]
    }
    private func readRepositoryFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
    private enum Error: Swift.Error { case sectionMissing }
}
''', encoding="utf-8")

    PROVENANCE_TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya accepted application-event provenance")
struct TuyaApplicationEventMetadataPrecedenceSourceTests {
    @Test("trusted generation is stamped after untrusted event redaction")
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
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { throw Error.sectionMissing }
        return source[a.lowerBound..<b.lowerBound]
    }
    private func readRepositoryFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
    private enum Error: Swift.Error { case sectionMissing }
}
''', encoding="utf-8")


def verify() -> None:
    app = APP.read_text(encoding="utf-8")
    a = app.index("private func receivedApplicationUpdate(")
    b = app.index("private func startWatchdog", a)
    receiver = app[a:b]
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
        raise SystemExit("untrusted-first event logging survived")
    if receiver.index("redactedApplicationEventDetails(update)") >= receiver.index('eventDetails["generation"]'):
        raise SystemExit("redaction must precede trusted generation stamp")
    if receiver.index('eventDetails["generation"]') >= receiver.index('log("tuya_application_update", eventDetails)'):
        raise SystemExit("trusted generation stamp must precede accepted log")

    smart0 = app.index("private static let secretKeyFragments = [", app.index("private final class SmartLifeDriver"))
    smart1 = app.index("private static func redactApplicationSecrets", smart0)
    app_classifier = app[smart0:smart1]
    bridge = BRIDGE.read_text(encoding="utf-8")
    meta0 = bridge.index("private static func redactSecrets(_ object: Any) -> Any")
    meta1 = bridge.index("private static func remoteMessage", meta0)
    meta = bridge[meta0:meta1]
    for fragment in FRAGMENTS:
        token = f'"{fragment}"'
        if app_classifier.count(token) != 1:
            raise SystemExit(f"application classifier must contain {fragment} exactly once")
        if meta.count(token) != 1:
            raise SystemExit(f"metadata classifier must contain {fragment} exactly once")
    if "array.map(redactApplicationSecrets)" not in app or "array.map(redactSecrets)" not in meta:
        raise SystemExit("recursive array redaction missing")
    for path, marker in ((UID_TEST, "acceptedEventScrubsExactLeasedAccountUID"), (PROVENANCE_TEST, "trustedGenerationWinsReservedCollision")):
        if marker not in path.read_text(encoding="utf-8"):
            raise SystemExit(f"regression marker missing: {marker}")


if __name__ == "__main__":
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("mode", choices=("apply", "verify"))
    args = p.parse_args()
    apply() if args.mode == "apply" else verify()
