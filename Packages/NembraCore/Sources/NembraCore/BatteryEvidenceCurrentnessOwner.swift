import Synchronization

/// Process-local revocation authority for live battery currentness.
///
/// Receipt chronology remains value data in `BatteryEvidenceStreamValidator`, but live
/// currentness must not. A validator copy captured at R1 must observe the same revocation when
/// the real chronology owner crosses a gap, consumes a newer receipt, or accepts R2.
///
/// The owner therefore carries one reference-backed generation. Copies may retain an old
/// generation reference, but they cannot recreate it after the owner rotates. No wall-clock
/// timeout or guessed device cadence participates in this decision.
final class BatteryEvidenceCurrentnessOwner: Sendable {
    final class Generation: Sendable {}

    struct Snapshot: Sendable {
        let acceptedReceiptIdentity: BatteryEvidenceReceiptIdentity?
        let acceptedUptimeNanoseconds: UInt64?
        let requiresContinuityBoundary: Bool
    }

    private struct State: Sendable {
        var generation: Generation
        var acceptedReceiptIdentity: BatteryEvidenceReceiptIdentity?
        var acceptedUptimeNanoseconds: UInt64?
        var requiresContinuityBoundary: Bool
    }

    private let state: Mutex<State>

    init() {
        state = Mutex(
            State(
                generation: Generation(),
                acceptedReceiptIdentity: nil,
                acceptedUptimeNanoseconds: nil,
                requiresContinuityBoundary: false
            )
        )
    }

    func generation() -> Generation {
        state.withLock { $0.generation }
    }

    /// Rotates currentness only when `generation` still owns this authority.
    /// A stale copy cannot invalidate or reclaim a newer owner's generation.
    func invalidateIfOwned(
        by generation: Generation,
        requiresContinuityBoundary: Bool
    ) -> Generation? {
        state.withLock { state in
            guard state.generation === generation else { return nil }
            let replacement = Generation()
            state.generation = replacement
            state.acceptedReceiptIdentity = nil
            state.acceptedUptimeNanoseconds = nil
            state.requiresContinuityBoundary = requiresContinuityBoundary
            return replacement
        }
    }

    /// Publishes the exact receipt that is live-current for this generation.
    /// Fails if another copy already rotated the owner.
    func publishIfOwned(
        by generation: Generation,
        receiptIdentity: BatteryEvidenceReceiptIdentity,
        uptimeNanoseconds: UInt64,
        requiresContinuityBoundary: Bool
    ) -> Bool {
        state.withLock { state in
            guard state.generation === generation else { return false }
            state.acceptedReceiptIdentity = receiptIdentity
            state.acceptedUptimeNanoseconds = uptimeNanoseconds
            state.requiresContinuityBoundary = requiresContinuityBoundary
            return true
        }
    }

    func snapshotIfOwned(by generation: Generation) -> Snapshot? {
        state.withLock { state in
            guard state.generation === generation else { return nil }
            return Snapshot(
                acceptedReceiptIdentity: state.acceptedReceiptIdentity,
                acceptedUptimeNanoseconds: state.acceptedUptimeNanoseconds,
                requiresContinuityBoundary: state.requiresContinuityBoundary
            )
        }
    }

    func isCurrent(
        generation: Generation,
        receiptIdentity: BatteryEvidenceReceiptIdentity,
        uptimeNanoseconds: UInt64
    ) -> Bool {
        guard let snapshot = snapshotIfOwned(by: generation) else { return false }
        return snapshot.requiresContinuityBoundary == false
            && snapshot.acceptedReceiptIdentity == receiptIdentity
            && snapshot.acceptedUptimeNanoseconds == uptimeNanoseconds
    }
}

/// Opaque, non-Codable proof that an accepted anchor was minted by one live currentness owner.
/// Construction is intentionally file/package-internal; ordinary callers cannot fabricate it
/// from receipt metadata alone.
struct BatteryEvidenceCurrentnessLease: Equatable, Sendable {
    let owner: BatteryEvidenceCurrentnessOwner
    let generation: BatteryEvidenceCurrentnessOwner.Generation

    static func == (
        lhs: BatteryEvidenceCurrentnessLease,
        rhs: BatteryEvidenceCurrentnessLease
    ) -> Bool {
        lhs.owner === rhs.owner && lhs.generation === rhs.generation
    }

    func isCurrent(
        receiptIdentity: BatteryEvidenceReceiptIdentity,
        uptimeNanoseconds: UInt64
    ) -> Bool {
        owner.isCurrent(
            generation: generation,
            receiptIdentity: receiptIdentity,
            uptimeNanoseconds: uptimeNanoseconds
        )
    }
}
