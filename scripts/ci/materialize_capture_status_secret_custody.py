from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BRIDGE = ROOT / "NembraApp/Features/Research/TuyaAccountBridge.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaMetadataStatusSecretRedactionSourceTests.swift"

RAW_RETAIN = "selectedDeviceStatus = statusMap"
SAFE_RETAIN = "selectedDeviceStatus = Self.redactSecrets(statusMap) as? [String: Any] ?? [:]"
RAW_EXPORT = '"status": selectedDeviceStatus ?? [:],'
SAFE_EXPORT = '"status": Self.redactSecrets(selectedDeviceStatus ?? [:]),'

TEST_CONTENT = r'''import Foundation
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


def apply() -> None:
    bridge = BRIDGE.read_text(encoding="utf-8")
    if bridge.count(RAW_RETAIN) != 1:
        raise SystemExit(f"raw retained-status boundary changed: expected 1, found {bridge.count(RAW_RETAIN)}")
    if bridge.count(RAW_EXPORT) != 1:
        raise SystemExit(f"raw status export boundary changed: expected 1, found {bridge.count(RAW_EXPORT)}")
    if SAFE_RETAIN in bridge or SAFE_EXPORT in bridge:
        raise SystemExit("status secret-custody repair is already partially present; re-inspect instead of double-applying")

    bridge = bridge.replace(RAW_RETAIN, SAFE_RETAIN, 1)
    bridge = bridge.replace(RAW_EXPORT, SAFE_EXPORT, 1)
    BRIDGE.write_text(bridge, encoding="utf-8")

    if TEST.exists():
        raise SystemExit("status secret-custody regression already exists; re-inspect current product")
    TEST.write_text(TEST_CONTENT, encoding="utf-8")


def verify() -> None:
    bridge = BRIDGE.read_text(encoding="utf-8")
    if bridge.count(SAFE_RETAIN) != 1 or RAW_RETAIN in bridge:
        raise SystemExit("retained status is not uniquely redacted before UI-state custody")
    if bridge.count(SAFE_EXPORT) != 1 or RAW_EXPORT in bridge:
        raise SystemExit("export does not uniquely re-apply status redaction")

    if not TEST.exists():
        raise SystemExit("status secret-custody regression file is missing")
    test = TEST.read_text(encoding="utf-8")
    required = (
        SAFE_RETAIN,
        '"status": Self.redactSecrets(selectedDeviceStatus ?? [:])',
        'func statusAdmissionCannotBypassRecursiveSecretRedaction()',
        'func exportCannotTrustRetainedStatusMapWithoutRedaction()',
    )
    for token in required:
        if token not in test:
            raise SystemExit(f"status secret-custody regression does not pin: {token}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
