from pathlib import Path
import subprocess

EXPECTED_PARENT = "e60494fd32a8b307cb825e5e47b0e393ff3509dd"
APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaProcessBLEMutualExclusionCurrentProductSourceTests.swift")

merge_base = subprocess.check_output(["git", "merge-base", "HEAD", EXPECTED_PARENT], text=True).strip()
if merge_base != EXPECTED_PARENT:
    raise SystemExit(f"Refusing stale materialization: expected merge-base {EXPECTED_PARENT}, got {merge_base}")
parent_blob = subprocess.check_output(["git", "rev-parse", f"{EXPECTED_PARENT}:{APP}"], text=True).strip()
head_blob = subprocess.check_output(["git", "rev-parse", f"HEAD:{APP}"], text=True).strip()
if parent_blob != head_blob:
    raise SystemExit("Current-product Entrypoint drifted before materialization")
if TEST.exists():
    raise SystemExit(f"Refusing to overwrite existing regression: {TEST}")

source = APP.read_text(encoding="utf-8")

def replace_once(old: str, new: str, label: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one anchor, found {count}")
    source = source.replace(old, new, 1)

replace_once(
    "    private let buildIdentity = NembraCaptureBuildIdentity.current\n    private var byID: [UUID: Candidate] = [:]\n",
    "    private let buildIdentity = NembraCaptureBuildIdentity.current\n"
    "    private let controllerOwnershipID = UUID()\n"
    "    private var byID: [UUID: Candidate] = [:]\n",
    "controller ownership identity"
)

replace_once(
    "            && driver == nil\n            && OfficialTuyaFactory.packageCorrelationMayStart\n",
    "            && driver == nil\n"
    "            && OfficialTuyaFactory.packageCorrelationMayStart\n"
    "            && OfficialTuyaFactory.packageCorrelationOwnerIsClear\n",
    "restart availability ownership fence"
)

replace_once(
    "    func consumeCorrelationAsyncInvalidation() {\n"
    "        guard phase == .baseline || phase == .scanning else { return }\n"
    "        if OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) {\n",
    "    func consumeCorrelationAsyncInvalidation() {\n"
    "        guard phase == .baseline || phase == .scanning else { return }\n"
    "        guard OfficialTuyaFactory.ownsPackageCorrelation(ownerID: controllerOwnershipID) else {\n"
    "            correlationSession?.abandonCurrentWindow()\n"
    "            correlationSession = nil\n"
    "            failLocally(\n"
    "                \"Process-wide package Bluetooth ownership was lost while target correlation was active. This series is invalid; relaunch Capture before another OFF1 attempt.\",\n"
    "                \"package_correlation_process_ownership_lost\"\n"
    "            )\n"
    "            return\n"
    "        }\n"
    "        if OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) {\n",
    "async owner-loss fence"
)

replace_once(
    "        resetDiscoverySessionOnly()\n"
    "        do {\n"
    "            correlationSession = try PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)\n",
    "        resetDiscoverySessionOnly()\n"
    "        guard OfficialTuyaFactory.claimPackageCorrelation(ownerID: controllerOwnershipID) else {\n"
    "            failLocally(\n"
    "                \"Another Capture controller currently owns package Bluetooth correlation. This controller will not create a competing scanner; relaunch Capture before a fresh OFF1 series.\",\n"
    "                \"package_correlation_process_claim_rejected\"\n"
    "            )\n"
    "            return\n"
    "        }\n"
    "        do {\n"
    "            correlationSession = try PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)\n",
    "claim before scanner construction"
)

start_marker = "    private func startCurrentCorrelationWindow() {\n"
start_idx = source.index(start_marker)
start_end = source.index("    func finishCorrelationWindow()", start_idx)
start_section = source[start_idx:start_end]
start_anchor = (
    "        guard !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) else {\n"
)
start_owner = (
    "        guard OfficialTuyaFactory.ownsPackageCorrelation(ownerID: controllerOwnershipID) else {\n"
    "            correlationSession?.abandonCurrentWindow()\n"
    "            correlationSession = nil\n"
    "            failLocally(\n"
    "                \"Process-wide package Bluetooth ownership was lost before this correlation window could start. Relaunch Capture before another OFF1 series.\",\n"
    "                \"package_correlation_process_ownership_lost\"\n"
    "            )\n"
    "            return\n"
    "        }\n"
)
if start_section.count(start_anchor) != 1:
    raise SystemExit("window-start local BLE guard drifted")
start_section = start_section.replace(start_anchor, start_owner + start_anchor, 1)
source = source[:start_idx] + start_section + source[start_end:]

finish_marker = "    func finishCorrelationWindow() {\n"
finish_idx = source.index(finish_marker)
finish_end = source.index("    private func finishCorrelationSeries", finish_idx)
finish_section = source[finish_idx:finish_end]
finish_anchor = (
    "        guard !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) else {\n"
)
finish_owner = (
    "        guard OfficialTuyaFactory.ownsPackageCorrelation(ownerID: controllerOwnershipID) else {\n"
    "            session.abandonCurrentWindow()\n"
    "            correlationSession = nil\n"
    "            failLocally(\n"
    "                \"Process-wide package Bluetooth ownership changed before this correlation window could be sealed. The window is invalid; relaunch Capture before another OFF1 series.\",\n"
    "                \"package_correlation_process_ownership_lost\"\n"
    "            )\n"
    "            return\n"
    "        }\n"
)
if finish_section.count(finish_anchor) != 1:
    raise SystemExit("window-finish local BLE guard drifted")
finish_section = finish_section.replace(finish_anchor, finish_owner + finish_anchor, 1)
source = source[:finish_idx] + finish_section + source[finish_end:]

replace_once(
    "        targetCorrelationWindowCount = result.windows.count\n"
    "        targetCorrelationOperatorConfirmed = false\n"
    "        switch result.correlation.disposition {\n",
    "        targetCorrelationWindowCount = result.windows.count\n"
    "        targetCorrelationOperatorConfirmed = false\n"
    "        OfficialTuyaFactory.releasePackageCorrelation(ownerID: controllerOwnershipID)\n"
    "        switch result.correlation.disposition {\n",
    "release before correlation handoff"
)

replace_once(
    "    func invalidateSDKMembership() {\n"
    "        let token = currentConnectionToken\n",
    "    func invalidateSDKMembership() {\n"
    "        let token = currentConnectionToken\n"
    "        OfficialTuyaFactory.releasePackageCorrelation(ownerID: controllerOwnershipID)\n",
    "membership invalidation release"
)

replace_once(
    "        guard let newDriver = OfficialTuyaFactory.make() else {\n"
    "            failLocally(\"Official Tuya provider is unavailable.\", \"sdk_provider_unavailable\")\n"
    "            return\n"
    "        }\n",
    "        guard OfficialTuyaFactory.packageCorrelationOwnerIsClear else {\n"
    "            failLocally(\n"
    "                \"Package-owned Bluetooth correlation is active elsewhere in this app process. Tuya BLE ownership will not start while a package scanner is authoritative. Relaunch Capture and run one path at a time.\",\n"
    "                \"package_correlation_blocks_tuya_ble_ownership\"\n"
    "            )\n"
    "            return\n"
    "        }\n"
    "        guard let newDriver = OfficialTuyaFactory.make() else {\n"
    "            failLocally(\"Official Tuya provider is unavailable.\", \"sdk_provider_unavailable\")\n"
    "            return\n"
    "        }\n",
    "controller driver handoff fence"
)

replace_once(
    "    private func resetDiscoverySessionOnly() {\n"
    "        acceptanceCutIsClosed = false\n",
    "    private func resetDiscoverySessionOnly() {\n"
    "        OfficialTuyaFactory.releasePackageCorrelation(ownerID: controllerOwnershipID)\n"
    "        acceptanceCutIsClosed = false\n",
    "reset release"
)

replace_once(
    "    private func failLocally(_ text: String, _ kind: String) {\n"
    "        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {\n",
    "    private func failLocally(_ text: String, _ kind: String) {\n"
    "        OfficialTuyaFactory.releasePackageCorrelation(ownerID: controllerOwnershipID)\n"
    "        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {\n",
    "failure release"
)

replace_once(
    "private enum OfficialTuyaFactory {\n"
    "    private static var didBootstrap = false\n"
    "    private static var packageCorrelationRetiredForProcess = false\n\n"
    "    static var packageCorrelationMayStart: Bool {\n"
    "        !packageCorrelationRetiredForProcess\n"
    "    }\n",
    "private enum OfficialTuyaFactory {\n"
    "    private static var didBootstrap = false\n"
    "    private static var packageCorrelationRetiredForProcess = false\n"
    "    private static var packageCorrelationOwnerID: UUID?\n\n"
    "    static var packageCorrelationMayStart: Bool {\n"
    "        !packageCorrelationRetiredForProcess\n"
    "    }\n\n"
    "    static var packageCorrelationOwnerIsClear: Bool {\n"
    "        packageCorrelationOwnerID == nil\n"
    "    }\n\n"
    "    static func claimPackageCorrelation(ownerID: UUID) -> Bool {\n"
    "        guard packageCorrelationMayStart else { return false }\n"
    "        guard packageCorrelationOwnerID == nil || packageCorrelationOwnerID == ownerID else { return false }\n"
    "        packageCorrelationOwnerID = ownerID\n"
    "        return true\n"
    "    }\n\n"
    "    static func ownsPackageCorrelation(ownerID: UUID) -> Bool {\n"
    "        packageCorrelationOwnerID == ownerID\n"
    "    }\n\n"
    "    static func releasePackageCorrelation(ownerID: UUID) {\n"
    "        guard packageCorrelationOwnerID == ownerID else { return }\n"
    "        packageCorrelationOwnerID = nil\n"
    "    }\n",
    "factory owner state"
)

replace_once(
    "    static func make() -> OfficialTuyaDriver? {\n"
    "#if canImport(ThingSmartHomeKit) && canImport(NembraTuyaPrivateConfig)\n"
    "        guard bootstrap(), accountLoggedIn, currentAccountUID != nil else { return nil }\n",
    "    static func make() -> OfficialTuyaDriver? {\n"
    "#if canImport(ThingSmartHomeKit) && canImport(NembraTuyaPrivateConfig)\n"
    "        guard packageCorrelationOwnerIsClear else { return nil }\n"
    "        guard bootstrap(), accountLoggedIn, currentAccountUID != nil else { return nil }\n",
    "factory driver handoff fence"
)

# Preserve current exact-product contracts that must not be regressed by this reanchor.
required_source = (
    "sdk_local_ble_reacquired_during_target_correlation",
    "sdk_local_ble_ownership_blocks_correlation_window",
    "sdk_local_ble_ownership_invalidates_correlation_window",
    "packageCorrelationRetiredForProcess = true",
    "let appleNickname = credential.fullName?.nickname",
    "procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier",
    "sealedAcceptedEventPrefix",
    "self.sealedAcceptedExport = self.makeExport(",
)
for needle in required_source:
    if needle not in source:
        raise SystemExit(f"Required current-product contract missing after patch: {needle}")

controller = source[source.index("private final class SecureLinkController"):source.index("private protocol OfficialTuyaDriver")]
for forbidden in ("disconnectBLE", "publishDps(", "queryDps(", "writeValue("):
    if forbidden in controller:
        raise SystemExit(f"Mutual-exclusion repair unexpectedly introduced transport mutation: {forbidden}")

APP.write_text(source, encoding="utf-8")

TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture current-product process BLE mutual exclusion")
struct TuyaProcessBLEMutualExclusionCurrentProductSourceTests {
    @Test("package correlation claims one process owner before constructing its scanner")
    func packageCorrelationClaimsBeforeScannerConstruction() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let begin = try section(in: app, from: "private func beginCorrelationSeries()", to: "func startNextCorrelationWindow()")
        let body = String(begin)
        let reset = try requiredRange("resetDiscoverySessionOnly()", in: body)
        let claim = try requiredRange("OfficialTuyaFactory.claimPackageCorrelation(ownerID: controllerOwnershipID)", in: body)
        let session = try requiredRange("PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)", in: body)
        #expect(reset.lowerBound < claim.lowerBound)
        #expect(claim.lowerBound < session.lowerBound)
        #expect(body[claim.upperBound..<session.lowerBound].contains("return"))
    }

    @Test("every active window retains process ownership and same-device local BLE contamination fences")
    func activeWindowsRetainOwner() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let async = try section(in: app, from: "func consumeCorrelationAsyncInvalidation()", to: "var correlationWindowLabel")
        let start = try section(in: app, from: "private func startCurrentCorrelationWindow()", to: "func finishCorrelationWindow()")
        let finish = try section(in: app, from: "func finishCorrelationWindow()", to: "private func finishCorrelationSeries")

        #expect(async.contains("OfficialTuyaFactory.ownsPackageCorrelation(ownerID: controllerOwnershipID)"))
        #expect(async.contains("OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)"))

        let startOwner = try requiredRange("OfficialTuyaFactory.ownsPackageCorrelation(ownerID: controllerOwnershipID)", in: String(start))
        let startLocal = try requiredRange("OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)", in: String(start))
        let scannerStart = try requiredRange("session.startCurrentWindow()", in: String(start))
        #expect(startOwner.lowerBound < scannerStart.lowerBound)
        #expect(startLocal.lowerBound < scannerStart.lowerBound)

        let finishOwner = try requiredRange("OfficialTuyaFactory.ownsPackageCorrelation(ownerID: controllerOwnershipID)", in: String(finish))
        let finishLocal = try requiredRange("OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID)", in: String(finish))
        let scannerSeal = try requiredRange("session.finishCurrentWindow()", in: String(finish))
        #expect(finishOwner.lowerBound < scannerSeal.lowerBound)
        #expect(finishLocal.lowerBound < scannerSeal.lowerBound)
    }

    @Test("correlation owner is released before correlated handoff and on local reset/failure")
    func ownerReleaseIsBoundedToOwningController() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let final = try section(in: app, from: "private func finishCorrelationSeries", to: "func confirmCorrelatedTarget")
        let reset = try section(in: app, from: "private func resetDiscoverySessionOnly()", to: "private func failLocally")
        let failure = try section(in: app, from: "private func failLocally", to: "private func log")
        let finalBody = String(final)
        let release = try requiredRange("OfficialTuyaFactory.releasePackageCorrelation(ownerID: controllerOwnershipID)", in: finalBody)
        let disposition = try requiredRange("switch result.correlation.disposition", in: finalBody)
        #expect(release.lowerBound < disposition.lowerBound)
        #expect(reset.contains("OfficialTuyaFactory.releasePackageCorrelation(ownerID: controllerOwnershipID)"))
        #expect(failure.contains("OfficialTuyaFactory.releasePackageCorrelation(ownerID: controllerOwnershipID)"))
    }

    @Test("Tuya driver handoff cannot race an active package correlation owner")
    func factoryAndControllerBothFenceDriverHandoff() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = try section(in: app, from: "private func beginOfficialConnection(candidate:", to: "private func authenticated(token:")
        let factory = try section(in: app, from: "private enum OfficialTuyaFactory", to: "#if canImport(ThingSmartHomeKit)\n@MainActor\nprivate final class OfficialTuyaMembershipProbe")
        let controllerBody = String(controller)
        let factoryBody = String(factory)

        let controllerFence = try requiredRange("OfficialTuyaFactory.packageCorrelationOwnerIsClear", in: controllerBody)
        let controllerMake = try requiredRange("OfficialTuyaFactory.make()", in: controllerBody)
        #expect(controllerFence.lowerBound < controllerMake.lowerBound)

        #expect(factoryBody.contains("private static var packageCorrelationOwnerID: UUID?"))
        #expect(factoryBody.contains("static func claimPackageCorrelation(ownerID: UUID) -> Bool"))
        #expect(factoryBody.contains("static func ownsPackageCorrelation(ownerID: UUID) -> Bool"))
        #expect(factoryBody.contains("static func releasePackageCorrelation(ownerID: UUID)"))
        let factoryFence = try requiredRange("guard packageCorrelationOwnerIsClear else { return nil }", in: factoryBody)
        let retirement = try requiredRange("packageCorrelationRetiredForProcess = true", in: factoryBody)
        let driver = try requiredRange("return SmartLifeDriver()", in: factoryBody)
        #expect(factoryFence.lowerBound < retirement.lowerBound)
        #expect(retirement.lowerBound < driver.lowerBound)
    }

    @Test("mutual exclusion remains observation and ownership only")
    func repairCannotMutateScooterTransport() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let begin = try section(in: app, from: "private func beginCorrelationSeries()", to: "func startNextCorrelationWindow()")
        let start = try section(in: app, from: "private func startCurrentCorrelationWindow()", to: "func finishCorrelationWindow()")
        let finish = try section(in: app, from: "func finishCorrelationWindow()", to: "private func finishCorrelationSeries")
        let combined = String(begin) + String(start) + String(finish)
        for forbidden in ["disconnectBLE", "publishDps", "queryDps", "writeValue", "sessionLedger.endConnection"] {
            #expect(!combined.contains(forbidden))
        }
        #expect(app.contains("@MainActor\nprivate enum OfficialTuyaFactory"))
    }

    private func requiredRange(_ needle: String, in source: String) throws -> Range<String.Index> {
        guard let range = source.range(of: needle) else {
            Issue.record("Expected source contract missing: \(needle)")
            throw SourceContractError.sectionMissing
        }
        return range
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
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
''', encoding="utf-8")

print("Materialized current-product process BLE mutual exclusion repair")
