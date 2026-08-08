from pathlib import Path
import subprocess

path = Path('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift')
expected_blob = 'c931c11655f52ffe7cd98286943153e7952405c1'
actual_blob = subprocess.check_output(['git', 'hash-object', str(path)], text=True).strip()
if actual_blob != expected_blob:
    raise SystemExit(f'controller blob moved: expected {expected_blob}, got {actual_blob}')

source = path.read_text()

error_needle = '''        case invalidAcquisitionProgressTimeout\n        case targetNotSelected\n'''
error_replacement = '''        case invalidAcquisitionProgressTimeout\n        case experimentOneVehicleContextMismatch\n        case targetNotSelected\n'''
if source.count(error_needle) != 1:
    raise SystemExit('ControllerError insertion anchor was not unique')
source = source.replace(error_needle, error_replacement, 1)

marker = '''\n    /// Cancels the active attempt without allowing a subsequent attempt to the\n'''
if source.count(marker) != 1:
    raise SystemExit('controller admission method insertion anchor was not unique')

method = r'''

    /// Connects the exact correlated Experiment One target using the mutable recorder
    /// already owned by that same sealed run. This package-internal bridge is the only
    /// controller path that may turn `PassiveBluetoothExperimentOneCaptureAdmission`
    /// into live capture ownership; app/UI code cannot call it directly.
    ///
    /// The admission is consumed once only after controller-global preconditions that
    /// do not depend on its hidden target have passed. The consumed full CoreBluetooth
    /// UUID must then exist in this controller's *current* candidate catalog. A repeatable
    /// UUID is still only a correlated Bluetooth target, never authenticated ES80 identity.
    /// No application characteristic write is performed by this path.
    func connectUsingExperimentOneAdmission(
        _ admission: PassiveBluetoothExperimentOneCaptureAdmission,
        timeout: TimeInterval = 12
    ) throws {
        try ensureCaptureHealthy()
        guard vehicleIdentity == VehicleProfile.aovoproES80.identity else {
            throw ControllerError.experimentOneVehicleContextMismatch
        }
        guard !observationBoundaryQueueGate.isTerminal else {
            throw ControllerError.captureFinalized
        }
        guard !observationBoundaryBlocksArtifactMutation else {
            throw ControllerError.captureIncomplete
        }
        guard centralManager.state == .poweredOn else {
            throw ControllerError.bluetoothNotPoweredOn
        }
        guard let timeoutNanoseconds = PassiveCoreBluetoothAcquisitionPolicy.connectionTimeoutNanoseconds(timeout) else {
            throw ControllerError.invalidConnectionTimeout
        }
        guard connectionPhase == .idle else {
            throw ControllerError.connectionAlreadyActive
        }
        // Experiment One is one provenance life. Do not replace an already-installed
        // generic or prior recorder with a newly consumed sealed admission.
        guard recorder == nil,
              targetState.selectedTargetIdentifier == nil else {
            throw ControllerError.connectionAlreadyActive
        }
        guard targetSessionGeneration != UInt64.max else {
            throw ControllerError.captureFailed
        }

        let payload = try admission.consume()
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

        let latestAdvertisement = latestAdvertisementByIdentifier[payload.peripheralIdentifier]
        guard observationBoundaryQueueGate.resetForNewCaptureSession() else {
            throw ControllerError.captureIncomplete
        }
        committedReadyEpoch = nil

        let previousAuthority = currentArtifactAuthorityContext()
        let freshAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: targetSessionGeneration + 1,
            authorityGeneration: 1
        )
        do {
            try artifactAuthorityFence.transition(
                from: previousAuthority,
                to: freshAuthority
            )
        } catch {
            failCapture(error)
            throw ControllerError.captureFailed
        }
        targetSessionGeneration = freshAuthority.targetSessionGeneration
        artifactAuthorityGeneration = freshAuthority.authorityGeneration
        lastFinalizedArtifactAuthority = nil

        targetState.selectTarget(payload.peripheralIdentifier)
        acquisitionLedger.beginTargetSession()
        gattIdentityRegistry.reset()
        selectedTargetCancellationPending = false
        // Publication of this run-owned recorder is a genuinely fresh durable
        // evidence life, so it earns the same foreground-integrity reset as the
        // generic fresh-session path on the unified controller spine.
        foregroundEvidenceIntegrityValid = true
        hasUsedInitialSessionIdentity = true
        recorder = payload.recorder

        // Preserve only the exact correlated target's latest advertisement, with
        // the callback clocks from the current controller scan that proved catalog
        // presence. Other broad-scan candidates remain unpromoted research signals.
        if let latestAdvertisement {
            enqueue(
                .advertisement(latestAdvertisement.observation),
                receivedAtUptimeNanoseconds: latestAdvertisement.receivedAtUptimeNanoseconds,
                receivedAtDate: latestAdvertisement.receivedAtDate
            )
        }

        do {
            _ = try targetState.beginAttempt(for: payload.peripheralIdentifier)
        } catch PassiveCoreBluetoothTargetState.StateError.peripheralAwaitingTerminalCallback(let identifier) {
            throw ControllerError.peripheralAwaitingTerminalCallback(identifier)
        } catch PassiveCoreBluetoothTargetState.StateError.generationExhausted {
            throw ControllerError.attemptGenerationExhausted
        } catch {
            throw ControllerError.targetNotSelected
        }

        acquisitionLedger.beginConnectionAttempt()
        selectedTargetCancellationPending = false
        guard advanceArtifactAuthority() else {
            throw ControllerError.captureFailed
        }

        stopScanning()
        connectionPhase = .connecting(payload.peripheralIdentifier)
        activePeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
        scheduleConnectionTimeout(for: peripheral, nanoseconds: timeoutNanoseconds)
    }
'''

source = source.replace(marker, method + marker, 1)
path.write_text(source)
