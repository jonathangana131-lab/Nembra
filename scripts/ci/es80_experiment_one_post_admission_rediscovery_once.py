from pathlib import Path

run_path = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneRun.swift")
controller_path = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift")

run_source = run_path.read_text()
controller_source = controller_path.read_text()


def once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 occurrence of {old!r}, found {count}")
    return source.replace(old, new, 1)


# Producer: carry one monotonic software handoff boundary in the producer-sealed
# payload. Use intentionally tiny anchors so formatting/comment churn cannot turn
# this transform into a broad rewrite.
run_source = once(
    run_source,
    "        let admissionIdentity: UUID\n",
    """        let admissionIdentity: UUID
        /// Local monotonic software handoff boundary captured when this sealed
        /// admission is issued. It orders controller callback receipts only; it is
        /// not BLE/RF emission time and carries no physical timing semantics.
        let issuedAtUptimeNanoseconds: UInt64
""",
    "payload property",
)
run_source = once(
    run_source,
    "            admissionIdentity: UUID,\n",
    """            admissionIdentity: UUID,
            issuedAtUptimeNanoseconds: UInt64,
""",
    "payload initializer parameter",
)
run_source = once(
    run_source,
    "            self.admissionIdentity = admissionIdentity\n",
    """            self.admissionIdentity = admissionIdentity
            self.issuedAtUptimeNanoseconds = issuedAtUptimeNanoseconds
""",
    "payload initializer assignment",
)
run_source = once(
    run_source,
    """    fileprivate init(
        powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence,
""",
    """    fileprivate init(
        issuedAtUptimeNanoseconds: UInt64,
        powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence,
""",
    "admission initializer parameter",
)
run_source = once(
    run_source,
    "            admissionIdentity: UUID(),\n",
    """            admissionIdentity: UUID(),
            issuedAtUptimeNanoseconds: issuedAtUptimeNanoseconds,
""",
    "payload construction",
)
run_source = once(
    run_source,
    """        let recorder = try beginCaptureRecorder(startedAt: startedAt)
        return PassiveBluetoothExperimentOneCaptureAdmission(
""",
    """        let recorder = try beginCaptureRecorder(startedAt: startedAt)
        // Captured only after the exact run-owned recorder constructor succeeds and
        // immediately before the sealed one-shot handoff is minted.
        let issuedAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        return PassiveBluetoothExperimentOneCaptureAdmission(
            issuedAtUptimeNanoseconds: issuedAtUptimeNanoseconds,
""",
    "admission issuance",
)

# Controller: require a callback receipt on/after that boundary before any target
# publication or exact recorder installation.
controller_source = once(
    controller_source,
    "        case experimentOneVehicleContextMismatch\n",
    """        case experimentOneVehicleContextMismatch
        case experimentOneRediscoveryRequired(UUID)
""",
    "controller error",
)
controller_source = once(
    controller_source,
    """        if discovery.isConnectable == false {
            throw ControllerError.peripheralNotConnectable(payload.peripheralIdentifier)
        }

        do {
""",
    """        guard let latestAdvertisement = latestAdvertisementByIdentifier[payload.peripheralIdentifier],
              latestAdvertisement.receivedAtUptimeNanoseconds >= payload.issuedAtUptimeNanoseconds else {
            throw ControllerError.experimentOneRediscoveryRequired(payload.peripheralIdentifier)
        }
        if discovery.isConnectable == false {
            throw ControllerError.peripheralNotConnectable(payload.peripheralIdentifier)
        }

        do {
""",
    "post-admission rediscovery guard",
)
controller_source = once(
    controller_source,
    "        let latestAdvertisement = latestAdvertisementByIdentifier[payload.peripheralIdentifier]\n",
    "",
    "remove stale optional advertisement lookup",
)
controller_source = once(
    controller_source,
    """        if let latestAdvertisement {
            enqueue(
                .advertisement(latestAdvertisement.observation),
                receivedAtUptimeNanoseconds: latestAdvertisement.receivedAtUptimeNanoseconds,
                receivedAtDate: latestAdvertisement.receivedAtDate
            )
        }
""",
    """        enqueue(
            .advertisement(latestAdvertisement.observation),
            receivedAtUptimeNanoseconds: latestAdvertisement.receivedAtUptimeNanoseconds,
            receivedAtDate: latestAdvertisement.receivedAtDate
        )
""",
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
