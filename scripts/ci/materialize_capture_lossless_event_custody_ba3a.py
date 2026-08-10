from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
UID_TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationAccountUIDExportCustodySourceTests.swift"
PROVENANCE_TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationEventMetadataPrecedenceSourceTests.swift"
PARENT = "ba3a1eeae36caca6dd84beaabd0f15f4f0b57925"

CALLER_OLD = '''            var eventDetails = redactedApplicationEventDetails(update)\n            eventDetails["generation"] = String(token.diagnosticGeneration)\n            log("tuya_application_update", eventDetails)\n'''
CALLER_NEW = '''            let eventDetails = TuyaAuthenticatedApplicationEventCustody.eventDetails(\n                applicationUpdate: update,\n                trustedGeneration: String(token.diagnosticGeneration),\n                accountUID: membershipAccountUID\n            )\n            log("tuya_application_update", eventDetails)\n'''

HELPER_OLD = '''\n    private func redactedApplicationEventDetails(_ update: [String: String]) -> [String: String] {\n        guard let accountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),\n              !accountUID.isEmpty else {\n            return update\n        }\n\n        var redacted: [String: String] = [:]\n        redacted.reserveCapacity(update.count)\n        for (key, value) in update {\n            let redactedKey = key.replacingOccurrences(\n                of: accountUID,\n                with: "<redacted-account-uid>",\n                options: [.caseInsensitive, .literal]\n            )\n            redacted[redactedKey] = value.replacingOccurrences(\n                of: accountUID,\n                with: "<redacted-account-uid>",\n                options: [.caseInsensitive, .literal]\n            )\n        }\n        return redacted\n    }\n'''

UID_TEST_NEW = '''import Foundation\nimport Testing\n@testable import NembraBluetoothCapture\n\n@Suite("Tuya application account UID export custody")\nstruct TuyaApplicationAccountUIDExportCustodySourceTests {\n    @Test("accepted event delegates exact leased account UID custody before logging")\n    func acceptedEventDelegatesExactLeasedAccountUIDCustody() throws {\n        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")\n        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))\n        let custody = try #require(receiver.range(of: "TuyaAuthenticatedApplicationEventCustody.eventDetails("))\n        let accountUID = try #require(receiver.range(of: "accountUID: membershipAccountUID"))\n        let log = try #require(receiver.range(of: "log(\\"tuya_application_update\\", eventDetails)"))\n        #expect(custody.lowerBound < accountUID.lowerBound)\n        #expect(accountUID.lowerBound < log.lowerBound)\n        #expect(!receiver.contains("redactedApplicationEventDetails(update)"))\n        #expect(!receiver.contains("log(\\"tuya_application_update\\", update"))\n    }\n\n    private func section(in source: String, from start: String, to end: String) throws -> Substring {\n        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { throw Error.sectionMissing }\n        return source[a.lowerBound..<b.lowerBound]\n    }\n    private func readRepositoryFile(_ path: String) throws -> String {\n        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()\n        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)\n    }\n    private enum Error: Swift.Error { case sectionMissing }\n}\n'''

PROVENANCE_TEST_NEW = '''import Foundation\nimport Testing\n@testable import NembraBluetoothCapture\n\n@Suite("Tuya accepted application-event provenance")\nstruct TuyaApplicationEventMetadataPrecedenceSourceTests {\n    @Test("trusted generation is owned by package custody before immutable event logging")\n    func trustedGenerationWinsWithoutDiscardingApplicationEvidence() throws {\n        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")\n        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))\n        let custody = try #require(receiver.range(of: "TuyaAuthenticatedApplicationEventCustody.eventDetails("))\n        let generation = try #require(receiver.range(of: "trustedGeneration: String(token.diagnosticGeneration)"))\n        let log = try #require(receiver.range(of: "log(\\"tuya_application_update\\", eventDetails)"))\n        #expect(custody.lowerBound < generation.lowerBound)\n        #expect(generation.lowerBound < log.lowerBound)\n        #expect(!receiver.contains("eventDetails[\\"generation\\"] ="))\n        #expect(!receiver.contains("update.merging(["))\n    }\n\n    private func section(in source: String, from start: String, to end: String) throws -> Substring {\n        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { throw Error.sectionMissing }\n        return source[a.lowerBound..<b.lowerBound]\n    }\n    private func readRepositoryFile(_ path: String) throws -> String {\n        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()\n        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)\n    }\n    private enum Error: Swift.Error { case sectionMissing }\n}\n'''


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def apply() -> None:
    source = APP.read_text(encoding="utf-8")
    source = replace_once(source, CALLER_OLD, CALLER_NEW, "application event custody caller")
    source = replace_once(source, HELPER_OLD, "", "lossy inline event redactor")
    APP.write_text(source, encoding="utf-8")
    UID_TEST.write_text(UID_TEST_NEW, encoding="utf-8")
    PROVENANCE_TEST.write_text(PROVENANCE_TEST_NEW, encoding="utf-8")


def verify() -> None:
    source = APP.read_text(encoding="utf-8")
    start = source.index("    private func receivedApplicationUpdate(")
    end = source.index("    private func startWatchdog", start)
    receiver = source[start:end]
    for token in (
        "TuyaAuthenticatedApplicationEventCustody.eventDetails(",
        "applicationUpdate: update",
        "trustedGeneration: String(token.diagnosticGeneration)",
        "accountUID: membershipAccountUID",
        "log(\"tuya_application_update\", eventDetails)",
    ):
        if token not in receiver:
            raise SystemExit(f"receiver missing lossless custody token: {token}")
    for forbidden in (
        "redactedApplicationEventDetails(",
        "eventDetails[\"generation\"] =",
        "update.merging([",
        "log(\"tuya_application_update\", update",
    ):
        if forbidden in receiver:
            raise SystemExit(f"receiver retains lossy custody path: {forbidden}")

    primitive_path = ROOT / "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedApplicationEventCustody.swift"
    primitive = primitive_path.read_text(encoding="utf-8")
    for token in (
        "for key in applicationUpdate.keys.sorted()",
        "var occupiedKeys: Set<String> = [trustedGenerationKey]",
        "while occupiedKeys.contains(admittedKey)",
        "admittedKey = \"application.\\(admittedKey)\"",
        "output[trustedGenerationKey] = trustedGeneration",
        "accountUIDRedactionMarker = \"<redacted-account-uid>\"",
    ):
        if token not in primitive:
            raise SystemExit(f"primitive missing deterministic preservation contract: {token}")

    for path in (UID_TEST, PROVENANCE_TEST):
        test = path.read_text(encoding="utf-8")
        if "TuyaAuthenticatedApplicationEventCustody.eventDetails(" not in test:
            raise SystemExit(f"updated source contract not pinned in {path.name}")

    # Preserve the already-composed foreground/privacy truth on this exact parent.
    for token in (
        "guard phase != .accepted else { return }",
        "foreground_integrity_lost_after_target_correlation",
        "Exact scooter membership must be verified again after Capture leaves Secure Link authority.",
    ):
        if token not in source:
            raise SystemExit(f"ba3a accepted dependency missing: {token}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
