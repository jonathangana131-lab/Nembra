from pathlib import Path

p = Path('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift')
s = p.read_text()

old = '''            let data = try await recorder.encodedJSON(prettyPrinted: prettyPrinted)
            try validateBoundaryAuthority(committedHorizon.authority)
            try committedHorizon.completeHorizonArtifactFreeze(on: &observationBoundaryQueueGate)
            retireQueuedEvidenceAfterTerminalHorizon()
'''
new = '''            let data: Data
            do {
                // Artifact materialization, final authority validation, and explicit
                // terminal freeze form one committed-H pre-freeze transaction. Any
                // failure here preserves H as durable incomplete evidence and must
                // quarantine the exact producer-issued committed H rather than retry
                // under a newer authority or fabricate terminal success.
                data = try await recorder.encodedJSON(prettyPrinted: prettyPrinted)
                try validateBoundaryAuthority(committedHorizon.authority)
                try committedHorizon.completeHorizonArtifactFreeze(
                    on: &observationBoundaryQueueGate
                )
            } catch {
                let artifactFailure = error
                do {
                    try observationBoundaryQueueGate.abortCommittedHorizonBeforeArtifactFreeze(
                        committedHorizon
                    )
                } catch {
                    // If exact quarantine itself cannot be established, surface that
                    // stronger lifecycle failure; the outer failCapture path remains
                    // closed and still never retires or terminalizes this epoch.
                    throw error
                }
                throw artifactFailure
            }
            retireQueuedEvidenceAfterTerminalHorizon()
'''
count = s.count(old)
if count != 1:
    raise SystemExit(f'expected exactly one committed-H artifact seam, found {count}')
s = s.replace(old, new, 1)
p.write_text(s)
