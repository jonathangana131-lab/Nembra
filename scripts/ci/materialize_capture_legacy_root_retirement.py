from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BRIDGE = ROOT / "NembraApp/Features/Research/TuyaAccountBridge.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureRootProductSurfaceSourceTests.swift"

LEGACY_MARKER = "\nstruct NembraCaptureRootView: View {"
TEST_INSERTION = "    private func section(in source: String, from start: String, to end: String) throws -> Substring {"

TEST_ADDITION = '''    @Test("legacy card-based Capture root is retired from the metadata bridge")
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


def apply() -> None:
    bridge = BRIDGE.read_text(encoding="utf-8")
    count = bridge.count(LEGACY_MARKER)
    if count != 1:
        raise SystemExit(f"legacy root marker: expected exactly one match, found {count}")
    kept, _ = bridge.split(LEGACY_MARKER, 1)
    BRIDGE.write_text(kept.rstrip() + "\n", encoding="utf-8")

    test = TEST.read_text(encoding="utf-8")
    if "func legacyCardRootIsRetired()" in test:
        raise SystemExit("retirement regression already exists")
    if test.count(TEST_INSERTION) != 1:
        raise SystemExit("Capture root source-test insertion point changed")
    TEST.write_text(test.replace(TEST_INSERTION, TEST_ADDITION + TEST_INSERTION, 1), encoding="utf-8")


def verify() -> None:
    bridge = BRIDGE.read_text(encoding="utf-8")
    required = (
        "final class TuyaAccountBridge: ObservableObject",
        "struct TuyaQRCodeExport: Transferable",
        "struct TuyaMetadataExport: Transferable",
    )
    forbidden = (
        "struct NembraCaptureRootView: View",
        "func captureCard() -> some View",
        "Link Tuya first",
        "Continue to Bluetooth Capture",
    )
    for token in required:
        if token not in bridge:
            raise SystemExit(f"required bridge/export surface missing: {token}")
    for token in forbidden:
        if token in bridge:
            raise SystemExit(f"legacy product token survived: {token}")

    test = TEST.read_text(encoding="utf-8")
    if test.count("func legacyCardRootIsRetired()") != 1:
        raise SystemExit("retirement regression missing or duplicated")
    for token in required + forbidden:
        if token not in test:
            raise SystemExit(f"retirement regression does not pin token: {token}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
