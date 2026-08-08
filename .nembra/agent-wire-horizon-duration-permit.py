from pathlib import Path

controller = Path('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift')
s = controller.read_text()

def one(old: str, new: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f'expected exactly one match, got {count}: {old[:140]!r}')
    s = s.replace(old, new, 1)

one(
'''    public var canFinalizeObservationHorizon: Bool {
        guard hasCompleteTargetEvidence,
              !artifactReadBarrier.isActive,
              observationBoundaryTask == nil,
              case .observing = observationBoundaryQueueGate.phase,
              let committedReadyEpoch else { return false }
        return committedReadyEpoch.authority == artifactAuthorityFence.currentAuthority
    }
''',
'''    public var canFinalizeObservationHorizon: Bool {
        guard hasCompleteTargetEvidence,
              !artifactReadBarrier.isActive,
              observationBoundaryTask == nil,
              case .observing = observationBoundaryQueueGate.phase,
              let committedReadyEpoch,
              committedReadyEpoch.authority == artifactAuthorityFence.currentAuthority else {
            return false
        }

        // Product eligibility mirrors the trusted Experiment One procedure clock,
        // but this descriptive status is never mutation authority. Finalization
        // still obtains a producer-issued Permit immediately before H allocation.
        if case .eligible = PassiveCoreBluetoothObservationHorizonMinimumDurationGate
            .currentExperimentOneStatus(for: committedReadyEpoch) {
            return true
        }
        return false
    }
'''
)

one(
'''        let horizonAdmission = try committedReadyEpoch.beginHorizon(
            queueCutoff: lastEnqueuedEventSequence,
            processedThrough: lastProcessedEventSequence,
            gate: &observationBoundaryQueueGate
        )
''',
'''        // H cannot be allocated from Ready merely because the queue is drained.
        // The producer samples trusted monotonic uptime here and issues a Permit
        // only after the fixed Experiment One Ready -> H minimum has elapsed.
        let durationPermit = try PassiveCoreBluetoothObservationHorizonMinimumDurationGate
            .authorizeExperimentOneHorizon(for: committedReadyEpoch)
        let horizonAdmission = try durationPermit.beginHorizon(
            queueCutoff: lastEnqueuedEventSequence,
            processedThrough: lastProcessedEventSequence,
            gate: &observationBoundaryQueueGate
        )
'''
)

# The controller must no longer bypass the producer by directly consuming Ready.
if 'committedReadyEpoch.beginHorizon(' in s:
    raise SystemExit('raw committed Ready -> Horizon bypass remains in foreground controller')

controller.write_text(s)
