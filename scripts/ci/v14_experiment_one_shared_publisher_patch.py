from pathlib import Path

path = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift")
source = path.read_text()

artifact_context = """    private struct ArtifactContext {
        let recorder: PassiveCoreBluetoothCaptureRecorder
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
        let eventWatermark: UInt64
    }
"""
experiment_authority = artifact_context + """
    /// Provenance retained beside the exact run-owned recorder for one
    /// admitted Experiment One target session. This is software authority
    /// only; it does not authenticate the physical scooter.
    private struct ExperimentOneCaptureAuthority {
        let admissionIdentity: UUID
        let powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence
        let peripheralIdentifier: UUID
        let recorder: PassiveCoreBluetoothCaptureRecorder
        let issuedAtUptimeNanoseconds: UInt64
    }
"""
if source.count(artifact_context) != 1:
    raise SystemExit("ArtifactContext insertion point drifted")
source = source.replace(artifact_context, experiment_authority, 1)

recorder_state = "    private var recorder: PassiveCoreBluetoothCaptureRecorder?\n"
recorder_replacement = recorder_state + "    private var experimentOneCaptureAuthority: ExperimentOneCaptureAuthority?\n"
if source.count(recorder_state) != 1:
    raise SystemExit("recorder state insertion point drifted")
source = source.replace(recorder_state, recorder_replacement, 1)

admitted_start = source.index("    /// Connects the exact correlated Experiment One target using the mutable recorder")
admitted_end = source.index("    /// Cancels the active attempt without allowing a subsequent attempt", admitted_start)
admitted_method = """    /// Connects the exact correlated Experiment One target using the recorder and
    /// provenance sealed by that same run. The admission is package-internal and
    /// consumed exactly once; app/UI code cannot forge this authority.
    ///
    /// Repeated full CoreBluetooth UUID is still only a correlated Bluetooth target.
    /// This path performs no application characteristic-value write.
    func connect(
        using admission: PassiveBluetoothExperimentOneCaptureAdmission,
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

        let peripheral = try connectionCandidate(for: payload.peripheralIdentifier)
        if latestDiscoveryByIdentifier[payload.peripheralIdentifier]?.isConnectable == false {
            throw ControllerError.peripheralNotConnectable(payload.peripheralIdentifier)
        }
        guard let latestAdvertisement = latestAdvertisementByIdentifier[payload.peripheralIdentifier],
              latestAdvertisement.receivedAtUptimeNanoseconds >= payload.issuedAtUptimeNanoseconds else {
            throw ControllerError.unknownPeripheral(payload.peripheralIdentifier)
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

        try beginExperimentOneTargetSession(using: payload)
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

    private func connectionCandidate(for peripheralIdentifier: UUID) throws -> CBPeripheral {
        guard let peripheral = peripheralByIdentifier[peripheralIdentifier],
              latestDiscoveryByIdentifier[peripheralIdentifier] != nil else {
            throw ControllerError.unknownPeripheral(peripheralIdentifier)
        }
        return peripheral
    }

"""
source = source[:admitted_start] + admitted_method + source[admitted_end:]

session_start = source.index("    private func beginTargetSessionIfNeeded(for identifier: UUID) throws {")
session_end = source.index("    private func currentArtifactContext() throws -> ArtifactContext {", session_start)
session_methods = """    private func beginTargetSessionIfNeeded(for identifier: UUID) throws {
        if targetState.selectedTargetIdentifier == identifier, recorder != nil {
            return
        }

        guard targetSessionGeneration != UInt64.max else {
            throw ControllerError.captureFailed
        }

        let latestAdvertisement = latestAdvertisementByIdentifier[identifier]
        let startedAt = latestAdvertisement?.receivedAtDate
            ?? (!hasUsedInitialSessionIdentity ? firstSessionStartedAtOverride : nil)
            ?? Date()
        let sessionID = hasUsedInitialSessionIdentity ? UUID() : initialSessionID
        let newRecorder = try PassiveCoreBluetoothCaptureRecorder(
            id: sessionID,
            vehicleIdentity: vehicleIdentity,
            startedAt: startedAt
        )

        try publishTargetSession(
            identifier: identifier,
            newRecorder: newRecorder,
            latestAdvertisement: latestAdvertisement,
            experimentOneAuthority: nil
        )
    }

    private func beginExperimentOneTargetSession(
        using payload: PassiveBluetoothExperimentOneCaptureAdmission.Payload
    ) throws {
        let latestAdvertisement = latestAdvertisementByIdentifier[payload.peripheralIdentifier]
        guard let latestAdvertisement,
              latestAdvertisement.receivedAtUptimeNanoseconds >= payload.issuedAtUptimeNanoseconds else {
            throw ControllerError.unknownPeripheral(payload.peripheralIdentifier)
        }
        let authority = ExperimentOneCaptureAuthority(
            admissionIdentity: payload.admissionIdentity,
            powerCycleEvidence: payload.powerCycleEvidence,
            peripheralIdentifier: payload.peripheralIdentifier,
            recorder: payload.recorder,
            issuedAtUptimeNanoseconds: payload.issuedAtUptimeNanoseconds
        )
        try publishTargetSession(
            identifier: payload.peripheralIdentifier,
            newRecorder: payload.recorder,
            latestAdvertisement: latestAdvertisement,
            experimentOneAuthority: authority
        )
    }

    private func publishTargetSession(
        identifier: UUID,
        newRecorder: PassiveCoreBluetoothCaptureRecorder,
        latestAdvertisement: CandidateAdvertisement?,
        experimentOneAuthority: ExperimentOneCaptureAuthority?
    ) throws {
        guard observationBoundaryQueueGate.resetForNewCaptureSession() else {
            throw ControllerError.captureIncomplete
        }
        committedReadyEpoch = nil

        let previousAuthority = currentArtifactAuthorityContext()
        let nextTargetSessionGeneration = targetSessionGeneration + 1
        let freshAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: nextTargetSessionGeneration,
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

        targetState.selectTarget(identifier)
        acquisitionLedger.beginTargetSession()
        gattIdentityRegistry.reset()
        selectedTargetCancellationPending = false
        foregroundEvidenceIntegrityValid = true
        hasUsedInitialSessionIdentity = true
        experimentOneCaptureAuthority = experimentOneAuthority
        self.recorder = newRecorder

        if let latestAdvertisement {
            enqueue(
                .advertisement(latestAdvertisement.observation),
                receivedAtUptimeNanoseconds: latestAdvertisement.receivedAtUptimeNanoseconds,
                receivedAtDate: latestAdvertisement.receivedAtDate
            )
        }
    }

"""
source = source[:session_start] + session_methods + source[session_end:]
path.write_text(source)
