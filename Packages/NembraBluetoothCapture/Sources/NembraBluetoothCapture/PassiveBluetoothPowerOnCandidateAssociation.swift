import Foundation

/// A narrow, fail-closed policy for associating one newly appearing eligible
/// CoreBluetooth candidate with an operator-controlled power-on experiment.
///
/// The caller owns the physical procedure and candidate-admission policy and
/// must provide candidate sets from two distinct, fresh scan epochs: a
/// powered-off baseline followed by a scan after powering on only the intended
/// device. `Eligible` deliberately does not mean CoreBluetooth proved a missing
/// optional connectability advertisement field to be `true`.
///
/// This policy does not verify the physical procedure, authenticate hardware,
/// inspect names/RSSI, reinterpret advertisement metadata, or assign any GATT,
/// Tuya, data-point, telemetry, or command meaning.
public enum PassiveBluetoothPowerOnCandidateAssociation: Sendable {
    public enum Resolution: Equatable, Sendable {
        /// Exactly one eligible CoreBluetooth identifier appeared after the
        /// operator-controlled power-on transition.
        ///
        /// This is association evidence for the experiment, not permanent or
        /// cryptographic scooter identity.
        case uniqueNewCandidate(UUID)

        /// No newly appearing eligible identifier was observed. The caller must
        /// not guess from name, RSSI, ordering, or a stale selection.
        case noNewCandidate

        /// More than one newly appearing eligible identifier was observed. The
        /// caller must fail closed rather than choose among them by signal,
        /// name, or presentation order.
        case ambiguousNewCandidates([UUID])
    }

    /// Resolves the set difference between two caller-supplied eligible
    /// candidate snapshots.
    ///
    /// Only identifiers present in `refreshedEligibleIdentifiers` and absent
    /// from `baselineEligibleIdentifiers` are considered newly appearing.
    /// Baseline candidates disappearing in the refreshed scan do not create
    /// positive evidence. Ambiguous identifiers are sorted canonically for
    /// deterministic presentation/testing only; sorting never selects a winner.
    public static func resolve(
        baselineEligibleIdentifiers: Set<UUID>,
        refreshedEligibleIdentifiers: Set<UUID>
    ) -> Resolution {
        let newIdentifiers = refreshedEligibleIdentifiers
            .subtracting(baselineEligibleIdentifiers)
            .sorted { $0.uuidString < $1.uuidString }

        switch newIdentifiers.count {
        case 0:
            return .noNewCandidate
        case 1:
            return .uniqueNewCandidate(newIdentifiers[0])
        default:
            return .ambiguousNewCandidates(newIdentifiers)
        }
    }
}
