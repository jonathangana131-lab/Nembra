from pathlib import Path

controller = Path('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift')
s = controller.read_text()

def one(old: str, new: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f'expected one controller match, found {count}: {old[:100]!r}')
    s = s.replace(old, new, 1)

one(
'''        guard !observationBoundaryQueueGate.isTerminal else {
            throw ControllerError.captureFinalized
        }
        guard centralManager.state == .poweredOn else {
            throw ControllerError.bluetoothNotPoweredOn
        }
        guard let timeoutNanoseconds = PassiveCoreBluetoothAcquisitionPolicy.connectionTimeoutNanoseconds(timeout) else {
''',
'''        guard !observationBoundaryQueueGate.isTerminal else {
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
'''
)

one(
'''    private func advanceArtifactAuthority() -> Bool {
        guard artifactAuthorityGeneration != UInt64.max else {
''',
'''    private func advanceArtifactAuthority() -> Bool {
        // Defense in depth: once H owns the immutable cutoff, no transport path may
        // replace the artifact authority. Callers still perform their own transport
        // cleanup so this guard is not used as lifecycle control flow.
        guard !observationBoundaryBlocksArtifactMutation else { return false }
        guard artifactAuthorityGeneration != UInt64.max else {
'''
)

one(
'''            self.lastDiagnostic = "Connection attempt timed out and was cancelled."
            self.enqueueInterruption("connection attempt timed out")
''',
'''            if self.observationBoundaryBlocksArtifactMutation {
                // The timeout happened outside the admitted artifact horizon. Retire
                // transport state only; do not append interruption evidence or revoke
                // the authority currently sealing H.
                self.connectionTimeoutTask = nil
                self.selectedTargetCancellationPending = true
                _ = self.targetState.retireActiveAttempt()
                peripheral.delegate = nil
                self.activePeripheral = nil
                self.clearAcquisitionObjects()
                self.connectionPhase = .idle
                self.centralManager.cancelPeripheralConnection(peripheral)
                return
            }

            self.lastDiagnostic = "Connection attempt timed out and was cancelled."
            self.enqueueInterruption("connection attempt timed out")
'''
)

one(
'''        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        activePeripheral = peripheral
        peripheral.delegate = self
        connectionPhase = .connected(identifier)

        do {
''',
'''        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil

        if observationBoundaryBlocksArtifactMutation {
            // A connect callback that arrives after H admission belongs to transport
            // cleanup, not a new finite-acquisition epoch inside the sealed artifact.
            selectedTargetCancellationPending = true
            _ = targetState.retireActiveAttempt()
            peripheral.delegate = nil
            activePeripheral = nil
            clearAcquisitionObjects()
            connectionPhase = .idle
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        activePeripheral = peripheral
        peripheral.delegate = self
        connectionPhase = .connected(identifier)

        do {
'''
)

one(
'''        let disposition = targetState.completeFailedConnection(from: identifier)
        guard disposition != .ignored else { return }

        if targetState.selectedTargetIdentifier == identifier {
''',
'''        let disposition = targetState.completeFailedConnection(from: identifier)
        guard disposition != .ignored else { return }

        if observationBoundaryBlocksArtifactMutation {
            // This terminal transport callback arrived outside H. Consume transport
            // state only and preserve the authority of the closing artifact.
            selectedTargetCancellationPending = false
            if case .active = disposition {
                clearActiveConnectionState(for: identifier)
            }
            return
        }

        if targetState.selectedTargetIdentifier == identifier {
'''
)

controller.write_text(s)

tests = Path('Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/ForegroundCoreBluetoothCaptureControllerTerminalTransportIsolationTests.swift')
t = tests.read_text()
insert = r'''

    @Test("Horizon-closing reconnect cannot replace artifact authority")
    func reconnectAdmissionStopsBeforeAuthorityReplacementWhileHorizonCloses() throws {
        let source = try Self.controllerSource()
        let method = try Self.section(
            in: source,
            from: "    public func connect(\n        to peripheralIdentifier: UUID,",
            to: "    /// Cancels the active attempt"
        )

        let horizonFence = try Self.offset(of: "observationBoundaryBlocksArtifactMutation", in: method)
        let authorityAdvance = try Self.offset(of: "advanceArtifactAuthority()", in: method)
        #expect(horizonFence < authorityAdvance)
    }

    @Test("late didConnect cannot restart finite acquisition after Horizon admission")
    func connectedCallbackStopsBeforeDiscoveryWhileHorizonCloses() throws {
        let source = try Self.controllerSource()
        let method = try Self.section(
            in: source,
            from: "    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {",
            to: "    public func centralManager(\n        _ central: CBCentralManager,\n        didFailToConnect peripheral: CBPeripheral,"
        )

        let horizonFence = try Self.offset(of: "observationBoundaryBlocksArtifactMutation", in: method)
        let discovery = try Self.offset(of: "beginDiscovery(on: peripheral)", in: method)
        #expect(horizonFence < discovery)
    }

    @Test("late failed connect cannot revoke authority after Horizon admission")
    func failedConnectionStopsBeforeAuthorityReplacementWhileHorizonCloses() throws {
        let source = try Self.controllerSource()
        let method = try Self.section(
            in: source,
            from: "    public func centralManager(\n        _ central: CBCentralManager,\n        didFailToConnect peripheral: CBPeripheral,",
            to: "    public func centralManager(\n        _ central: CBCentralManager,\n        didDisconnectPeripheral peripheral: CBPeripheral,"
        )

        let horizonFence = try Self.offset(of: "observationBoundaryBlocksArtifactMutation", in: method)
        let authorityAdvance = try Self.offset(of: "advanceArtifactAuthority()", in: method)
        #expect(horizonFence < authorityAdvance)
    }

    @Test("connection timeout cannot revoke authority after Horizon admission")
    func connectionTimeoutStopsBeforeAuthorityReplacementWhileHorizonCloses() throws {
        let source = try Self.controllerSource()
        let method = try Self.section(
            in: source,
            from: "    private func scheduleConnectionTimeout(for peripheral: CBPeripheral, nanoseconds: UInt64) {",
            to: "    private func currentAcquisitionWatchdogContext()"
        )

        let horizonFence = try Self.offset(of: "observationBoundaryBlocksArtifactMutation", in: method)
        let authorityAdvance = try Self.offset(of: "advanceArtifactAuthority()", in: method)
        #expect(horizonFence < authorityAdvance)
    }

    @Test("authority helper itself refuses replacement while Horizon owns the cutoff")
    func authorityAdvanceHasHorizonDefenseInDepth() throws {
        let source = try Self.controllerSource()
        let method = try Self.section(
            in: source,
            from: "    private func advanceArtifactAuthority() -> Bool {",
            to: "    private func currentArtifactAuthorityContext()"
        )

        let horizonFence = try Self.offset(of: "observationBoundaryBlocksArtifactMutation", in: method)
        let transition = try Self.offset(of: "artifactAuthorityFence.transition", in: method)
        #expect(horizonFence < transition)
    }
'''
if not t.endswith('\n}\n'):
    raise SystemExit('unexpected test file ending')
if 'Horizon-closing reconnect cannot replace artifact authority' in t:
    raise SystemExit('hardening tests already present')
t = t[:-3] + insert + '\n}\n'
tests.write_text(t)
