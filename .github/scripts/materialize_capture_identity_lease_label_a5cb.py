from pathlib import Path
import sys

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
GATE = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaSDKAccountIdentityLeaseGate.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAccountIdentityLeaseAppSourceIntegrationTests.swift")


def apply() -> None:
    source = APP.read_text(encoding="utf-8")
    old = "            sdkIsLoggedIn: sdkAccountLoggedIn,"
    new = "            isLoggedIn: sdkAccountLoggedIn,"
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one stale identity-lease label, found {count}")
    APP.write_text(source.replace(old, new, 1), encoding="utf-8")
    TEST.write_text('''import Foundation
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
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
''', encoding="utf-8")


def verify() -> None:
    app = APP.read_text(encoding="utf-8")
    gate = GATE.read_text(encoding="utf-8")
    if app.count("isLoggedIn: sdkAccountLoggedIn") != 1:
        raise SystemExit("corrected app identity-lease label missing or duplicated")
    if "sdkIsLoggedIn: sdkAccountLoggedIn" in app:
        raise SystemExit("stale app identity-lease label remains")
    if "public init(\n            isLoggedIn: Bool," not in gate:
        raise SystemExit("package public identity-lease initializer contract changed")
    if not TEST.exists():
        raise SystemExit("source integration regression missing")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "verify"
    if mode == "apply":
        apply()
    elif mode == "verify":
        verify()
    else:
        raise SystemExit(f"unknown mode: {mode}")
