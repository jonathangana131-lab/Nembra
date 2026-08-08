from pathlib import Path

path = Path("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift")
source = path.read_text()
old = '''        if observationBoundaryBlocksArtifactMutation {
            // This terminal transport callback arrived outside H. Consume transport
            // state only and preserve the authority of the closing artifact.
            selectedTargetCancellationPending = false
            if case .active = disposition {
                clearActiveConnectionState(for: identifier)
            }
            return
        }
'''
new = '''        if observationBoundaryBlocksArtifactMutation {
            // This terminal transport callback arrived outside H. Consume transport
            // state only and preserve the authority of the closing artifact. A failed
            // connect is also a real same-attempt terminal callback, so once target-state
            // quarantine is released it must drive the same fresh-session completion seam
            // as disconnect rather than leaving a finalized capture stuck terminal.
            selectedTargetCancellationPending = false
            if case .active = disposition {
                clearActiveConnectionState(for: identifier)
            }
            do {
                _ = try completeTerminalFreshTargetSessionIfReady()
            } catch {
                failCapture(error)
            }
            return
        }
'''
count = source.count(old)
if count != 1:
    raise SystemExit(f"expected exactly one didFailToConnect terminal branch, found {count}")
updated = source.replace(old, new, 1)
start = updated.index("didFailToConnect peripheral: CBPeripheral")
end = updated.index("didDisconnectPeripheral peripheral: CBPeripheral", start)
callback = updated[start:end]
completion = callback.index("completeTerminalFreshTargetSessionIfReady()")
disposition = callback.index("targetState.completeFailedConnection(from: identifier)")
if disposition >= completion:
    raise SystemExit("fresh recovery must remain downstream of terminal disposition consumption")
path.write_text(updated)
