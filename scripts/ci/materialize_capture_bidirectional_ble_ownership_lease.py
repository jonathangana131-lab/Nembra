from __future__ import annotations

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaBidirectionalBLEOwnershipLeaseSourceTests.swift"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one source match, found {count}")
    return text.replace(old, new, 1)


def apply() -> None:
    text = APP.read_text(encoding="utf-8")

    text = replace_once(
        text,
        "    private var membershipRequestID = UUID()\n",
        "    private var membershipRequestID = UUID()\n"
        "    private var packageCorrelationOwnershipLeaseID: UUID?\n",
        "controller lease storage",
    )

    text = replace_once(
        text,
        "            && driver == nil\n"
        "            && OfficialTuyaFactory.packageCorrelationMayStart\n",
        "            && driver == nil\n"
        "            && OfficialTuyaFactory.packageCorrelationMayStart\n"
        "            && !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)\n",
        "restart live ownership gate",
    )

    text = replace_once(
        text,
        "\n        resetDiscoverySessionOnly()\n"
        "        do {\n"
        "            correlationSession = try PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)\n",
        "\n        guard let ownershipLeaseID = OfficialTuyaFactory.claimPackageCorrelationOwnership() else {\n"
        "            failLocally(\n"
        "                \"Another Bluetooth owner became active before OFF1 could claim process ownership. Relaunch Capture with the scooter OFF before a fresh OFF1→ON1→OFF2→ON2 series.\",\n"
        "                \"package_correlation_process_lease_unavailable\"\n"
        "            )\n"
        "            return\n"
        "        }\n"
        "        packageCorrelationOwnershipLeaseID = ownershipLeaseID\n\n"
        "        resetDiscoverySessionOnly()\n"
        "        do {\n"
        "            correlationSession = try PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)\n",
        "claim process lease before scanner creation",
    )

    text = replace_once(
        text,
        "        guard !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) else {\n"
        "            correlationSession?.abandonCurrentWindow()\n"
        "            correlationSession = nil\n"
        "            failLocally(\n"
        "                \"Tuya local-BLE ownership is active before this correlation window. The package scanner will not start; power the scooter OFF, let Tuya local BLE clear, and restart from OFF1.\",\n"
        "                \"sdk_local_ble_ownership_blocks_correlation_window\"\n"
        "            )\n"
        "            return\n"
        "        }\n"
        "        guard let session = correlationSession,\n",
        "        guard let ownershipLeaseID = packageCorrelationOwnershipLeaseID,\n"
        "              OfficialTuyaFactory.packageCorrelationOwnershipIsCurrent(ownershipLeaseID) else {\n"
        "            correlationSession?.abandonCurrentWindow()\n"
        "            correlationSession = nil\n"
        "            failLocally(\n"
        "                \"Package Bluetooth process ownership was lost before this correlation window. The scanner will not start; relaunch Capture and restart from OFF1.\",\n"
        "                \"package_correlation_process_lease_lost\"\n"
        "            )\n"
        "            return\n"
        "        }\n"
        "        guard !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) else {\n"
        "            correlationSession?.abandonCurrentWindow()\n"
        "            correlationSession = nil\n"
        "            failLocally(\n"
        "                \"Tuya local-BLE ownership is active before this correlation window. The package scanner will not start; power the scooter OFF, let Tuya local BLE clear, and restart from OFF1.\",\n"
        "                \"sdk_local_ble_ownership_blocks_correlation_window\"\n"
        "            )\n"
        "            return\n"
        "        }\n"
        "        guard let session = correlationSession,\n",
        "validate process lease at every window",
    )

    text = replace_once(
        text,
        "    private func finishCorrelationSeries(_ result: PassiveBluetoothPowerCycleObservationResult) {\n"
        "        // Preserve the package-issued receipts + exact catalogs before releasing the live scanner.\n",
        "    private func finishCorrelationSeries(_ result: PassiveBluetoothPowerCycleObservationResult) {\n"
        "        releasePackageCorrelationOwnership()\n"
        "        // Preserve the package-issued receipts + exact catalogs before releasing the live scanner.\n",
        "release process lease on successful series finish",
    )

    text = replace_once(
        text,
        "    private func failLocally(_ text: String, _ kind: String) {\n"
        "        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {\n",
        "    private func releasePackageCorrelationOwnership() {\n"
        "        guard let ownershipLeaseID = packageCorrelationOwnershipLeaseID else { return }\n"
        "        OfficialTuyaFactory.releasePackageCorrelationOwnership(ownershipLeaseID)\n"
        "        packageCorrelationOwnershipLeaseID = nil\n"
        "    }\n\n"
        "    private func failLocally(_ text: String, _ kind: String) {\n"
        "        releasePackageCorrelationOwnership()\n"
        "        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {\n",
        "central failure lease release",
    )

    text = replace_once(
        text,
        "    private static var didBootstrap = false\n"
        "    private static var packageCorrelationRetiredForProcess = false\n\n"
        "    static var packageCorrelationMayStart: Bool {\n"
        "        !packageCorrelationRetiredForProcess\n"
        "    }\n",
        "    private static var didBootstrap = false\n"
        "    private static var packageCorrelationRetiredForProcess = false\n"
        "    private static var packageCorrelationOwnershipLeaseID: UUID?\n\n"
        "    static var packageCorrelationMayStart: Bool {\n"
        "        !packageCorrelationRetiredForProcess && packageCorrelationOwnershipLeaseID == nil\n"
        "    }\n\n"
        "    static func claimPackageCorrelationOwnership() -> UUID? {\n"
        "        guard packageCorrelationMayStart else { return nil }\n"
        "        let ownershipLeaseID = UUID()\n"
        "        packageCorrelationOwnershipLeaseID = ownershipLeaseID\n"
        "        return ownershipLeaseID\n"
        "    }\n\n"
        "    static func packageCorrelationOwnershipIsCurrent(_ ownershipLeaseID: UUID) -> Bool {\n"
        "        packageCorrelationOwnershipLeaseID == ownershipLeaseID\n"
        "            && !packageCorrelationRetiredForProcess\n"
        "    }\n\n"
        "    static func releasePackageCorrelationOwnership(_ ownershipLeaseID: UUID) {\n"
        "        guard packageCorrelationOwnershipLeaseID == ownershipLeaseID else { return }\n"
        "        packageCorrelationOwnershipLeaseID = nil\n"
        "    }\n",
        "factory bidirectional lease state",
    )

    text = replace_once(
        text,
        "        guard bootstrap(), accountLoggedIn, currentAccountUID != nil else { return nil }\n"
        "        // A process-global Tuya BLE manager may outlive any one controller. Once a\n",
        "        guard bootstrap(),\n"
        "              accountLoggedIn,\n"
        "              currentAccountUID != nil,\n"
        "              packageCorrelationOwnershipLeaseID == nil else { return nil }\n"
        "        // A process-global Tuya BLE manager may outlive any one controller. Once a\n",
        "block Tuya driver handoff while package owns BLE",
    )

    APP.write_text(text, encoding="utf-8")

    TEST.write_text(
        '''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture bidirectional process BLE ownership lease")
struct TuyaBidirectionalBLEOwnershipLeaseSourceTests {
    @Test("package correlation holds one process lease and Tuya driver handoff is excluded")
    func processLeaseIsBidirectional() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let factory = try section(in: source, from: "private enum OfficialTuyaFactory", to: "private final class OfficialTuyaMembershipProbe")
        let body = String(factory)

        #expect(body.contains("private static var packageCorrelationOwnershipLeaseID: UUID?"))
        #expect(body.contains("static func claimPackageCorrelationOwnership() -> UUID?"))
        #expect(body.contains("static func packageCorrelationOwnershipIsCurrent(_ ownershipLeaseID: UUID) -> Bool"))
        #expect(body.contains("static func releasePackageCorrelationOwnership(_ ownershipLeaseID: UUID)"))
        #expect(body.contains("!packageCorrelationRetiredForProcess && packageCorrelationOwnershipLeaseID == nil"))

        guard let makeStart = body.range(of: "static func make() -> OfficialTuyaDriver?") else {
            Issue.record("Official Tuya make() missing")
            throw SourceContractError.sectionMissing
        }
        let makeTail = body[makeStart.lowerBound...]
        let packageExclusion = makeTail.range(of: "packageCorrelationOwnershipLeaseID == nil")
        let retirement = makeTail.range(of: "packageCorrelationRetiredForProcess = true")
        let driverReturn = makeTail.range(of: "return SmartLifeDriver()")
        #expect(packageExclusion != nil)
        #expect(retirement != nil)
        #expect(driverReturn != nil)
        if let packageExclusion, let retirement, let driverReturn {
            #expect(packageExclusion.lowerBound < retirement.lowerBound)
            #expect(retirement.lowerBound < driverReturn.lowerBound)
        }
    }

    @Test("the complete four-window package series owns the lease until success or failure")
    func controllerOwnsLeaseAcrossSeries() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(source.contains("private var packageCorrelationOwnershipLeaseID: UUID?"))

        let begin = try section(in: source, from: "private func beginCorrelationSeries()", to: "func startNextCorrelationWindow()")
        let claim = begin.range(of: "OfficialTuyaFactory.claimPackageCorrelationOwnership()")
        let store = begin.range(of: "packageCorrelationOwnershipLeaseID = ownershipLeaseID")
        let reset = begin.range(of: "resetDiscoverySessionOnly()")
        #expect(claim != nil)
        #expect(store != nil)
        #expect(reset != nil)
        if let claim, let store, let reset {
            #expect(claim.lowerBound < store.lowerBound)
            #expect(store.lowerBound < reset.lowerBound)
        }

        let window = try section(in: source, from: "private func startCurrentCorrelationWindow()", to: "func finishCorrelationWindow()")
        let leaseCheck = window.range(of: "OfficialTuyaFactory.packageCorrelationOwnershipIsCurrent(ownershipLeaseID)")
        let liveCheck = window.range(of: "OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)")
        let scannerStart = window.range(of: "session.startCurrentWindow()")
        #expect(leaseCheck != nil)
        #expect(liveCheck != nil)
        #expect(scannerStart != nil)
        if let leaseCheck, let liveCheck, let scannerStart {
            #expect(leaseCheck.lowerBound < liveCheck.lowerBound)
            #expect(liveCheck.lowerBound < scannerStart.lowerBound)
        }

        let finish = try section(in: source, from: "private func finishCorrelationSeries", to: "func confirmCorrelatedTarget")
        #expect(finish.contains("releasePackageCorrelationOwnership()"))
        let failure = try section(in: source, from: "private func failLocally", to: "private func log")
        #expect(failure.contains("releasePackageCorrelationOwnership()"))
    }

    @Test("controller abandonment cannot silently reopen process ownership")
    func abandonmentFailsClosed() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(source.contains("deinit { watchdog?.cancel() }"))
        #expect(!source.contains("deinit { releasePackageCorrelationOwnership()"))
        #expect(source.components(separatedBy: "packageCorrelationRetiredForProcess = false").count - 1 == 1)
        #expect(source.components(separatedBy: "packageCorrelationRetiredForProcess = true").count - 1 == 1)
        #expect(source.contains("&& !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)"))
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

    private enum SourceContractError: Error { case sectionMissing }
}
''',
        encoding="utf-8",
    )


def verify() -> None:
    source = APP.read_text(encoding="utf-8")
    required = [
        "private var packageCorrelationOwnershipLeaseID: UUID?",
        "private static var packageCorrelationOwnershipLeaseID: UUID?",
        "claimPackageCorrelationOwnership() -> UUID?",
        "packageCorrelationOwnershipIsCurrent(_ ownershipLeaseID: UUID) -> Bool",
        "releasePackageCorrelationOwnership(_ ownershipLeaseID: UUID)",
        "packageCorrelationOwnershipLeaseID == nil else { return nil }",
        "packageCorrelationOwnershipLeaseID = ownershipLeaseID",
        "releasePackageCorrelationOwnership()",
    ]
    missing = [needle for needle in required if needle not in source]
    if missing:
        raise SystemExit(f"missing bidirectional BLE ownership contracts: {missing}")
    if source.count("packageCorrelationRetiredForProcess = false") != 1:
        raise SystemExit("process retirement fence must have one initialization")
    if source.count("packageCorrelationRetiredForProcess = true") != 1:
        raise SystemExit("process retirement fence must have one irreversible mutation")
    if not TEST.is_file():
        raise SystemExit("bidirectional BLE ownership source regression is missing")
    print("Capture bidirectional BLE ownership lease source contract: PASS")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    if args.mode == "apply":
        apply()
    verify()


if __name__ == "__main__":
    main()
