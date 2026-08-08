from pathlib import Path

p = Path('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift')
s = p.read_text()

def one(old: str, new: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f'expected one match, got {count}: {old[:120]!r}')
    s = s.replace(old, new, 1)

# Broad discovery is evidence-producing for the selected target. Once H is admitted,
# the accepted artifact interval is closed, so stop before callback clocks/catalog/GATT
# evidence can be attributed to that closing recorder.
one(
'''        ) else { return }

        let receipt = callbackReceipt()
        let normalizedRSSI = DiscoveredPeripheral.normalizedRSSI(RSSI.intValue)
''',
'''        ) else { return }
        guard !observationBoundaryBlocksArtifactMutation else { return }

        let receipt = callbackReceipt()
        let normalizedRSSI = DiscoveredPeripheral.normalizedRSSI(RSSI.intValue)
'''
)

# Move didConnect's H fence ahead of connection-timeout/provenance mutation while
# preserving transport cancellation cleanup.
one(
'''        guard targetState.acceptsActiveCallback(from: identifier),
              targetState.selectedTargetIdentifier == identifier else { return }

        connectionTimeoutTask?.cancel()
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
''',
'''        guard targetState.acceptsActiveCallback(from: identifier),
              targetState.selectedTargetIdentifier == identifier else { return }

        if observationBoundaryBlocksArtifactMutation {
            // A connect callback that arrives after H admission belongs to transport
            // cleanup, not a new finite-acquisition epoch inside the sealed artifact.
            connectionTimeoutTask?.cancel()
            connectionTimeoutTask = nil
            selectedTargetCancellationPending = true
            _ = targetState.retireActiveAttempt()
            peripheral.delegate = nil
            activePeripheral = nil
            clearAcquisitionObjects()
            connectionPhase = .idle
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }

        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        activePeripheral = peripheral
'''
)

# Every selected-target GATT callback must stop before error/failure/provenance/
# acquisition mutation once H owns the immutable queue cutoff.
markers = [
'''    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let receipt = callbackReceipt()
        guard targetState.acceptsActiveCallback(from: peripheral.identifier) else { return }
''',
'''    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverIncludedServicesFor service: CBService,
        error: Error?
    ) {
        let receipt = callbackReceipt()
        guard targetState.acceptsActiveCallback(from: peripheral.identifier) else { return }
''',
'''    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        let receipt = callbackReceipt()
        guard targetState.acceptsActiveCallback(from: peripheral.identifier) else { return }
''',
'''    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverDescriptorsFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let receipt = callbackReceipt()
        guard targetState.acceptsActiveCallback(from: peripheral.identifier) else { return }
''',
'''    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let receipt = callbackReceipt()
        guard targetState.acceptsActiveCallback(from: peripheral.identifier) else { return }
''',
'''    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let receipt = callbackReceipt()
        guard targetState.acceptsActiveCallback(from: peripheral.identifier) else { return }
'''
]
for marker in markers:
    replacement = marker + '        guard !observationBoundaryBlocksArtifactMutation else { return }\n'
    one(marker, replacement)

# Mechanical sanity: the six GATT callbacks plus broad discovery and didConnect must
# now carry the H fence, while didFailToConnect was hardened by the prior commit.
required_starts = [
    'didDiscover peripheral: CBPeripheral,',
    'didConnect peripheral: CBPeripheral)',
    'didFailToConnect peripheral: CBPeripheral,',
    'didDiscoverServices error: Error?',
    'didDiscoverIncludedServicesFor service: CBService,',
    'didDiscoverCharacteristicsFor service: CBService,',
    'didDiscoverDescriptorsFor characteristic: CBCharacteristic,',
    'didUpdateValueFor characteristic: CBCharacteristic,',
    'didUpdateNotificationStateFor characteristic: CBCharacteristic,'
]
for start in required_starts:
    idx = s.find(start)
    if idx < 0:
        raise SystemExit(f'missing callback marker: {start}')
    next_idx = s.find('\n    public func ', idx + 1)
    if next_idx < 0:
        next_idx = len(s)
    body = s[idx:next_idx]
    if 'observationBoundaryBlocksArtifactMutation' not in body:
        raise SystemExit(f'missing Horizon fence in callback: {start}')

p.write_text(s)
