import Foundation

/// A narrow, fail-closed policy for associating one newly appearing connectable
/// CoreBluetooth candidate with an operator-controlled power-on experiment.
///
/// The caller owns the physical procedure and must provide candidate sets from
/// two distinct, fresh scan epochs: a powered-off baseline followed by a scan
/// after powering on only the intended device. This policy does not verify that
/// procedure, authenticate hardware, inspect names/RSSI, or assign any GATT,
/// Tuya, data-point, telemetry, or command meaning.
public enum PassiveBluetoothPowerOnCandidateAssociation: Sendable {
    public enum Resolution: Equatable, Sendable {
        /// Exactly one connectable CoreBluetooth identifier appeared after the
        /// operator-controlled power-on transition.
        ///
        /// This is association evidence for the experiment, not permanent or
        /// cryptographic scooter identity.
        case uniqueNewCandidate(UUID)

        /// No newly appearing connectable identifier was observed. The caller
        /// must not guess from name, RSSI, ordering, or a stale selection.
        case noNewCandidate

        /// More than one newly appearing connectable identifier was observed.
        /// The caller must fail closed rather than choose among them by signal,
        /// name, or presentation order.
        case ambiguousNewCandidates([UUID])
    }

    /// Resolves the set difference between two caller-supplied connectable
    /// candidate snapshots.
    ///
    /// Only identifiers present in `refreshedConnectableIdentifiers` and absent
    /// from `baselineConnectableIdentifiers` are considered newly appearing.
    /// Baseline candidates disappearing in the refreshed scan do not create
    /// positive evidence. Ambiguous identifiers are sorted canonically for
    /// deterministic presentation/testing only; sorting never selects a winner.
    public static func resolve(
        baselineConnectableIdentifiers: Set<UUID>,
        refreshedConnectableIdentifiers: Set<UUID>
    ) -> Resolution {
        let newIdentifiers = refreshedConnectableIdentifiers
            .subtracting(baselineConnectableIdentifiers)
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
