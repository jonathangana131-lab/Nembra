#!/usr/bin/env python3
from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
text = path.read_text()

def once(old: str, new: str, label: str) -> None:
    global text
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"{label}: expected 1 anchor, found {n}")
    text = text.replace(old, new, 1)

once("@preconcurrency import CoreBluetooth\n", "", "CoreBluetooth import")
once("let CBAdvertisementDataIsConnectableKey = CBAdvertisementDataIsConnectable\n\n", "", "advertisement alias")
once("    static let fd50 = CBUUID(string: \"FD50\")\n", "", "legacy FD50 constant")
once(
    "    @Published private(set) var pendingCorrelatedTargetID: UUID?\n    @Published private(set) var sdkLocalBLEOnline = false\n",
    "    @Published private(set) var pendingCorrelatedTargetID: UUID?\n    @Published private(set) var correlationProgress: PassiveBluetoothPowerCycleObservationProgress?\n    @Published private(set) var sdkLocalBLEOnline = false\n",
    "published progress",
)
once(
    "    private let buildIdentity = NembraCaptureBuildIdentity.current\n    private var central: CBCentralManager!\n    private var byID: [UUID: Candidate] = [:]\n    private var baseline = Set<UUID>()\n    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?\n",
    "    private let buildIdentity = NembraCaptureBuildIdentity.current\n    private var byID: [UUID: Candidate] = [:]\n    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?\n    private var correlationProgressTask: Task<Void, Never>?\n",
    "scanner ownership fields",
)
once("        super.init()\n        central = CBCentralManager(delegate: self, queue: .main)\n        log(\"controller_created\")\n", "        super.init()\n        log(\"controller_created\")\n", "central init")
once("    deinit { watchdog?.cancel() }\n", "    deinit {\n        watchdog?.cancel()\n        correlationProgressTask?.cancel()\n    }\n", "deinit")
once("    var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }\n", "", "computed progress")
once(
    "            try session.startCurrentWindow()\n            phase = progress.phase.operatorExpectedPowerOn ? .scanning : .baseline\n",
    "            try session.startCurrentWindow()\n            startCorrelationProgressObservation(session: session)\n            phase = progress.phase.operatorExpectedPowerOn ? .scanning : .baseline\n",
    "window observer start",
)
once(
    "    func finishCorrelationWindow() {\n",
    "    private func startCorrelationProgressObservation(session: PassiveBluetoothPowerCycleObservationSession) {\n        stopCorrelationProgressObservation()\n        correlationProgress = session.progress\n        correlationProgressTask = Task { @MainActor [weak self] in\n            while !Task.isCancelled {\n                guard let self, self.correlationSession === session else { return }\n                if let progress = session.progress { self.correlationProgress = progress }\n                try? await Task.sleep(for: .milliseconds(100))\n            }\n        }\n    }\n\n    private func stopCorrelationProgressObservation() {\n        correlationProgressTask?.cancel()\n        correlationProgressTask = nil\n    }\n\n    func finishCorrelationWindow() {\n",
    "observer helpers",
)
once("            let final = try session.finishCurrentWindow()\n            if let final {\n", "            let final = try session.finishCurrentWindow()\n            stopCorrelationProgressObservation()\n            correlationProgress = session.progress\n            if let final {\n", "sealed progress")
once("            default:\n                session.abandonCurrentWindow()\n                correlationSession = nil\n", "            default:\n                stopCorrelationProgressObservation()\n                session.abandonCurrentWindow()\n                correlationSession = nil\n                correlationProgress = nil\n", "typed window failure")
once("        } catch {\n            session.abandonCurrentWindow()\n            correlationSession = nil\n            failLocally(\"\\(sealedLabel) failed closed: \\(error.localizedDescription). Restart the complete correlation series.\", \"target_correlation_window_failed\")\n", "        } catch {\n            stopCorrelationProgressObservation()\n            session.abandonCurrentWindow()\n            correlationSession = nil\n            correlationProgress = nil\n            failLocally(\"\\(sealedLabel) failed closed: \\(error.localizedDescription). Restart the complete correlation series.\", \"target_correlation_window_failed\")\n", "generic window failure")
once("        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {\n            correlationSession?.abandonCurrentWindow()\n            correlationSession = nil\n        }\n        membershipStatus", "        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {\n            stopCorrelationProgressObservation()\n            correlationSession?.abandonCurrentWindow()\n            correlationSession = nil\n            correlationProgress = nil\n        }\n        membershipStatus", "membership invalidation progress")
if text.count("        central.stopScan()\n") != 4:
    raise SystemExit(f"legacy stopScan count changed: {text.count('        central.stopScan()')} (expected 4)")
text = text.replace("        central.stopScan()\n", "")
once("    private func resetDiscoverySessionOnly() {\n        correlationSession?.abandonCurrentWindow()\n        correlationSession = nil\n", "    private func resetDiscoverySessionOnly() {\n        stopCorrelationProgressObservation()\n        correlationSession?.abandonCurrentWindow()\n        correlationSession = nil\n        correlationProgress = nil\n", "reset progress")
once("        baseline.removeAll()\n", "", "baseline reset")
once("    private func failLocally(_ text: String, _ kind: String) {\n        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {\n            correlationSession?.abandonCurrentWindow()\n            correlationSession = nil\n        }\n", "    private func failLocally(_ text: String, _ kind: String) {\n        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {\n            stopCorrelationProgressObservation()\n            correlationSession?.abandonCurrentWindow()\n            correlationSession = nil\n            correlationProgress = nil\n        }\n", "local failure progress")
start = text.find("    private static func hasTuyaCompanyID")
end = text.find("\n@MainActor\nprivate protocol OfficialTuyaDriver: AnyObject {", start)
if start < 0 or end < 0:
    raise SystemExit("legacy scanner block markers changed")
text = text[:start] + "}\n" + text[end:]
for forbidden in ["CBCentralManager", "CBCentralManagerDelegate", "CBAdvertisementData", "central.stopScan", "private var baseline = Set<UUID>()", "private func updateCandidate", "private static func hasTuyaCompanyID"]:
    if forbidden in text:
        raise SystemExit(f"legacy scanner authority remains: {forbidden}")
for required in ["@Published private(set) var correlationProgress", "private var correlationProgressTask", "startCorrelationProgressObservation(session: session)", "self.correlationProgress = progress", "stopCorrelationProgressObservation()", "PassiveBluetoothPowerCycleObservationSession"]:
    if required not in text:
        raise SystemExit(f"missing readiness postcondition: {required}")
path.write_text(text)
print("Capture readiness/single-scanner patch applied")
