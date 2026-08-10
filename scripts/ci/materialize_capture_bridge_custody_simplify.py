from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BRIDGE = ROOT / "NembraApp/Features/Research/TuyaAccountBridge.swift"
ROOT_TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureRootProductSurfaceSourceTests.swift"
STATUS_TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaMetadataStatusSecretRedactionSourceTests.swift"

LEGACY_MARKER = "\nstruct NembraCaptureRootView: View {"
ROOT_TEST_INSERTION = "    private func section(in source: String, from start: String, to end: String) throws -> Substring {"

ROOT_TEST_ADDITION = '''    @Test("legacy card-based Capture root is retired from the metadata bridge")
    func legacyCardRootIsRetired() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")

        #expect(bridge.contains("final class TuyaAccountBridge: ObservableObject"))
        #expect(bridge.contains("struct TuyaQRCodeExport: Transferable"))
        #expect(bridge.contains("struct TuyaMetadataExport: Transferable"))
        #expect(!bridge.contains("struct NembraCaptureRootView: View"))
        #expect(!bridge.contains("func captureCard() -> some View"))
        #expect(!bridge.contains("ES80OneTimeBluetoothDumpView()"))
        #expect(!bridge.contains("We already proved this scooter uses Tuya FD50."))
        #expect(!bridge.contains("Continue to Bluetooth Capture"))
    }

'''

STATUS_TEST_SOURCE = '''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya metadata status secret redaction source contract")
struct TuyaMetadataStatusSecretRedactionSourceTests {
    @Test("raw status entries are redacted before retained UI state")
    func statusAdmissionCannotBypassRecursiveSecretRedaction() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let load = try section(
            in: bridge,
            from: "private func loadSelectedDeviceDetails",
            to: "private func signedGET"
        )
        let body = String(load)

        #expect(body.contains("selectedDeviceStatus = Self.redactSecrets(statusMap) as? [String: Any] ?? [:]"))
        #expect(!body.contains("selectedDeviceStatus = statusMap"))
    }

    @Test("export re-applies redaction to retained status as defense in depth")
    func exportCannotTrustRetainedStatusMapWithoutRedaction() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        let export = try section(
            in: bridge,
            from: "func prepareRedactedExport()",
            to: "func resetLink()"
        )
        let body = String(export)

        #expect(body.contains("\\\"status\\\": Self.redactSecrets(selectedDeviceStatus ?? [:])"))
        #expect(!body.contains("\\\"status\\\": selectedDeviceStatus ?? [:]"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \\(start) ... \\(end)")
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
'''


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def apply() -> None:
    bridge = BRIDGE.read_text(encoding="utf-8")
    bridge = replace_once(
        bridge,
        '            "status": selectedDeviceStatus ?? [:],\n',
        '            "status": Self.redactSecrets(selectedDeviceStatus ?? [:]),\n',
        "export status redaction",
    )
    bridge = replace_once(
        bridge,
        "        selectedDeviceStatus = statusMap\n",
        "        selectedDeviceStatus = Self.redactSecrets(statusMap) as? [String: Any] ?? [:]\n",
        "retained status redaction",
    )
    if bridge.count(LEGACY_MARKER) != 1:
        raise SystemExit(f"legacy root marker: expected exactly one match, found {bridge.count(LEGACY_MARKER)}")
    bridge, _ = bridge.split(LEGACY_MARKER, 1)
    BRIDGE.write_text(bridge.rstrip() + "\n", encoding="utf-8")

    root_test = ROOT_TEST.read_text(encoding="utf-8")
    if "func legacyCardRootIsRetired()" in root_test:
        raise SystemExit("legacy retirement regression already exists")
    if root_test.count(ROOT_TEST_INSERTION) != 1:
        raise SystemExit("Capture root test insertion point changed")
    ROOT_TEST.write_text(root_test.replace(ROOT_TEST_INSERTION, ROOT_TEST_ADDITION + ROOT_TEST_INSERTION, 1), encoding="utf-8")

    if STATUS_TEST.exists():
        raise SystemExit("status redaction regression unexpectedly already exists on product parent")
    STATUS_TEST.write_text(STATUS_TEST_SOURCE, encoding="utf-8")


def verify() -> None:
    bridge = BRIDGE.read_text(encoding="utf-8")
    required = (
        "final class TuyaAccountBridge: ObservableObject",
        "struct TuyaQRCodeExport: Transferable",
        "struct TuyaMetadataExport: Transferable",
        '"status": Self.redactSecrets(selectedDeviceStatus ?? [:])',
        "selectedDeviceStatus = Self.redactSecrets(statusMap) as? [String: Any] ?? [:]",
    )
    forbidden = (
        '"status": selectedDeviceStatus ?? [:]',
        "selectedDeviceStatus = statusMap",
        "struct NembraCaptureRootView: View",
        "func captureCard() -> some View",
        "ES80OneTimeBluetoothDumpView()",
        "We already proved this scooter uses Tuya FD50.",
        "Continue to Bluetooth Capture",
    )
    for token in required:
        if token not in bridge:
            raise SystemExit(f"required product token missing: {token}")
    for token in forbidden:
        if token in bridge:
            raise SystemExit(f"forbidden stale/unsafe product token survived: {token}")

    root_test = ROOT_TEST.read_text(encoding="utf-8")
    if root_test.count("func legacyCardRootIsRetired()") != 1:
        raise SystemExit("legacy retirement regression missing or duplicated")
    status_test = STATUS_TEST.read_text(encoding="utf-8")
    for token in (
        "statusAdmissionCannotBypassRecursiveSecretRedaction",
        "exportCannotTrustRetainedStatusMapWithoutRedaction",
        "selectedDeviceStatus = Self.redactSecrets(statusMap) as? [String: Any] ?? [:]",
        '\\"status\\": Self.redactSecrets(selectedDeviceStatus ?? [:])',
    ):
        if token not in status_test:
            raise SystemExit(f"status regression token missing: {token}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
