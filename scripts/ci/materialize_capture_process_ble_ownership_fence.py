from __future__ import annotations

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaProcessLifetimeBLEOwnershipFenceSourceTests.swift"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one source match, found {count}")
    return text.replace(old, new, 1)


def apply() -> None:
    text = APP.read_text(encoding="utf-8")

    text = replace_once(
        text,
        "    var failedAttemptCanRestartFromOFF1: Bool {\n"
        "        phase == .failed && currentConnectionToken == nil && localBLESettlementToken == nil && driver == nil\n"
        "    }\n",
        "    var failedAttemptCanRestartFromOFF1: Bool {\n"
        "        phase == .failed\n"
        "            && currentConnectionToken == nil\n"
        "            && localBLESettlementToken == nil\n"
        "            && driver == nil\n"
        "            && OfficialTuyaFactory.packageCorrelationMayStart\n"
        "    }\n",
        "restart authority",
    )

    text = replace_once(
        text,
        "        guard !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) else {\n",
        "        guard OfficialTuyaFactory.packageCorrelationMayStart else {\n"
        "            failLocally(\n"
        "                \"Tuya BLE ownership was already attempted in this app process. Relaunch Capture with the scooter OFF before a fresh OFF1→ON1→OFF2→ON2 series. Package-owned correlation cannot restart in-process after Tuya BLE ownership.\",\n"
        "                \"process_tuya_ble_ownership_blocks_scan\"\n"
        "            )\n"
        "            return\n"
        "        }\n"
        "        guard !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) else {\n",
        "correlation process fence",
    )

    text = replace_once(
        text,
        "private enum OfficialTuyaFactory {\n"
        "    private static var didBootstrap = false\n",
        "private enum OfficialTuyaFactory {\n"
        "    private static var didBootstrap = false\n"
        "    private static var packageCorrelationRetiredForProcess = false\n\n"
        "    static var packageCorrelationMayStart: Bool {\n"
        "        !packageCorrelationRetiredForProcess\n"
        "    }\n",
        "factory process fence state",
    )

    text = replace_once(
        text,
        "    static func make() -> OfficialTuyaDriver? {\n"
        "#if canImport(ThingSmartHomeKit) && canImport(NembraTuyaPrivateConfig)\n"
        "        guard bootstrap(), accountLoggedIn, currentAccountUID != nil else { return nil }\n"
        "        return SmartLifeDriver()\n",
        "    static func make() -> OfficialTuyaDriver? {\n"
        "#if canImport(ThingSmartHomeKit) && canImport(NembraTuyaPrivateConfig)\n"
        "        guard bootstrap(), accountLoggedIn, currentAccountUID != nil else { return nil }\n"
        "        // A process-global Tuya BLE manager may outlive any one controller. Once a\n"
        "        // supported Tuya driver is handed out, package-owned correlation stays retired\n"
        "        // until app relaunch; later failures must not recreate competing BLE ownership.\n"
        "        packageCorrelationRetiredForProcess = true\n"
        "        return SmartLifeDriver()\n",
        "driver handoff retirement",
    )

    APP.write_text(text, encoding="utf-8")

    TEST.write_text(
        '''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture process-lifetime BLE ownership fence")
struct TuyaProcessLifetimeBLEOwnershipFenceSourceTests {
    @Test("official Tuya driver handoff permanently retires package correlation until relaunch")
    func officialDriverHandoffRetiresPackageCorrelation() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let factory = try section(in: source, from: "private enum OfficialTuyaFactory", to: "#if canImport(ThingSmartHomeKit)\n@MainActor\nprivate final class OfficialTuyaMembershipProbe")
        let body = String(factory)

        #expect(body.contains("private static var packageCorrelationRetiredForProcess = false"))
        #expect(body.contains("static var packageCorrelationMayStart: Bool"))
        #expect(body.contains("!packageCorrelationRetiredForProcess"))
        #expect(body.contains("packageCorrelationRetiredForProcess = true"))
        #expect(body.components(separatedBy: "packageCorrelationRetiredForProcess = false").count - 1 == 1)
        #expect(body.components(separatedBy: "packageCorrelationRetiredForProcess = true").count - 1 == 1)

        let make = try section(in: body, from: "static func make() -> OfficialTuyaDriver?", to: "}\n}\n\n#if canImport(ThingSmartHomeKit)")
        let retirement = make.range(of: "packageCorrelationRetiredForProcess = true")
        let returnDriver = make.range(of: "return SmartLifeDriver()")
        #expect(retirement != nil)
        #expect(returnDriver != nil)
        if let retirement, let returnDriver { #expect(retirement.lowerBound < returnDriver.lowerBound) }
    }

    @Test("OFF1 admission and in-process retry both consume the process fence")
    func correlationAndRetryConsumeProcessFence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let retry = try section(in: source, from: "var failedAttemptCanRestartFromOFF1: Bool", to: "var canRestartFromFreshOFF1")
        #expect(retry.contains("OfficialTuyaFactory.packageCorrelationMayStart"))

        let correlation = try section(in: source, from: "private func beginCorrelationSeries()", to: "func confirmCorrelatedTarget")
        let processFence = correlation.range(of: "guard OfficialTuyaFactory.packageCorrelationMayStart else")
        let liveStatus = correlation.range(of: "guard !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) else")
        let reset = correlation.range(of: "resetDiscoverySessionOnly()")
        #expect(processFence != nil)
        #expect(liveStatus != nil)
        #expect(reset != nil)
        if let processFence, let liveStatus, let reset {
            #expect(processFence.lowerBound < liveStatus.lowerBound)
            #expect(liveStatus.lowerBound < reset.lowerBound)
        }
        #expect(correlation.contains("process_tuya_ble_ownership_blocks_scan"))
        #expect(correlation.contains("Relaunch Capture"))
    }

    @Test("process fence cannot be cleared by controller recovery")
    func processFenceHasNoRuntimeClearPath() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(source.components(separatedBy: "packageCorrelationRetiredForProcess = false").count - 1 == 1)
        #expect(source.components(separatedBy: "packageCorrelationRetiredForProcess = true").count - 1 == 1)
        #expect(!source.contains("packageCorrelationRetiredForProcess.toggle()"))
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

    private enum SourceContractError: Error { case sectionMissing }
}
''',
        encoding="utf-8",
    )


def verify() -> None:
    source = APP.read_text(encoding="utf-8")
    required = [
        "private static var packageCorrelationRetiredForProcess = false",
        "static var packageCorrelationMayStart: Bool",
        "packageCorrelationRetiredForProcess = true",
        "guard OfficialTuyaFactory.packageCorrelationMayStart else",
        "process_tuya_ble_ownership_blocks_scan",
        "&& OfficialTuyaFactory.packageCorrelationMayStart",
    ]
    missing = [needle for needle in required if needle not in source]
    if missing:
        raise SystemExit(f"missing process BLE ownership contracts: {missing}")
    if source.count("packageCorrelationRetiredForProcess = false") != 1:
        raise SystemExit("process fence must have exactly one initialization")
    if source.count("packageCorrelationRetiredForProcess = true") != 1:
        raise SystemExit("process fence must have exactly one retirement mutation")
    if not TEST.is_file():
        raise SystemExit("process BLE ownership source regression is missing")
    print("Capture process-lifetime BLE ownership fence source contract: PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    if args.mode == "apply":
        apply()
    verify()


if __name__ == "__main__":
    main()
