import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth post-horizon queue retirement")
struct PassiveCoreBluetoothPostHorizonQueueRetirementTests {
    private let authority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 17,
        authorityGeneration: 29
    )

    @Test("retirement proof requires the exact terminal horizon transaction")
    func retirementProofRequiresTerminalHorizon() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try gate.begin(
            .finiteAcquisitionReady,
            through: 2,
            authority: authority
        )

        let readyError = capturedRetirementStateError {
            _ = try PassiveCoreBluetoothPostHorizonQueueRetirement(
                horizonTransaction: ready,
                terminalGate: gate
            )
        }
        #expect(readyError == .horizonTransactionRequired)

        try gate.markBoundaryRecorded(
            ready,
            lastProcessedQueueSequence: 2,
            currentAuthority: authority
        )
        let horizon = try gate.begin(
            .observationHorizon,
            through: 5,
            processedThrough: 2,
            authority: authority
        )
        try gate.markBoundaryRecorded(
            horizon,
            lastProcessedQueueSequence: 5,
            currentAuthority: authority
        )

        let preFreezeError = capturedRetirementStateError {
            _ = try PassiveCoreBluetoothPostHorizonQueueRetirement(
                horizonTransaction: horizon,
                terminalGate: gate
            )
        }
        #expect(preFreezeError == .terminalTransactionMismatch)

        try gate.completeHorizonArtifactFreeze(
            horizon,
            currentAuthority: authority
        )
        let proof = try PassiveCoreBluetoothPostHorizonQueueRetirement(
            horizonTransaction: horizon,
            terminalGate: gate
        )
        #expect(proof.horizonQueueCutoff == 5)
        #expect(proof.retiredAuthority == authority)
    }

    @Test("only exact-authority post-horizon evidence becomes retirement-eligible")
    func retirementClassificationPreservesOtherAuthorities() throws {
        let (gate, horizon) = try terminalGate(horizonCutoff: 8)
        let proof = try PassiveCoreBluetoothPostHorizonQueueRetirement(
            horizonTransaction: horizon,
            terminalGate: gate
        )

        let afterHorizon = PassiveCoreBluetoothPostHorizonQueueRetirement.QueuedEvidenceIdentity(
            queueSequence: 9,
            authority: authority
        )
        let atHorizon = PassiveCoreBluetoothPostHorizonQueueRetirement.QueuedEvidenceIdentity(
            queueSequence: 8,
            authority: authority
        )
        let beforeHorizon = PassiveCoreBluetoothPostHorizonQueueRetirement.QueuedEvidenceIdentity(
            queueSequence: 3,
            authority: authority
        )
        let futureAuthority = PassiveCoreBluetoothPostHorizonQueueRetirement.QueuedEvidenceIdentity(
            queueSequence: 10,
            authority: PassiveCoreBluetoothArtifactAuthorityContext(
                targetSessionGeneration: authority.targetSessionGeneration,
                authorityGeneration: authority.authorityGeneration + 1
            )
        )
        let differentTargetSession = PassiveCoreBluetoothPostHorizonQueueRetirement.QueuedEvidenceIdentity(
            queueSequence: 11,
            authority: PassiveCoreBluetoothArtifactAuthorityContext(
                targetSessionGeneration: authority.targetSessionGeneration + 1,
                authorityGeneration: authority.authorityGeneration
            )
        )

        #expect(
            try proof.disposition(for: afterHorizon, terminalGate: gate)
                == .retirePostHorizonEvidence
        )
        #expect(
            try proof.disposition(for: atHorizon, terminalGate: gate)
                == .blocksRetirement
        )
        #expect(
            try proof.disposition(for: beforeHorizon, terminalGate: gate)
                == .blocksRetirement
        )
        #expect(
            try proof.disposition(for: futureAuthority, terminalGate: gate)
                == .preserveDifferentAuthority
        )
        #expect(
            try proof.disposition(for: differentTargetSession, terminalGate: gate)
                == .preserveDifferentAuthority
        )
    }

    @Test("remaining old authority blocks lifecycle reopen after retirement pass")
    func remainingRetiredAuthorityFailsClosed() throws {
        let (gate, horizon) = try terminalGate(horizonCutoff: 5)
        let proof = try PassiveCoreBluetoothPostHorizonQueueRetirement(
            horizonTransaction: horizon,
            terminalGate: gate
        )
        let oldPostHorizon = PassiveCoreBluetoothPostHorizonQueueRetirement.QueuedEvidenceIdentity(
            queueSequence: 6,
            authority: authority
        )
        let oldPrefix = PassiveCoreBluetoothPostHorizonQueueRetirement.QueuedEvidenceIdentity(
            queueSequence: 5,
            authority: authority
        )

        let postHorizonError = capturedRetirementStateError {
            try proof.validateQueueCanReopen(
                remainingQueuedEvidence: [oldPostHorizon],
                terminalGate: gate
            )
        }
        #expect(
            postHorizonError == .retiredAuthorityStillQueued(queueSequence: 6)
        )

        let prefixError = capturedRetirementStateError {
            try proof.validateQueueCanReopen(
                remainingQueuedEvidence: [oldPrefix],
                terminalGate: gate
            )
        }
        #expect(prefixError == .retiredAuthorityStillQueued(queueSequence: 5))
    }

    @Test("queue may reopen only after exact retired authority is absent")
    func retirementLeavesFutureAuthorityUntouched() throws {
        let (gate, horizon) = try terminalGate(horizonCutoff: 5)
        let proof = try PassiveCoreBluetoothPostHorizonQueueRetirement(
            horizonTransaction: horizon,
            terminalGate: gate
        )

        let queued = [
            PassiveCoreBluetoothPostHorizonQueueRetirement.QueuedEvidenceIdentity(
                queueSequence: 6,
                authority: authority
            ),
            PassiveCoreBluetoothPostHorizonQueueRetirement.QueuedEvidenceIdentity(
                queueSequence: 7,
                authority: PassiveCoreBluetoothArtifactAuthorityContext(
                    targetSessionGeneration: authority.targetSessionGeneration,
                    authorityGeneration: authority.authorityGeneration + 1
                )
            ),
            PassiveCoreBluetoothPostHorizonQueueRetirement.QueuedEvidenceIdentity(
                queueSequence: 8,
                authority: PassiveCoreBluetoothArtifactAuthorityContext(
                    targetSessionGeneration: authority.targetSessionGeneration + 1,
                    authorityGeneration: authority.authorityGeneration + 1
                )
            )
        ]

        var remaining: [PassiveCoreBluetoothPostHorizonQueueRetirement.QueuedEvidenceIdentity] = []
        for item in queued {
            let disposition = try proof.disposition(for: item, terminalGate: gate)
            if disposition != .retirePostHorizonEvidence {
                remaining.append(item)
            }
        }

        #expect(remaining.map(\.queueSequence) == [7, 8])
        try proof.validateQueueCanReopen(
            remainingQueuedEvidence: remaining,
            terminalGate: gate
        )
    }

    @Test("proof cannot outlive the exact terminal gate transaction")
    func staleProofCannotAuthorizeAnotherGate() throws {
        let (gate, horizon) = try terminalGate(horizonCutoff: 5)
        let proof = try PassiveCoreBluetoothPostHorizonQueueRetirement(
            horizonTransaction: horizon,
            terminalGate: gate
        )

        let changedAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration,
            authorityGeneration: authority.authorityGeneration + 1
        )
        var otherGate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let otherReady = try otherGate.begin(
            .finiteAcquisitionReady,
            through: 2,
            authority: changedAuthority
        )
        try otherGate.markBoundaryRecorded(
            otherReady,
            lastProcessedQueueSequence: 2,
            currentAuthority: changedAuthority
        )
        let otherHorizon = try otherGate.begin(
            .observationHorizon,
            through: 5,
            processedThrough: 2,
            authority: changedAuthority
        )
        try otherGate.markBoundaryRecorded(
            otherHorizon,
            lastProcessedQueueSequence: 5,
            currentAuthority: changedAuthority
        )
        try otherGate.completeHorizonArtifactFreeze(
            otherHorizon,
            currentAuthority: changedAuthority
        )

        let candidate = PassiveCoreBluetoothPostHorizonQueueRetirement.QueuedEvidenceIdentity(
            queueSequence: 6,
            authority: authority
        )
        let dispositionError = capturedRetirementStateError {
            _ = try proof.disposition(for: candidate, terminalGate: otherGate)
        }
        #expect(dispositionError == .terminalTransactionMismatch)

        let reopenError = capturedRetirementStateError {
            try proof.validateQueueCanReopen(
                remainingQueuedEvidence: [],
                terminalGate: otherGate
            )
        }
        #expect(reopenError == .terminalTransactionMismatch)
    }

    @Test("maximum queue cutoff cannot manufacture post-horizon retirement")
    func maximumCutoffHasNoPostHorizonSequence() throws {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let ready = try gate.begin(
            .finiteAcquisitionReady,
            through: UInt64.max,
            authority: authority
        )
        try gate.markBoundaryRecorded(
            ready,
            lastProcessedQueueSequence: UInt64.max,
            currentAuthority: authority
        )
        let horizon = try gate.begin(
            .observationHorizon,
            through: UInt64.max,
            processedThrough: UInt64.max,
            authority: authority
        )
        try gate.markBoundaryRecorded(
            horizon,
            lastProcessedQueueSequence: UInt64.max,
            currentAuthority: authority
        )
        try gate.completeHorizonArtifactFreeze(
            horizon,
            currentAuthority: authority
        )

        let proof = try PassiveCoreBluetoothPostHorizonQueueRetirement(
            horizonTransaction: horizon,
            terminalGate: gate
        )
        let finalSequence = PassiveCoreBluetoothPostHorizonQueueRetirement.QueuedEvidenceIdentity(
            queueSequence: UInt64.max,
            authority: authority
        )

        #expect(
            try proof.disposition(for: finalSequence, terminalGate: gate)
                == .blocksRetirement
        )
    }

    private func terminalGate(
        horizonCutoff: UInt64
    ) throws -> (
        PassiveCoreBluetoothObservationBoundaryQueueGate,
        PassiveCoreBluetoothObservationBoundaryQueueGate.Transaction
    ) {
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()
        let readyCutoff = min(horizonCutoff, 2)
        let ready = try gate.begin(
            .finiteAcquisitionReady,
            through: readyCutoff,
            authority: authority
        )
        try gate.markBoundaryRecorded(
            ready,
            lastProcessedQueueSequence: readyCutoff,
            currentAuthority: authority
        )
        let horizon = try gate.begin(
            .observationHorizon,
            through: horizonCutoff,
            processedThrough: readyCutoff,
            authority: authority
        )
        try gate.markBoundaryRecorded(
            horizon,
            lastProcessedQueueSequence: horizonCutoff,
            currentAuthority: authority
        )
        try gate.completeHorizonArtifactFreeze(
            horizon,
            currentAuthority: authority
        )
        return (gate, horizon)
    }
}

private func capturedRetirementStateError<T>(
    _ operation: () throws -> T
) -> PassiveCoreBluetoothPostHorizonQueueRetirement.StateError? {
    do {
        _ = try operation()
        return nil
    } catch let error as PassiveCoreBluetoothPostHorizonQueueRetirement.StateError {
        return error
    } catch {
        return nil
    }
}
