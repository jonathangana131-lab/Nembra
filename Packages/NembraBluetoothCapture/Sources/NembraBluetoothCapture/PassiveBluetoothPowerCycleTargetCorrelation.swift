import Foundation

/// Package-issued local ordering for one candidate-observation window.
///
/// This sequence is deliberately **not** a CoreBluetooth callback generation ID.
/// `didDiscover` does not expose the scan request that originated a callback, so
/// incrementing a local counter cannot prove that a delayed callback belongs to a
/// later scan. The initializer is not public so app/UI code cannot mint ordering
/// tokens and turn two arbitrary catalogs into authoritative physical evidence.
public struct PassiveBluetoothCandidateObservationWindowSequence: Equatable, Hashable, Sendable {
    public let rawValue: UInt64

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

/// Immutable candidate catalog from one package-issued observation window.
///
/// Construction is intentionally package-internal. A future live producer may
/// expose snapshots only after its CoreBluetooth lifecycle policy can honestly
/// establish a bounded observation window and isolation from the prior window.
/// A sequence number alone never establishes that isolation.
///
/// This remains presentation/research targeting evidence only. It is not a
/// durable scooter identity and does not prove any candidate is an AOVOPRO ES80.
public struct PassiveBluetoothCandidateObservationSnapshot: Equatable, Sendable {
    public struct Candidate: Equatable, Sendable {
        public let id: UUID
        public let isConnectable: Bool?

        init(id: UUID, isConnectable: Bool?) {
            self.id = id
            self.isConnectable = isConnectable
        }
    }

    public let windowSequence: PassiveBluetoothCandidateObservationWindowSequence
    public let candidates: [Candidate]

    init(
        windowSequence: PassiveBluetoothCandidateObservationWindowSequence,
        candidates: [Candidate]
    ) throws {
        var seen = Set<UUID>()
        for candidate in candidates {
            guard seen.insert(candidate.id).inserted else {
                throw PassiveBluetoothCandidateObservationSnapshotError
                    .duplicatePeripheralIdentifier(candidate.id)
            }
        }

        self.windowSequence = windowSequence
        self.candidates = candidates.sorted {
            $0.id.uuidString < $1.id.uuidString
        }
    }
}

enum PassiveBluetoothCandidateObservationSnapshotError: Error, Equatable, Sendable {
    case duplicatePeripheralIdentifier(UUID)
}

/// Evidence summary for the minimal physical target-correlation experiment:
/// observe nearby candidates with the intended scooter OFF, then compare against
/// a separately established later observation window after the operator powers
/// only that scooter ON.
///
/// The set-difference algorithm does not prove the observation windows were
/// isolated. That authority belongs to the package producer that constructs the
/// otherwise non-public snapshots. Until the live CoreBluetooth lifecycle can
/// prove that boundary, app code cannot drive this report honestly.
///
/// A single delta candidate is still only a physical-correlation candidate for
/// explicit operator selection. It is not authentication, permanent identity,
/// GATT/protocol verification, or permission to issue vehicle commands.
public struct PassiveBluetoothPowerCycleTargetCorrelationReport: Equatable, Sendable {
    public enum Disposition: Equatable, Sendable {
        /// The powered-on snapshot is not locally ordered after the baseline.
        /// This rejects accidental reuse/backward inputs but does not itself
        /// prove CoreBluetooth callback isolation between otherwise later values.
        case invalidObservationWindowOrder

        /// No newly selectable candidate appeared after the intended power-on.
        case noNewSelectableCandidate

        /// More than one newly selectable candidate appeared; guessing is banned.
        case ambiguousNewSelectableCandidates([UUID])

        /// Exactly one newly selectable UUID was absent from the complete OFF
        /// snapshot. This may be offered for explicit operator selection only.
        case singleNewSelectableCandidate(UUID)
    }

    public let baselineWindowSequence: PassiveBluetoothCandidateObservationWindowSequence
    public let poweredOnWindowSequence: PassiveBluetoothCandidateObservationWindowSequence

    /// Every peripheral UUID observed during the OFF baseline, irrespective of
    /// connectability. This prevents a previously sighted device from becoming
    /// "new" merely because its connectability metadata changed later.
    public let baselineObservedIdentifiers: [UUID]

    /// Powered-on candidates that are not explicitly marked non-connectable.
    /// Unknown connectability remains potentially selectable because the current
    /// controller also fails closed only on an explicit `false` value.
    public let poweredOnSelectableIdentifiers: [UUID]

    /// Powered-on selectable UUIDs absent from the entire OFF baseline.
    public let newSelectableIdentifiers: [UUID]
    public let disposition: Disposition

    fileprivate init(
        baselineWindowSequence: PassiveBluetoothCandidateObservationWindowSequence,
        poweredOnWindowSequence: PassiveBluetoothCandidateObservationWindowSequence,
        baselineObservedIdentifiers: [UUID],
        poweredOnSelectableIdentifiers: [UUID],
        newSelectableIdentifiers: [UUID],
        disposition: Disposition
    ) {
        self.baselineWindowSequence = baselineWindowSequence
        self.poweredOnWindowSequence = poweredOnWindowSequence
        self.baselineObservedIdentifiers = baselineObservedIdentifiers
        self.poweredOnSelectableIdentifiers = poweredOnSelectableIdentifiers
        self.newSelectableIdentifiers = newSelectableIdentifiers
        self.disposition = disposition
    }
}

public enum PassiveBluetoothPowerCycleTargetCorrelation {
    /// Compare two package-issued observation snapshots without using names,
    /// RSSI, UUID prefixes, or any guessed product signature.
    ///
    /// The caller cannot publicly construct snapshots or local sequence values.
    /// This intentionally prevents app/UI code from manufacturing apparent window
    /// authority. The future snapshot producer must separately prove its bounded
    /// CoreBluetooth observation/isolation policy; the sequence check below is
    /// only a local ordering sanity check and never callback provenance.
    public static func assess(
        baseline: PassiveBluetoothCandidateObservationSnapshot,
        poweredOn: PassiveBluetoothCandidateObservationSnapshot
    ) -> PassiveBluetoothPowerCycleTargetCorrelationReport {
        let baselineObserved = sortedIdentifiers(
            Set(baseline.candidates.map(\.id))
        )
        let poweredOnSelectable = sortedIdentifiers(
            Set(
                poweredOn.candidates
                    .filter { $0.isConnectable != false }
                    .map(\.id)
            )
        )

        guard poweredOn.windowSequence.rawValue > baseline.windowSequence.rawValue else {
            return .init(
                baselineWindowSequence: baseline.windowSequence,
                poweredOnWindowSequence: poweredOn.windowSequence,
                baselineObservedIdentifiers: baselineObserved,
                poweredOnSelectableIdentifiers: poweredOnSelectable,
                newSelectableIdentifiers: [],
                disposition: .invalidObservationWindowOrder
            )
        }

        let baselineSet = Set(baselineObserved)
        let newSelectable = poweredOnSelectable.filter {
            !baselineSet.contains($0)
        }

        let disposition: PassiveBluetoothPowerCycleTargetCorrelationReport.Disposition
        switch newSelectable.count {
        case 0:
            disposition = .noNewSelectableCandidate
        case 1:
            disposition = .singleNewSelectableCandidate(newSelectable[0])
        default:
            disposition = .ambiguousNewSelectableCandidates(newSelectable)
        }

        return .init(
            baselineWindowSequence: baseline.windowSequence,
            poweredOnWindowSequence: poweredOn.windowSequence,
            baselineObservedIdentifiers: baselineObserved,
            poweredOnSelectableIdentifiers: poweredOnSelectable,
            newSelectableIdentifiers: newSelectable,
            disposition: disposition
        )
    }

    private static func sortedIdentifiers(_ identifiers: Set<UUID>) -> [UUID] {
        identifiers.sorted { $0.uuidString < $1.uuidString }
    }
}
