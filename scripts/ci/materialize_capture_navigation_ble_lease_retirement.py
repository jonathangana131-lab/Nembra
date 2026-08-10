from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaNavigationBLELeaseRetirementSourceTests.swift"

DEINIT = "    deinit { watchdog?.cancel() }\n"
DEINIT_PLUS_EXIT = '''    deinit { watchdog?.cancel() }\n\n    func abandonCorrelationForViewExit() {\n        guard processCorrelationLease != nil || correlationSession != nil else { return }\n        abandonPackageCorrelation()\n        phase = .failed\n        message = "Bluetooth correlation was interrupted when Capture left Secure Link. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series."\n        log("target_correlation_abandoned_on_view_exit")\n    }\n'''
ONCHANGE = '''        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in\n'''
ONDISAPPEAR_PLUS_ONCHANGE = '''        .onDisappear {\n            test.abandonCorrelationForViewExit()\n        }\n        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in\n'''

TEST_CONTENT = r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture navigation BLE lease retirement source contract")
struct TuyaNavigationBLELeaseRetirementSourceTests {
    @Test("leaving Secure Link deterministically retires package correlation before controller loss")
    func secureLinkNavigationExitRetiresCorrelationLease() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let view = String(try section(
            in: source,
            from: "private struct SecureLinkView: View",
            to: "private extension SecureLinkView"
        ))

        #expect(controller.contains("func abandonCorrelationForViewExit()"))
        #expect(controller.contains("guard processCorrelationLease != nil || correlationSession != nil else { return }"))
        #expect(controller.contains("abandonPackageCorrelation()"))
        #expect(controller.contains("target_correlation_abandoned_on_view_exit"))
        #expect(view.contains(".onDisappear"))
        #expect(view.contains("test.abandonCorrelationForViewExit()"))
    }

    @Test("cleanup reuses transport-first package abandonment path")
    func packageTransportRetirementPrecedesLeaseRelease() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let abandon = String(try section(
            in: source,
            from: "private func abandonPackageCorrelation()",
            to: "private func releasePackageCorrelationLease()"
        ))
        let abandonLine = try requiredLine(containing: "correlationSession?.abandonCurrentWindow()", in: abandon)
        let releaseLine = try requiredLine(containing: "releasePackageCorrelationLease()", in: abandon)
        #expect(abandonLine < releaseLine)
    }

    private func requiredLine(containing token: String, in source: String) throws -> Int {
        guard let index = source.components(separatedBy: "\n").firstIndex(where: { $0.contains(token) }) else {
            Issue.record("Expected source token missing: \(token)")
            throw SourceContractError.sectionMissing
        }
        return index
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
    source = ENTRYPOINT.read_text(encoding="utf-8")
    if source.count(DEINIT) != 1:
        raise SystemExit(f"controller deinit anchor changed: {source.count(DEINIT)}")
    if source.count(ONCHANGE) != 1:
        raise SystemExit(f"SecureLink view lifecycle anchor changed: {source.count(ONCHANGE)}")
    if "func abandonCorrelationForViewExit()" in source or "test.abandonCorrelationForViewExit()" in source:
        raise SystemExit("navigation retirement is already partially present; re-inspect instead of double-applying")
    if TEST.exists():
        raise SystemExit("navigation retirement regression already exists; re-inspect current product")

    source = source.replace(DEINIT, DEINIT_PLUS_EXIT, 1)
    source = source.replace(ONCHANGE, ONDISAPPEAR_PLUS_ONCHANGE, 1)
    ENTRYPOINT.write_text(source, encoding="utf-8")
    TEST.write_text(TEST_CONTENT, encoding="utf-8")


def verify() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    required = (
        "func abandonCorrelationForViewExit()",
        "guard processCorrelationLease != nil || correlationSession != nil else { return }",
        "abandonPackageCorrelation()",
        "target_correlation_abandoned_on_view_exit",
        ".onDisappear {",
        "test.abandonCorrelationForViewExit()",
    )
    for token in required:
        if token not in source:
            raise SystemExit(f"navigation retirement source token missing: {token}")
    if not TEST.exists():
        raise SystemExit("navigation retirement regression is missing")

    abandon_start = source.index("private func abandonPackageCorrelation()")
    release_start = source.index("private func releasePackageCorrelationLease()", abandon_start)
    abandon_body = source[abandon_start:release_start]
    if abandon_body.index("correlationSession?.abandonCurrentWindow()") > abandon_body.index("releasePackageCorrelationLease()"):
        raise SystemExit("package correlation lease is released before transport abandonment")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
