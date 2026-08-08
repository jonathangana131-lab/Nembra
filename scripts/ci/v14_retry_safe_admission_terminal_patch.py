from pathlib import Path

path = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift")
source = path.read_text()

error_needle = "        case experimentOneVehicleContextMismatch\n        case targetNotSelected\n"
error_replacement = "        case experimentOneVehicleContextMismatch\n        case experimentOneTargetNotRediscoveredAfterAdmission(UUID)\n        case targetNotSelected\n"
if source.count(error_needle) != 1:
    raise SystemExit(f"ControllerError insertion point drifted: {source.count(error_needle)}")
source = source.replace(error_needle, error_replacement, 1)

old = """        let payload = try admission.consume()
        guard case let .singleRepeatableCandidate(correlatedIdentifier) =
                payload.powerCycleEvidence.result.correlation.disposition,
              correlatedIdentifier == payload.peripheralIdentifier else {
            throw ControllerError.targetSessionChanged
        }
        guard let peripheral = peripheralByIdentifier[payload.peripheralIdentifier],
              let discovery = latestDiscoveryByIdentifier[payload.peripheralIdentifier] else {
            throw ControllerError.unknownPeripheral(payload.peripheralIdentifier)
        }
        if discovery.isConnectable == false {
            throw ControllerError.peripheralNotConnectable(payload.peripheralIdentifier)
        }

        do {
            try targetState.validateCanBeginAttempt(for: payload.peripheralIdentifier)
        } catch PassiveCoreBluetoothTargetState.StateError.peripheralAwaitingTerminalCallback(let identifier) {
            throw ControllerError.peripheralAwaitingTerminalCallback(identifier)
        } catch PassiveCoreBluetoothTargetState.StateError.generationExhausted {
            throw ControllerError.attemptGenerationExhausted
        } catch {
            throw ControllerError.targetNotSelected
        }

        guard let latestAdvertisement = latestAdvertisementByIdentifier[payload.peripheralIdentifier],
              latestAdvertisement.receivedAtUptimeNanoseconds >= payload.issuedAtUptimeNanoseconds else {
            // The sealed admission must be joined to a controller observation received after
            // that handoff. Replaying an older cached advertisement would splice two software
            // chronology lives and could enqueue evidence that predates this recorder.
            throw ControllerError.unknownPeripheral(payload.peripheralIdentifier)
        }
"""
new = """        // Read only the producer-sealed staging preview first. A normal rediscovery delay is
        // recoverable: keep this one-shot admission intact until the exact target has appeared
        // in the current controller catalog after the admission handoff.
        let preview = try admission.stagingPreview()
        guard let peripheral = peripheralByIdentifier[preview.peripheralIdentifier],
              let discovery = latestDiscoveryByIdentifier[preview.peripheralIdentifier] else {
            throw ControllerError.experimentOneTargetNotRediscoveredAfterAdmission(preview.peripheralIdentifier)
        }
        if discovery.isConnectable == false {
            throw ControllerError.peripheralNotConnectable(preview.peripheralIdentifier)
        }

        do {
            try targetState.validateCanBeginAttempt(for: preview.peripheralIdentifier)
        } catch PassiveCoreBluetoothTargetState.StateError.peripheralAwaitingTerminalCallback(let identifier) {
            throw ControllerError.peripheralAwaitingTerminalCallback(identifier)
        } catch PassiveCoreBluetoothTargetState.StateError.generationExhausted {
            throw ControllerError.attemptGenerationExhausted
        } catch {
            throw ControllerError.targetNotSelected
        }

        guard let latestAdvertisement = latestAdvertisementByIdentifier[preview.peripheralIdentifier],
              latestAdvertisement.receivedAtUptimeNanoseconds >= preview.issuedAtUptimeNanoseconds else {
            throw ControllerError.experimentOneTargetNotRediscoveredAfterAdmission(preview.peripheralIdentifier)
        }

        // All recoverable controller-local checks have passed. Burn the admission only at
        // the ownership handoff, then mechanically prove that the consumed payload is the
        // same producer-sealed target/issuance event that was staged above.
        let payload = try admission.consume()
        guard payload.admissionIdentity == preview.admissionIdentity,
              payload.peripheralIdentifier == preview.peripheralIdentifier,
              payload.issuedAtUptimeNanoseconds == preview.issuedAtUptimeNanoseconds,
              case let .singleRepeatableCandidate(correlatedIdentifier) =
                payload.powerCycleEvidence.result.correlation.disposition,
              correlatedIdentifier == preview.peripheralIdentifier else {
            throw ControllerError.targetSessionChanged
        }
"""
count = source.count(old)
if count != 1:
    raise SystemExit(f"expected one exact Experiment One staging block, found {count}")
source = source.replace(old, new, 1)
path.write_text(source)
