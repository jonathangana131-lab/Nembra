/// Opaque software identity for one observation-boundary queue-gate producer.
///
/// Queue transaction revisions are intentionally local monotonic counters. They
/// therefore cannot, by themselves, distinguish two independently constructed
/// queue gates that happen to mint the same revision/cutoff/authority values.
/// This token supplies the missing producer scope without exposing a caller-
/// chosen scalar that can be reconstructed later.
///
/// Identity is reference-based on purpose:
/// - copying a value-type queue gate preserves the same producer token;
/// - constructing a genuinely fresh queue-gate lifecycle must mint a new token;
/// - equality never falls back to revision, cutoff, artifact authority, UUID text,
///   or another reconstructable field.
///
/// The token is process-local software chronology authority only. It is not
/// persisted capture identity, CoreBluetooth peripheral identity, scooter
/// authentication, RF provenance, or physical AOVOPRO ES80 evidence.
final class PassiveCoreBluetoothObservationBoundaryQueueProducerIdentity:
    Equatable,
    Hashable,
    Sendable
{
    private init() {}

    /// Mints a producer identity for one fresh queue-gate lifecycle.
    ///
    /// Package code that owns gate construction may call this once and retain the
    /// returned object for the entire copied/mutated lifetime of that gate.
    static func mint() -> PassiveCoreBluetoothObservationBoundaryQueueProducerIdentity {
        PassiveCoreBluetoothObservationBoundaryQueueProducerIdentity()
    }

    static func == (
        lhs: PassiveCoreBluetoothObservationBoundaryQueueProducerIdentity,
        rhs: PassiveCoreBluetoothObservationBoundaryQueueProducerIdentity
    ) -> Bool {
        lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
