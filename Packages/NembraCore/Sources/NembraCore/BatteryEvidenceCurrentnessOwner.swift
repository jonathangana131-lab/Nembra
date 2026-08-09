import Foundation

/// Process-local revocation authority for live battery currentness.
///
/// Receipt chronology remains value data in `BatteryEvidenceStreamValidator`, but live
/// currentness must not. A validator copy captured at R1 must observe the same revocation when
/// the real chronology owner crosses a gap, consumes a newer receipt, or accepts R2.
///
/// The owner therefore carries one reference-backed generation. Copies may retain an old
/// generation handle, but they cannot recreate it after the owner rotates. Leases hold only a
/// weak handle back to this owner, so retaining an anchor/estimate cannot keep its own live
/// authority alive after the real stream/validator lineage is destroyed.
///
/// No wall-clock timeout or guessed device cadence participates in this decision.
final class BatteryEvidenceCurrentnessOwner: @unchecked Sendable {
    final class Generation: Sendable {}

    /// Shared identity object retained by leases without retaining the owner itself.
    /// Weak-reference mutation is runtime-managed; callers only observe it through owner methods.
    final class LeaseHandle: @unchecked Sendable {
        weak var owner: BatteryEvidenceCurrentnessOwner?
    }

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

    // NembraCore still supports macOS 12 for package validation. `Synchronization.Mutex`
    // requires macOS 15, so use the long-supported Foundation lock while preserving the same
    // process-local critical-section semantics. All mutable state is accessed only through
    // `withState`, which is why this owner is explicitly @unchecked Sendable.
    private let lock = NSLock()
    private var state: State
    let leaseHandle: LeaseHandle

    init() {
        let handle = LeaseHandle()
        state = State(
            generation: Generation(),
            acceptedReceiptIdentity: nil,
            acceptedUptimeNanoseconds: nil,
            requiresContinuityBoundary: false
        )
        leaseHandle = handle
        handle.owner = self
    }

    private func withState<Result>(_ body: (inout State) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }

    func generation() -> Generation {
        withState { $0.generation }
    }

    /// Rotates currentness only when `generation` still owns this authority.
    /// A stale copy cannot invalidate or reclaim a newer owner's generation.
    func invalidateIfOwned(
        by generation: Generation,
        requiresContinuityBoundary: Bool
    ) -> Generation? {
        withState { state in
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
        withState { state in
            guard state.generation === generation else { return false }
            state.acceptedReceiptIdentity = receiptIdentity
            state.acceptedUptimeNanoseconds = uptimeNanoseconds
            state.requiresContinuityBoundary = requiresContinuityBoundary
            return true
        }
    }

    func snapshotIfOwned(by generation: Generation) -> Snapshot? {
        withState { state in
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
///
/// The lease strongly retains only the owner's shared identity handle plus the generation. The
/// handle points weakly to the owner, so an orphaned retained anchor/estimate automatically becomes
/// non-current when no stream/validator lineage still owns that authority.
struct BatteryEvidenceCurrentnessLease: Equatable, Sendable {
    let ownerHandle: BatteryEvidenceCurrentnessOwner.LeaseHandle
    let generation: BatteryEvidenceCurrentnessOwner.Generation

    static func == (
        lhs: BatteryEvidenceCurrentnessLease,
        rhs: BatteryEvidenceCurrentnessLease
    ) -> Bool {
        lhs.ownerHandle === rhs.ownerHandle && lhs.generation === rhs.generation
    }

    func isCurrent(
        receiptIdentity: BatteryEvidenceReceiptIdentity,
        uptimeNanoseconds: UInt64
    ) -> Bool {
        guard let owner = ownerHandle.owner else { return false }
        return owner.isCurrent(
            generation: generation,
            receiptIdentity: receiptIdentity,
            uptimeNanoseconds: uptimeNanoseconds
        )
    }
}
