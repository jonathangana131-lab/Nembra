from pathlib import Path

p = Path('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift')
s = p.read_text()
old = '''            let recordedHorizon = try await horizonAdmission.recordBoundary(on: recorder)
            // No actor suspension may occur between the authority-fenced recorder
            // return and typed queue commit. If that exact commit loses lifecycle
            // authority, #507's producer-issued recorded-H token quarantines the
            // durable H without fabricating terminal/frozen success.
            let committedHorizon: PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedHorizonBoundary
'''
new = '''            let horizonMutationOutcome = try await horizonAdmission
                .recordBoundaryWithMutationOutcome(on: recorder)
            let recordedHorizon: PassiveCoreBluetoothObservationBoundaryTransactionDecision.RecordedHorizonBoundary
            switch horizonMutationOutcome {
            case let .recorded(boundary):
                recordedHorizon = boundary
            case let .rejectedBeforeMutation(rejection):
                // Canonical authority was revoked before the recorder mutation body
                // executed. Preserve Ready as the furthest durable boundary and
                // quarantine the exact attempted H transaction as zero-mutation
                // lifecycle provenance. Do not fabricate H evidence.
                try observationBoundaryQueueGate.abortUncommittedHorizon(after: rejection)
                throw ControllerError.targetSessionChanged
            }

            // No actor suspension may occur between the authority-fenced recorder
            // return and typed queue commit. If that exact commit loses lifecycle
            // authority, #507's producer-issued recorded-H token quarantines the
            // durable H without fabricating terminal/frozen success.
            let committedHorizon: PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedHorizonBoundary
'''
count = s.count(old)
if count != 1:
    raise SystemExit(f'expected one Horizon mutation seam, found {count}')
s = s.replace(old, new, 1)
if 'let recordedHorizon = try await horizonAdmission.recordBoundary(on: recorder)' in s:
    raise SystemExit('raw Horizon recorder mutation bypass remains')
p.write_text(s)
