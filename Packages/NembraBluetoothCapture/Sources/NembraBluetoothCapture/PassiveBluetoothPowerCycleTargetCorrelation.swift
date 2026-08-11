import Foundation

/// Opaque software provenance for one producer/controller observation series.
///
/// This identity is package-issued and intentionally not a scooter identifier.
/// Reconstructing the live observation producer, resetting its authority, or
/// otherwise ending one bounded correlation series must mint a different value.
/// App/UI code cannot construct identities and splice unrelated producer lives.
public struct PassiveBluetoothCandidateObservationSeriesIdentity: Equatable, Hashable, Sendable {
    public let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Package-issued local ordering for one candidate-observation window.
///
/// This sequence is deliberately **not** a CoreBluetooth callback generation ID.
/// `didDiscover` does not expose the scan request that originated a callback, so
/// incrementing a local counter cannot prove that a delayed callback belongs to a
/// later scan. The initializer is not public so app/UI code cannot mint ordering
/// tokens and turn arbitrary catalogs into authoritative physical evidence.
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
/// establish a bounded observation window and isolation from adjacent windows.
/// `observationSeriesIdentity` prevents cross-producer/session splicing, while the
/// local sequence orders windows *within* that software authority. Neither field
/// proves CoreBluetooth callback origin or physical scooter identity.
public struct PassiveBluetoothCandidateObservationSnapshot: Equatable, Sendable {
    public struct Candidate: Equatable, Sendable {
        public let id: UUID
        public let isConnectable: Bool?

        init(id: UUID, isConnectable: Bool?) {
            self.id = id
            self.isConnectable = isConnectable
        }
    }

    public let observationSeriesIdentity: PassiveBluetoothCandidateObservationSeriesIdentity
    public let windowSequence: PassiveBluetoothCandidateObservationWindowSequence
    public let candidates: [Candidate]

    init(
        observationSeriesIdentity: PassiveBluetoothCandidateObservationSeriesIdentity,
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

        self.observationSeriesIdentity = observationSeriesIdentity
        self.windowSequence = windowSequence
        self.candidates = candidates.sorted {
            $0.id.uuidString < $1.id.uuidString
        }
    }
}

enum PassiveBluetoothCandidateObservationSnapshotError: Error, Equatable, Sendable {
    case duplicatePeripheralIdentifier(UUID)
}

/// Evidence summary for the minimal repeatable physical target-correlation
/// experiment: OFF₁ -> ON₁ -> OFF₂ -> ON₂.
///
/// Repetition materially reduces the chance that a one-off unrelated BLE arrival
/// is mistaken for the scooter. It still does not authenticate hardware: another
/// device could theoretically change state in sync with the operator experiment,
/// and CoreBluetooth UUIDs are not permanent hardware identities.
///
/// The set policy also does not prove the four observation windows were isolated.
/// That authority belongs to the package producer that constructs the otherwise
/// non-public snapshots. Until the live CoreBluetooth lifecycle can prove those
/// boundaries, app code cannot drive this report honestly.
public struct PassiveBluetoothPowerCycleTargetCorrelationReport: Equatable, Sendable {
    public enum Disposition: Equatable, Sendable {
        /// The snapshots were issued by more than one software observation
        /// authority. Foreign producer/controller lifetimes may never be spliced.
        case invalidObservationAuthority

        /// The four local window sequences are not strictly increasing in the
        /// required OFF₁ -> ON₁ -> OFF₂ -> ON₂ order. This is only a local
        /// chronology sanity check, never CoreBluetooth callback provenance.
        case invalidObservationWindowOrder

        /// No full UUID repeats the required physical-response pattern.
        case noRepeatableCandidate

        /// More than one full UUID repeats the pattern; guessing is banned.
        case ambiguousRepeatableCandidates([UUID])

        /// Exactly one full UUID repeats the pattern. It may be offered for
        /// explicit operator selection as correlation evidence only.
        case singleRepeatableCandidate(UUID)
    }

    /// OFF₁, ON₁, OFF₂, ON₂ software-series identities in chronological input
    /// order. Keeping all four makes a rejected mixed-authority report auditable.
    public let observationSeriesIdentities: [PassiveBluetoothCandidateObservationSeriesIdentity]

    public let firstOffWindowSequence: PassiveBluetoothCandidateObservationWindowSequence
    public let firstOnWindowSequence: PassiveBluetoothCandidateObservationWindowSequence
    public let secondOffWindowSequence: PassiveBluetoothCandidateObservationWindowSequence
    public let secondOnWindowSequence: PassiveBluetoothCandidateObservationWindowSequence

    /// Every UUID observed while the scooter is expected OFF in cycle one.
    public let firstOffObservedIdentifiers: [UUID]

    /// Every UUID observed while the scooter is expected OFF in cycle two.
    public let secondOffObservedIdentifiers: [UUID]

    /// ON-window candidates not explicitly marked non-connectable.
    public let firstOnSelectableIdentifiers: [UUID]
    public let secondOnSelectableIdentifiers: [UUID]

    /// Selectable ON₁ UUIDs absent from the complete OFF₁ catalog.
    /// Descriptive only; one-cycle arrivals are never final correlation success.
    public let firstCycleNewSelectableIdentifiers: [UUID]

    /// Selectable ON₂ UUIDs absent from the complete OFF₂ catalog.
    /// Descriptive only; one-cycle arrivals are never final correlation success.
    public let secondCycleNewSelectableIdentifiers: [UUID]

    /// Full UUIDs selectable in both ON windows and absent from both complete OFF
    /// catalogs. Only this repeated set participates in final disposition.
    public let repeatableCandidateIdentifiers: [UUID]
    public let disposition: Disposition

    fileprivate init(
        observationSeriesIdentities: [PassiveBluetoothCandidateObservationSeriesIdentity],
        firstOffWindowSequence: PassiveBluetoothCandidateObservationWindowSequence,
        firstOnWindowSequence: PassiveBluetoothCandidateObservationWindowSequence,
        secondOffWindowSequence: PassiveBluetoothCandidateObservationWindowSequence,
        secondOnWindowSequence: PassiveBluetoothCandidateObservationWindowSequence,
        firstOffObservedIdentifiers: [UUID],
        secondOffObservedIdentifiers: [UUID],
        firstOnSelectableIdentifiers: [UUID],
        secondOnSelectableIdentifiers: [UUID],
        firstCycleNewSelectableIdentifiers: [UUID],
        secondCycleNewSelectableIdentifiers: [UUID],
        repeatableCandidateIdentifiers: [UUID],
        disposition: Disposition
    ) {
        self.observationSeriesIdentities = observationSeriesIdentities
        self.firstOffWindowSequence = firstOffWindowSequence
        self.firstOnWindowSequence = firstOnWindowSequence
        self.secondOffWindowSequence = secondOffWindowSequence
        self.secondOnWindowSequence = secondOnWindowSequence
        self.firstOffObservedIdentifiers = firstOffObservedIdentifiers
        self.secondOffObservedIdentifiers = secondOffObservedIdentifiers
        self.firstOnSelectableIdentifiers = firstOnSelectableIdentifiers
        self.secondOnSelectableIdentifiers = secondOnSelectableIdentifiers
        self.firstCycleNewSelectableIdentifiers = firstCycleNewSelectableIdentifiers
        self.secondCycleNewSelectableIdentifiers = secondCycleNewSelectableIdentifiers
        self.repeatableCandidateIdentifiers = repeatableCandidateIdentifiers
        self.disposition = disposition
    }
}

public enum PassiveBluetoothPowerCycleTargetCorrelation {
    /// Require the same full UUID to repeat the operator-controlled OFF/ON pattern
    /// twice under one package-issued software observation authority. Names, RSSI,
    /// services, short UUID prefixes, ordering, and Tuya/product signatures never
    /// break ties or create authority.
    ///
    /// The caller cannot publicly construct snapshots, authority identities, or
    /// local sequence values. A future producer must separately prove its bounded
    /// CoreBluetooth window-isolation policy. Scope equality prevents cross-life
    /// splicing; sequence checks only reject local ordering errors. Neither proves
    /// callback provenance.
    public static func assess(
        firstOff: PassiveBluetoothCandidateObservationSnapshot,
        firstOn: PassiveBluetoothCandidateObservationSnapshot,
        secondOff: PassiveBluetoothCandidateObservationSnapshot,
        secondOn: PassiveBluetoothCandidateObservationSnapshot
    ) -> PassiveBluetoothPowerCycleTargetCorrelationReport {
        let snapshots = [firstOff, firstOn, secondOff, secondOn]
        let seriesIdentities = snapshots.map(\.observationSeriesIdentity)
        let sequences = snapshots.map { $0.windowSequence.rawValue }

        guard allEqual(seriesIdentities) else {
            return rejectedReport(
                snapshots: snapshots,
                disposition: .invalidObservationAuthority
            )
        }

        guard strictlyIncreasing(sequences) else {
            return rejectedReport(
                snapshots: snapshots,
                disposition: .invalidObservationWindowOrder
            )
        }

        let firstOffObserved = observedIdentifiers(in: firstOff)
        let secondOffObserved = observedIdentifiers(in: secondOff)
        let firstOnSelectable = selectableIdentifiers(in: firstOn)
        let secondOnSelectable = selectableIdentifiers(in: secondOn)

        let firstOffSet = Set(firstOffObserved)
        let secondOffSet = Set(secondOffObserved)
        let firstCycleNew = firstOnSelectable.filter { !firstOffSet.contains($0) }
        let secondCycleNew = secondOnSelectable.filter { !secondOffSet.contains($0) }
        let repeatable = sortedIdentifiers(
            Set(firstCycleNew).intersection(secondCycleNew)
        )

        let disposition: PassiveBluetoothPowerCycleTargetCorrelationReport.Disposition
        switch repeatable.count {
        case 0:
            disposition = .noRepeatableCandidate
        case 1:
            disposition = .singleRepeatableCandidate(repeatable[0])
        default:
            disposition = .ambiguousRepeatableCandidates(repeatable)
        }

        return .init(
            observationSeriesIdentities: seriesIdentities,
            firstOffWindowSequence: firstOff.windowSequence,
            firstOnWindowSequence: firstOn.windowSequence,
            secondOffWindowSequence: secondOff.windowSequence,
            secondOnWindowSequence: secondOn.windowSequence,
            firstOffObservedIdentifiers: firstOffObserved,
            secondOffObservedIdentifiers: secondOffObserved,
            firstOnSelectableIdentifiers: firstOnSelectable,
            secondOnSelectableIdentifiers: secondOnSelectable,
            firstCycleNewSelectableIdentifiers: firstCycleNew,
            secondCycleNewSelectableIdentifiers: secondCycleNew,
            repeatableCandidateIdentifiers: repeatable,
            disposition: disposition
        )
    }

    private static func rejectedReport(
        snapshots: [PassiveBluetoothCandidateObservationSnapshot],
        disposition: PassiveBluetoothPowerCycleTargetCorrelationReport.Disposition
    ) -> PassiveBluetoothPowerCycleTargetCorrelationReport {
        precondition(snapshots.count == 4)
        return .init(
            observationSeriesIdentities: snapshots.map(\.observationSeriesIdentity),
            firstOffWindowSequence: snapshots[0].windowSequence,
            firstOnWindowSequence: snapshots[1].windowSequence,
            secondOffWindowSequence: snapshots[2].windowSequence,
            secondOnWindowSequence: snapshots[3].windowSequence,
            firstOffObservedIdentifiers: [],
            secondOffObservedIdentifiers: [],
            firstOnSelectableIdentifiers: [],
            secondOnSelectableIdentifiers: [],
            firstCycleNewSelectableIdentifiers: [],
            secondCycleNewSelectableIdentifiers: [],
            repeatableCandidateIdentifiers: [],
            disposition: disposition
        )
    }

    private static func observedIdentifiers(
        in snapshot: PassiveBluetoothCandidateObservationSnapshot
    ) -> [UUID] {
        sortedIdentifiers(Set(snapshot.candidates.map(\.id)))
    }

    private static func selectableIdentifiers(
        in snapshot: PassiveBluetoothCandidateObservationSnapshot
    ) -> [UUID] {
        sortedIdentifiers(
            Set(
                snapshot.candidates
                    .filter { $0.isConnectable != false }
                    .map(\.id)
            )
        )
    }

    private static func allEqual<T: Equatable>(_ values: [T]) -> Bool {
        guard let first = values.first else { return true }
        return values.dropFirst().allSatisfy { $0 == first }
    }

    private static func strictlyIncreasing(_ values: [UInt64]) -> Bool {
        zip(values, values.dropFirst()).allSatisfy { pair in
            pair.0 < pair.1
        }
    }

    private static func sortedIdentifiers(_ identifiers: Set<UUID>) -> [UUID] {
        identifiers.sorted { $0.uuidString < $1.uuidString }
    }
}
