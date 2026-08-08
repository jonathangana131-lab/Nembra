from pathlib import Path

run_path = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneRun.swift")
controller_path = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift")

run_source = run_path.read_text()
controller_source = controller_path.read_text()


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one source anchor, found {count}")
    return source.replace(old, new, 1)


run_source = replace_once(
    run_source,
    """    struct Payload {\n        let admissionIdentity: UUID\n        let powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence\n""",
    """    struct Payload {\n        let admissionIdentity: UUID\n        /// Local monotonic software handoff boundary captured when this sealed\n        /// admission is issued. It orders controller callback receipts only; it is\n        /// not BLE/RF emission time and carries no physical timing semantics.\n        let issuedAtUptimeNanoseconds: UInt64\n        let powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence\n""",
    "payload property",
)

run_source = replace_once(
    run_source,
    """        fileprivate init(\n            admissionIdentity: UUID,\n            powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence,\n""",
    """        fileprivate init(\n            admissionIdentity: UUID,\n            issuedAtUptimeNanoseconds: UInt64,\n            powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence,\n""",
    "payload initializer signature",
)

run_source = replace_once(
    run_source,
    """            self.admissionIdentity = admissionIdentity\n            self.powerCycleEvidence = powerCycleEvidence\n""",
    """            self.admissionIdentity = admissionIdentity\n            self.issuedAtUptimeNanoseconds = issuedAtUptimeNanoseconds\n            self.powerCycleEvidence = powerCycleEvidence\n""",
    "payload initializer assignment",
)

run_source = replace_once(
    run_source,
    """    fileprivate init(\n        powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence,\n        peripheralIdentifier: UUID,\n        recorder: PassiveCoreBluetoothCaptureRecorder\n    ) {\n        payload = Payload(\n            admissionIdentity: UUID(),\n            powerCycleEvidence: powerCycleEvidence,\n""",
    """    fileprivate init(\n        issuedAtUptimeNanoseconds: UInt64,\n        powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence,\n        peripheralIdentifier: UUID,\n        recorder: PassiveCoreBluetoothCaptureRecorder\n    ) {\n        payload = Payload(\n            admissionIdentity: UUID(),\n            issuedAtUptimeNanoseconds: issuedAtUptimeNanoseconds,\n            powerCycleEvidence: powerCycleEvidence,\n""",
    "admission initializer",
)

run_source = replace_once(
    run_source,
    """        let recorder = try beginCaptureRecorder(startedAt: startedAt)\n        return PassiveBluetoothExperimentOneCaptureAdmission(\n            powerCycleEvidence: evidence,\n            peripheralIdentifier: peripheralIdentifier,\n            recorder: recorder\n        )\n""",
    """        let recorder = try beginCaptureRecorder(startedAt: startedAt)\n        // This monotonic boundary is captured only after the exact run-owned recorder\n        // constructor succeeds, immediately before the sealed handoff is minted.\n        let issuedAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds\n        return PassiveBluetoothExperimentOneCaptureAdmission(\n            issuedAtUptimeNanoseconds: issuedAtUptimeNanoseconds,\n            powerCycleEvidence: evidence,\n            peripheralIdentifier: peripheralIdentifier,\n            recorder: recorder\n        )\n""",
    "admission issuance",
)

controller_source = replace_once(
    controller_source,
    """        case experimentOneVehicleContextMismatch\n        case targetNotSelected\n""",
    """        case experimentOneVehicleContextMismatch\n        case experimentOneRediscoveryRequired(UUID)\n        case targetNotSelected\n""",
    "controller error",
)

controller_source = replace_once(
    controller_source,
    """        guard let peripheral = peripheralByIdentifier[payload.peripheralIdentifier],\n              let discovery = latestDiscoveryByIdentifier[payload.peripheralIdentifier] else {\n            throw ControllerError.unknownPeripheral(payload.peripheralIdentifier)\n        }\n        if discovery.isConnectable == false {\n            throw ControllerError.peripheralNotConnectable(payload.peripheralIdentifier)\n        }\n\n        do {\n""",
    """        guard let peripheral = peripheralByIdentifier[payload.peripheralIdentifier],\n              let discovery = latestDiscoveryByIdentifier[payload.peripheralIdentifier] else {\n            throw ControllerError.unknownPeripheral(payload.peripheralIdentifier)\n        }\n        guard let latestAdvertisement = latestAdvertisementByIdentifier[payload.peripheralIdentifier],\n              latestAdvertisement.receivedAtUptimeNanoseconds >= payload.issuedAtUptimeNanoseconds else {\n            throw ControllerError.experimentOneRediscoveryRequired(payload.peripheralIdentifier)\n        }\n        if discovery.isConnectable == false {\n            throw ControllerError.peripheralNotConnectable(payload.peripheralIdentifier)\n        }\n\n        do {\n""",
    "post-admission rediscovery guard",
)

controller_source = replace_once(
    controller_source,
    """        let latestAdvertisement = latestAdvertisementByIdentifier[payload.peripheralIdentifier]\n        guard observationBoundaryQueueGate.resetForNewCaptureSession() else {\n""",
    """        guard observationBoundaryQueueGate.resetForNewCaptureSession() else {\n""",
    "remove stale optional advertisement lookup",
)

controller_source = replace_once(
    controller_source,
    """        if let latestAdvertisement {\n            enqueue(\n                .advertisement(latestAdvertisement.observation),\n                receivedAtUptimeNanoseconds: latestAdvertisement.receivedAtUptimeNanoseconds,\n                receivedAtDate: latestAdvertisement.receivedAtDate\n            )\n        }\n""",
    """        enqueue(\n            .advertisement(latestAdvertisement.observation),\n            receivedAtUptimeNanoseconds: latestAdvertisement.receivedAtUptimeNanoseconds,\n            receivedAtDate: latestAdvertisement.receivedAtDate\n        )\n""",
    "fresh advertisement enqueue",
)

run_path.write_text(run_source)
controller_path.write_text(controller_source)

required_run = [
    "let issuedAtUptimeNanoseconds: UInt64",
    "let issuedAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds",
    "issuedAtUptimeNanoseconds: issuedAtUptimeNanoseconds",
]
for token in required_run:
    if token not in run_source:
        raise SystemExit(f"missing run token: {token}")

required_controller = [
    "case experimentOneRediscoveryRequired(UUID)",
    "let latestAdvertisement = latestAdvertisementByIdentifier[payload.peripheralIdentifier]",
    "latestAdvertisement.receivedAtUptimeNanoseconds >= payload.issuedAtUptimeNanoseconds",
    "throw ControllerError.experimentOneRediscoveryRequired(payload.peripheralIdentifier)",
    "recorder = payload.recorder",
]
for token in required_controller:
    if token not in controller_source:
        raise SystemExit(f"missing controller token: {token}")

consumer_start = controller_source.index("func connectUsingExperimentOneAdmission(")
consumer_end = controller_source.index("public func cancelActiveConnection()", consumer_start)
consumer = controller_source[consumer_start:consumer_end]
if consumer.count("latestAdvertisementByIdentifier[payload.peripheralIdentifier]") != 1:
    raise SystemExit("Experiment One consumer must have exactly one fresh advertisement lookup")
if consumer.count("admission.consume()") != 1:
    raise SystemExit("Experiment One admission must still be consumed exactly once")
if consumer.index("receivedAtUptimeNanoseconds >= payload.issuedAtUptimeNanoseconds") > consumer.index("recorder = payload.recorder"):
    raise SystemExit("freshness must be proven before recorder installation")
