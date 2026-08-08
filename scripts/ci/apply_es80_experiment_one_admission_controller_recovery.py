from pathlib import Path

path = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift")
source = path.read_text()

artifact_context = """    private struct ArtifactContext {
        let recorder: PassiveCoreBluetoothCaptureRecorder
        let authority: PassiveCoreBluetoothArtifactAuthorityContext
        let eventWatermark: UInt64
    }
"""
authority_context = artifact_context + """
    /// Sealed software provenance retained only for a target session that entered
    /// through the package-owned Experiment One admission. Generic research
    /// `connect(to:)` sessions never receive this authority.
    private struct ExperimentOneCaptureAuthority {
        let admissionIdentity: UUID
        let powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence
        let peripheralIdentifier: UUID
    }
"""
if source.count(artifact_context) != 1:
    raise SystemExit("ArtifactContext anchor changed")
source = source.replace(artifact_context, authority_context, 1)

foreground_state = """    private var foregroundEvidenceIntegrityValid = true
    private var scanRequested = false
"""
foreground_with_admission = """    private var foregroundEvidenceIntegrityValid = true
    private var experimentOneCaptureAuthority: ExperimentOneCaptureAuthority?
    private var scanRequested = false
"""
if source.count(foreground_state) != 1:
    raise SystemExit("foreground state anchor changed")
source = source.replace(foreground_state, foreground_with_admission, 1)

connect_start = source.index("    public func connect(\n")
connect_end = source.index("\n    /// Cancels the active attempt", connect_start)
new_connect = """    public func connect(
        to peripheralIdentifier: UUID,
        timeout: TimeInterval = 12
    ) throws {
        let candidate = try connectionCandidate(
            for: peripheralIdentifier,
            timeout: timeout
        )
        try beginTargetSessionIfNeeded(for: peripheralIdentifier)
        try beginConnectionAttempt(
            on: candidate.peripheral,
            timeoutNanoseconds: candidate.timeoutNanoseconds
        )
    }

    /// Consumes one producer-owned Experiment One admission and starts capture on
    /// the exact correlated peripheral/recorder pair it carries. This method is
    /// intentionally package-internal: app/UI code cannot supply a UUID or recorder
    /// directly and cannot construct the admission type.
    func connect(
        using admission: PassiveBluetoothExperimentOneCaptureAdmission,
        timeout: TimeInterval = 12
    ) throws {
        try ensureCaptureHealthy()
        guard recorder == nil,
              targetState.selectedTargetIdentifier == nil,
              experimentOneCaptureAuthority == nil,
              vehicleIdentity == VehicleProfile.aovoproES80.identity else {
            throw ControllerError.captureIncomplete
        }

        // Consumption is the provenance mutation point. If the current controller
        // catalog no longer contains this exact UUID, the one-shot is burned rather
        // than being replayed after another scan epoch.
        let payload = try admission.consume()
        guard case let .singleRepeatableCandidate(correlatedIdentifier) =
                payload.powerCycleEvidence.result.correlation.disposition,
              correlatedIdentifier == payload.peripheralIdentifier else {
            throw ControllerError.captureIncomplete
        }

        let candidate = try connectionCandidate(
            for: payload.peripheralIdentifier,
            timeout: timeout
        )
        try beginExperimentOneTargetSession(using: payload)
        try beginConnectionAttempt(
            on: candidate.peripheral,
            timeoutNanoseconds: candidate.timeoutNanoseconds
        )
    }

    private func connectionCandidate(
        for peripheralIdentifier: UUID,
        timeout: TimeInterval
    ) throws -> (peripheral: CBPeripheral, timeoutNanoseconds: UInt64) {
        try ensureCaptureHealthy()
        guard !observationBoundaryQueueGate.isTerminal else {
            throw ControllerError.captureFinalized
        }
        // Horizon admission freezes the artifact cutoff. A new transport attempt
        // cannot revoke that closing authority while JSON sealing is in flight.
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
        // Both maps are reset together at every explicit scan start. Requiring the
        // live object and discovery projection prevents an admission from reviving a
        // CoreBluetooth object retained outside the current candidate epoch.
        guard let peripheral = peripheralByIdentifier[peripheralIdentifier],
              latestDiscoveryByIdentifier[peripheralIdentifier] != nil else {
            throw ControllerError.unknownPeripheral(peripheralIdentifier)
        }
        if latestDiscoveryByIdentifier[peripheralIdentifier]?.isConnectable == false {
            throw ControllerError.peripheralNotConnectable(peripheralIdentifier)
        }

        do {
            try targetState.validateCanBeginAttempt(for: peripheralIdentifier)
        } catch PassiveCoreBluetoothTargetState.StateError.peripheralAwaitingTerminalCallback(let identifier) {
            throw ControllerError.peripheralAwaitingTerminalCallback(identifier)
        } catch PassiveCoreBluetoothTargetState.StateError.generationExhausted {
            throw ControllerError.attemptGenerationExhausted
        } catch {
            throw ControllerError.targetNotSelected
        }

        return (peripheral, timeoutNanoseconds)
    }

    private func beginConnectionAttempt(
        on peripheral: CBPeripheral,
        timeoutNanoseconds: UInt64
    ) throws {
        let peripheralIdentifier = peripheral.identifier
        do {
            _ = try targetState.beginAttempt(for: peripheralIdentifier)
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
        connectionPhase = .connecting(peripheralIdentifier)
        activePeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
        scheduleConnectionTimeout(for: peripheral, nanoseconds: timeoutNanoseconds)
    }
"""
source = source[:connect_start] + new_connect + source[connect_end:]

session_start = source.index("    private func beginTargetSessionIfNeeded(for identifier: UUID) throws {")
session_end = source.index("\n    private func currentArtifactContext() throws", session_start)
new_session = """    private func beginTargetSessionIfNeeded(for identifier: UUID) throws {
        if targetState.selectedTargetIdentifier == identifier, recorder != nil {
            return
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
            for: identifier,
            recorder: newRecorder,
            latestAdvertisement: latestAdvertisement,
            experimentOneAuthority: nil
        )
    }

    private func beginExperimentOneTargetSession(
        using payload: PassiveBluetoothExperimentOneCaptureAdmission.Payload
    ) throws {
        guard recorder == nil,
              targetState.selectedTargetIdentifier == nil else {
            throw ControllerError.captureIncomplete
        }

        let authority = ExperimentOneCaptureAuthority(
            admissionIdentity: payload.admissionIdentity,
            powerCycleEvidence: payload.powerCycleEvidence,
            peripheralIdentifier: payload.peripheralIdentifier
        )
        try publishTargetSession(
            for: payload.peripheralIdentifier,
            recorder: payload.recorder,
            latestAdvertisement: latestAdvertisementByIdentifier[payload.peripheralIdentifier],
            experimentOneAuthority: authority
        )
    }

    private func publishTargetSession(
        for identifier: UUID,
        recorder newRecorder: PassiveCoreBluetoothCaptureRecorder,
        latestAdvertisement: CandidateAdvertisement?,
        experimentOneAuthority: ExperimentOneCaptureAuthority?
    ) throws {
        guard targetSessionGeneration != UInt64.max else {
            throw ControllerError.captureFailed
        }
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
            // Transition the canonical fence first, then publish the complete
            // durable-session authority pair synchronously with no actor hop.
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
        experimentOneCaptureAuthority = experimentOneAuthority
        hasUsedInitialSessionIdentity = true
        self.recorder = newRecorder

        // Preserve at most the selected candidate's latest already-observed
        // advertisement, with the exact callback clocks from when it was actually
        // received. Other broad-scan devices remain candidate-catalog entries only.
        if let latestAdvertisement {
            enqueue(
                .advertisement(latestAdvertisement.observation),
                receivedAtUptimeNanoseconds: latestAdvertisement.receivedAtUptimeNanoseconds,
                receivedAtDate: latestAdvertisement.receivedAtDate
            )
        }
    }
"""
source = source[:session_start] + new_session + source[session_end:]

path.write_text(source)
