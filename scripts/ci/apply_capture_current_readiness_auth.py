#!/usr/bin/env python3
from pathlib import Path

PATH = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
text = PATH.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one anchor, found {count}")
    text = text.replace(old, new, 1)


replace_once("@preconcurrency import CoreBluetooth\n", "", "remove app CoreBluetooth import")
replace_once(
    "let CBAdvertisementDataIsConnectableKey = CBAdvertisementDataIsConnectable\n\n",
    "",
    "remove app advertisement alias",
)
replace_once(
    "    static let fd50 = CBUUID(string: \"FD50\")\n",
    "",
    "remove legacy FD50 scanner constant",
)
replace_once(
    "    @Published private(set) var pendingCorrelatedTargetID: UUID?\n"
    "    @Published private(set) var sdkLocalBLEOnline = false\n",
    "    @Published private(set) var pendingCorrelatedTargetID: UUID?\n"
    "    @Published private(set) var correlationProgress: PassiveBluetoothPowerCycleObservationProgress?\n"
    "    @Published private(set) var sdkLocalBLEOnline = false\n",
    "publish correlation progress",
)
replace_once(
    "    private let buildIdentity = NembraCaptureBuildIdentity.current\n"
    "    private var central: CBCentralManager!\n"
    "    private var byID: [UUID: Candidate] = [:]\n"
    "    private var baseline = Set<UUID>()\n"
    "    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?\n",
    "    private let buildIdentity = NembraCaptureBuildIdentity.current\n"
    "    private var byID: [UUID: Candidate] = [:]\n"
    "    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?\n"
    "    private var correlationProgressTask: Task<Void, Never>?\n",
    "retire duplicate scanner ownership",
)
replace_once(
    "        super.init()\n"
    "        central = CBCentralManager(delegate: self, queue: .main)\n"
    "        log(\"controller_created\")\n",
    "        super.init()\n"
    "        log(\"controller_created\")\n",
    "remove legacy central initialization",
)
replace_once(
    "    deinit { watchdog?.cancel() }\n",
    "    deinit {\n"
    "        watchdog?.cancel()\n"
    "        correlationProgressTask?.cancel()\n"
    "    }\n",
    "retire progress task at deinit",
)
replace_once(
    "    var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }\n",
    "",
    "remove unobservable progress pull",
)
replace_once(
    "            try session.startCurrentWindow()\n"
    "            phase = progress.phase.operatorExpectedPowerOn ? .scanning : .baseline\n",
    "            try session.startCurrentWindow()\n"
    "            startCorrelationProgressObservation(session: session)\n"
    "            phase = progress.phase.operatorExpectedPowerOn ? .scanning : .baseline\n",
    "start progress presentation bridge",
)
replace_once(
    "    func finishCorrelationWindow() {\n",
    "    private func startCorrelationProgressObservation(session: PassiveBluetoothPowerCycleObservationSession) {\n"
    "        stopCorrelationProgressObservation()\n"
    "        correlationProgress = session.progress\n"
    "        correlationProgressTask = Task { @MainActor [weak self] in\n"
    "            while !Task.isCancelled {\n"
    "                guard let self, self.correlationSession === session else { return }\n"
    "                if let progress = session.progress {\n"
    "                    self.correlationProgress = progress\n"
    "                }\n"
    "                try? await Task.sleep(for: .milliseconds(100))\n"
    "            }\n"
    "        }\n"
    "    }\n\n"
    "    private func stopCorrelationProgressObservation() {\n"
    "        correlationProgressTask?.cancel()\n"
    "        correlationProgressTask = nil\n"
    "    }\n\n"
    "    func finishCorrelationWindow() {\n",
    "add progress observer helpers",
)
replace_once(
    "            let final = try session.finishCurrentWindow()\n"
    "            if let final {\n",
    "            let final = try session.finishCurrentWindow()\n"
    "            stopCorrelationProgressObservation()\n"
    "            correlationProgress = session.progress\n"
    "            if let final {\n",
    "publish sealed progress",
)
replace_once(
    "            default:\n"
    "                session.abandonCurrentWindow()\n"
    "                correlationSession = nil\n",
    "            default:\n"
    "                stopCorrelationProgressObservation()\n"
    "                session.abandonCurrentWindow()\n"
    "                correlationSession = nil\n"
    "                correlationProgress = nil\n",
    "retire progress observer on package window failure",
)
replace_once(
    "        } catch {\n"
    "            session.abandonCurrentWindow()\n"
    "            correlationSession = nil\n"
    "            failLocally(\"\\(sealedLabel) failed closed: \\(error.localizedDescription). Restart the complete correlation series.\", \"target_correlation_window_failed\")\n"
    "        }\n"
    "    }\n\n"
    "    private func finishCorrelationSeries",
    "        } catch {\n"
    "            stopCorrelationProgressObservation()\n"
    "            session.abandonCurrentWindow()\n"
    "            correlationSession = nil\n"
    "            correlationProgress = nil\n"
    "            failLocally(\"\\(sealedLabel) failed closed: \\(error.localizedDescription). Restart the complete correlation series.\", \"target_correlation_window_failed\")\n"
    "        }\n"
    "    }\n\n"
    "    private func finishCorrelationSeries",
    "retire progress observer on generic window failure",
)
replace_once(
    "        guard sdkAccountLoggedIn,\n"
    "              sdkDeviceMembershipVerified,\n"
    "              accountIdentityLeaseIsAuthorized else {\n"
    "            pendingCorrelatedTargetID = nil\n"
    "            failLocally(\"Tuya account/device authority changed before target confirmation. Re-verify membership and restart correlation.\", \"sdk_authority_changed_before_target_confirmation\")\n",
    "        guard fieldBuildIsAuthoritative,\n"
    "              sdkAccountLoggedIn,\n"
    "              sdkDeviceMembershipVerified,\n"
    "              accountIdentityLeaseIsAuthorized else {\n"
    "            pendingCorrelatedTargetID = nil\n"
    "            failLocally(\"Build or Tuya account/device authority changed before target confirmation. Re-verify authority and restart correlation from OFF1.\", \"source_authority_changed_before_target_confirmation\")\n",
    "keep confirmation on compiled + Tuya authority",
)
replace_once(
    "        membershipDeviceID = nil\n"
    "        pendingCorrelatedTargetID = nil\n",
    "        membershipDeviceID = nil\n"
    "        pendingCorrelatedTargetID = nil\n"
    "        targetCorrelationOperatorConfirmed = false\n",
    "retire operator confirmation on source invalidation",
)
replace_once("        central.stopScan()\n", "", "remove membership invalidation scanner stop")
replace_once(
    "            guard stillAuthorized,\n"
    "                  self.sdkAccountLoggedIn,\n"
    "                  self.accountIdentityLeaseIsAuthorized,\n"
    "                  self.selectedID == candidate.id else {\n"
    "                self.failLocally(\"Exact scooter/account authority could not be re-verified immediately before BLE authentication.\", \"sdk_device_membership_recheck_failed\")\n",
    "            guard stillAuthorized,\n"
    "                  self.phase == .selected,\n"
    "                  self.targetCorrelationOperatorConfirmed,\n"
    "                  self.sdkAccountLoggedIn,\n"
    "                  self.accountIdentityLeaseIsAuthorized,\n"
    "                  self.selectedID == candidate.id else {\n"
    "                self.failLocally(\"Exact selected-target confirmation and scooter/account authority could not be re-verified immediately before BLE authentication.\", \"sdk_device_membership_recheck_failed\")\n",
    "block stale async membership resurrection",
)
replace_once(
    "    private func beginOfficialConnection(candidate: Candidate) {\n"
    "        guard phase == .selected || phase == .failed else { return }\n"
    "        guard candidate.likely,\n"
    "              sdkDeviceMembershipVerified,\n"
    "              sdkAccountLoggedIn,\n"
    "              accountIdentityLeaseIsAuthorized else {\n",
    "    private func beginOfficialConnection(candidate: Candidate) {\n"
    "        guard phase == .selected else { return }\n"
    "        guard targetCorrelationOperatorConfirmed,\n"
    "              selectedID == candidate.id,\n"
    "              candidate.likely,\n"
    "              fieldBuildIsAuthoritative,\n"
    "              sdkDeviceMembershipVerified,\n"
    "              sdkAccountLoggedIn,\n"
    "              accountIdentityLeaseIsAuthorized else {\n",
    "tighten official connection authority",
)
# remove the remaining beginOfficialConnection scanner stop after the membership one was removed above
replace_once("        central.stopScan()\n", "", "remove connection-start scanner stop")
replace_once(
    "    private func resetDiscoverySessionOnly() {\n"
    "        correlationSession?.abandonCurrentWindow()\n"
    "        correlationSession = nil\n",
    "    private func resetDiscoverySessionOnly() {\n"
    "        stopCorrelationProgressObservation()\n"
    "        correlationSession?.abandonCurrentWindow()\n"
    "        correlationSession = nil\n"
    "        correlationProgress = nil\n",
    "reset presentation progress",
)
replace_once("        central.stopScan()\n", "", "remove reset scanner stop")
replace_once("        baseline.removeAll()\n", "", "remove legacy baseline state")
replace_once(
    "        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {\n"
    "            correlationSession?.abandonCurrentWindow()\n"
    "            correlationSession = nil\n"
    "        }\n"
    "        pendingCorrelatedTargetID = nil\n",
    "        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {\n"
    "            stopCorrelationProgressObservation()\n"
    "            correlationSession?.abandonCurrentWindow()\n"
    "            correlationSession = nil\n"
    "            correlationProgress = nil\n"
    "        }\n"
    "        pendingCorrelatedTargetID = nil\n",
    "retire progress state on local failure",
)
replace_once("        central.stopScan()\n", "", "remove failure scanner stop")

legacy_start = text.find("    private static func hasTuyaCompanyID")
legacy_end_marker = "\n@MainActor\nprivate protocol OfficialTuyaDriver: AnyObject {"
legacy_end = text.find(legacy_end_marker, legacy_start)
if legacy_start < 0 or legacy_end < 0:
    raise SystemExit("legacy scanner block markers missing")
text = text[:legacy_start] + "}\n" + text[legacy_end:]

# Final authority assertions.
required = [
    "@Published private(set) var correlationProgress: PassiveBluetoothPowerCycleObservationProgress?",
    "private var correlationProgressTask: Task<Void, Never>?",
    "startCorrelationProgressObservation(session: session)",
    "private func stopCorrelationProgressObservation()",
    "self.phase == .selected",
    "self.targetCorrelationOperatorConfirmed",
    "guard phase == .selected else { return }",
    "selectedID == candidate.id",
    "fieldBuildIsAuthoritative",
]
for needle in required:
    if needle not in text:
        raise SystemExit(f"missing postcondition: {needle}")
for forbidden in [
    "CBCentralManager",
    "CBCentralManagerDelegate",
    "CBAdvertisementData",
    "central.stopScan()",
    "static let fd50 = CBUUID",
    "private var baseline = Set<UUID>()",
    "var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }",
    "phase == .selected || phase == .failed",
]:
    if forbidden in text:
        raise SystemExit(f"forbidden stale authority remains: {forbidden}")

PATH.write_text(text)
print("Capture app readiness/auth patch applied")
