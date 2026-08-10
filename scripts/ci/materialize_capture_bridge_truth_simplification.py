from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BRIDGE = ROOT / "NembraApp/Features/Research/TuyaAccountBridge.swift"
ROOT_TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureRootProductSurfaceSourceTests.swift"
STATUS_TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaMetadataStatusSecretRedactionSourceTests.swift"

LEGACY_MARKER = "\nstruct NembraCaptureRootView: View {"
ROOT_TEST_INSERTION = "    private func section(in source: String, from start: String, to end: String) throws -> Substring {"
RAW_STATUS_RETENTION = "        selectedDeviceStatus = statusMap"
REDACTED_STATUS_RETENTION = "        selectedDeviceStatus = Self.redactSecrets(statusMap) as? [String: Any] ?? [:]"
RAW_STATUS_EXPORT = '            "status": selectedDeviceStatus ?? [:],'
REDACTED_STATUS_EXPORT = '            "status": Self.redactSecrets(selectedDeviceStatus ?? [:]),'

ROOT_TEST_ADDITION = '''    @Test("legacy card-based Capture root is retired from the metadata bridge")
    func legacyCardRootIsRetired() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")

        #expect(bridge.contains("final class TuyaAccountBridge: ObservableObject"))
        #expect(bridge.contains("struct TuyaQRCodeExport: Transferable"))
        #expect(bridge.contains("struct TuyaMetadataExport: Transferable"))
        #expect(!bridge.contains("struct NembraCaptureRootView: View"))
        #expect(!bridge.contains("func captureCard() -> some View"))
        #expect(!bridge.contains("Link Tuya first"))
        #expect(!bridge.contains("Continue to Bluetooth Capture"))
    }

'''

STATUS_TEST_CONTENT = r'''import Foundation
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

        #expect(body.contains("\"status\": Self.redactSecrets(selectedDeviceStatus ?? [:])"))
        #expect(!body.contains("\"status\": selectedDeviceStatus ?? [:]"))
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
'''


def require_count(text: str, token: str, count: int, label: str) -> None:
    actual = text.count(token)
    if actual != count:
        raise SystemExit(f"{label}: expected {count} match(es), found {actual}")


def apply() -> None:
    bridge = BRIDGE.read_text(encoding="utf-8")
    require_count(bridge, RAW_STATUS_RETENTION, 1, "raw status retention")
    require_count(bridge, RAW_STATUS_EXPORT, 1, "raw status export")
    require_count(bridge, LEGACY_MARKER, 1, "legacy root marker")

    bridge = bridge.replace(RAW_STATUS_RETENTION, REDACTED_STATUS_RETENTION, 1)
    bridge = bridge.replace(RAW_STATUS_EXPORT, REDACTED_STATUS_EXPORT, 1)
    kept, _ = bridge.split(LEGACY_MARKER, 1)
    BRIDGE.write_text(kept.rstrip() + "\n", encoding="utf-8")

    root_test = ROOT_TEST.read_text(encoding="utf-8")
    if "func legacyCardRootIsRetired()" in root_test:
        raise SystemExit("legacy-root retirement regression already exists")
    require_count(root_test, ROOT_TEST_INSERTION, 1, "Capture root source-test insertion point")
    ROOT_TEST.write_text(
        root_test.replace(ROOT_TEST_INSERTION, ROOT_TEST_ADDITION + ROOT_TEST_INSERTION, 1),
        encoding="utf-8",
    )

    if STATUS_TEST.exists():
        raise SystemExit("status-secret regression path already exists on exact product parent")
    STATUS_TEST.write_text(STATUS_TEST_CONTENT, encoding="utf-8")


def verify() -> None:
    bridge = BRIDGE.read_text(encoding="utf-8")
    required = (
        "final class TuyaAccountBridge: ObservableObject",
        "struct TuyaQRCodeExport: Transferable",
        "struct TuyaMetadataExport: Transferable",
        REDACTED_STATUS_RETENTION.strip(),
        REDACTED_STATUS_EXPORT.strip(),
    )
    forbidden = (
        "struct NembraCaptureRootView: View",
        "func captureCard() -> some View",
        "Link Tuya first",
        "Continue to Bluetooth Capture",
        RAW_STATUS_RETENTION.strip(),
        RAW_STATUS_EXPORT.strip(),
    )
    for token in required:
        if token not in bridge:
            raise SystemExit(f"required bridge truth/surface missing: {token}")
    for token in forbidden:
        if token in bridge:
            raise SystemExit(f"forbidden legacy/raw bridge token survived: {token}")

    root_test = ROOT_TEST.read_text(encoding="utf-8")
    if root_test.count("func legacyCardRootIsRetired()") != 1:
        raise SystemExit("legacy-root retirement regression missing or duplicated")
    for token in (
        "final class TuyaAccountBridge: ObservableObject",
        "struct TuyaQRCodeExport: Transferable",
        "struct TuyaMetadataExport: Transferable",
        "struct NembraCaptureRootView: View",
        "func captureCard() -> some View",
        "Link Tuya first",
        "Continue to Bluetooth Capture",
    ):
        if token not in root_test:
            raise SystemExit(f"legacy-root regression does not pin token: {token}")

    if not STATUS_TEST.exists():
        raise SystemExit("status-secret regression was not created")
    status_test = STATUS_TEST.read_text(encoding="utf-8")
    for token in (
        "selectedDeviceStatus = Self.redactSecrets(statusMap) as? [String: Any] ?? [:]",
        r'\"status\": Self.redactSecrets(selectedDeviceStatus ?? [:])',
        "selectedDeviceStatus = statusMap",
        r'\"status\": selectedDeviceStatus ?? [:]',
    ):
        if token not in status_test:
            raise SystemExit(f"status-secret regression does not pin token: {token}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
