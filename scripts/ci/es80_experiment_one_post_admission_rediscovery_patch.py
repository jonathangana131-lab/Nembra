from pathlib import Path
import subprocess

run_path = Path('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneRun.swift')
controller_path = Path('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift')

expected = {
    run_path: '5bfd17a81c809ee3442c95fc0fa1a35ea18fadf2',
    controller_path: '4cbbb67964e3aa52530762de15c89306ca6a2763',
}
for path, blob in expected.items():
    actual = subprocess.check_output(['git', 'hash-object', str(path)], text=True).strip()
    if actual != blob:
        raise SystemExit(f'{path} moved: expected {blob}, got {actual}')

source = run_path.read_text()
source = source.replace('import Foundation\nimport NembraCore\n', 'import Dispatch\nimport Foundation\nimport NembraCore\n', 1)
source = source.replace(
'''    struct Payload {\n        let admissionIdentity: UUID\n        let powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence\n''',
'''    struct Payload {\n        let admissionIdentity: UUID\n        /// Local monotonic handoff boundary. Callback chronology only; never BLE/RF emission time.\n        let issuedAtUptimeNanoseconds: UInt64\n        let powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence\n''', 1)
source = source.replace(
'''        fileprivate init(\n            admissionIdentity: UUID,\n            powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence,\n''',
'''        fileprivate init(\n            admissionIdentity: UUID,\n            issuedAtUptimeNanoseconds: UInt64,\n            powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence,\n''', 1)
source = source.replace(
'''            self.admissionIdentity = admissionIdentity\n            self.powerCycleEvidence = powerCycleEvidence\n''',
'''            self.admissionIdentity = admissionIdentity\n            self.issuedAtUptimeNanoseconds = issuedAtUptimeNanoseconds\n            self.powerCycleEvidence = powerCycleEvidence\n''', 1)
source = source.replace(
'''        payload = Payload(\n            admissionIdentity: UUID(),\n            powerCycleEvidence: powerCycleEvidence,\n''',
'''        payload = Payload(\n            admissionIdentity: UUID(),\n            issuedAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,\n            powerCycleEvidence: powerCycleEvidence,\n''', 1)
run_path.write_text(source)

source = controller_path.read_text()
source = source.replace(
'''        case experimentOneVehicleContextMismatch\n        case targetNotSelected\n''',
'''        case experimentOneVehicleContextMismatch\n        case experimentOnePostAdmissionRediscoveryRequired(UUID)\n        case targetNotSelected\n''', 1)
source = source.replace(
'''        if discovery.isConnectable == false {\n            throw ControllerError.peripheralNotConnectable(payload.peripheralIdentifier)\n        }\n\n        do {\n''',
'''        if discovery.isConnectable == false {\n            throw ControllerError.peripheralNotConnectable(payload.peripheralIdentifier)\n        }\n        guard let latestAdvertisement = latestAdvertisementByIdentifier[payload.peripheralIdentifier],\n              latestAdvertisement.receivedAtUptimeNanoseconds >= payload.issuedAtUptimeNanoseconds else {\n            throw ControllerError.experimentOnePostAdmissionRediscoveryRequired(payload.peripheralIdentifier)\n        }\n\n        do {\n''', 1)
source = source.replace(
'''        let latestAdvertisement = latestAdvertisementByIdentifier[payload.peripheralIdentifier]\n        guard observationBoundaryQueueGate.resetForNewCaptureSession() else {\n''',
'''        guard observationBoundaryQueueGate.resetForNewCaptureSession() else {\n''', 1)
source = source.replace(
'''        if let latestAdvertisement {\n            enqueue(\n                .advertisement(latestAdvertisement.observation),\n                receivedAtUptimeNanoseconds: latestAdvertisement.receivedAtUptimeNanoseconds,\n                receivedAtDate: latestAdvertisement.receivedAtDate\n            )\n        }\n''',
'''        enqueue(\n            .advertisement(latestAdvertisement.observation),\n            receivedAtUptimeNanoseconds: latestAdvertisement.receivedAtUptimeNanoseconds,\n            receivedAtDate: latestAdvertisement.receivedAtDate\n        )\n''', 1)
controller_path.write_text(source)
