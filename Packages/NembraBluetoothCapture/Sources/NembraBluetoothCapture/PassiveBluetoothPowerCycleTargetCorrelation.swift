import Foundation

/// Package-issued identity for one authoritative broad-scan candidate epoch.
///
/// The initializer is intentionally not public. App/UI code must not invent scan
/// generations merely to make two catalog snapshots look independent. A future
/// controller integration should issue these tokens only after the CoreBluetooth
/// callback acceptance path is generation-fenced.
public struct PassiveBluetoothCandidateScanEpoch: Equatable, Hashable, Sendable {
    public let rawValue: UInt64

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

/// Immutable candidate catalog from one authoritative scan epoch.
///
/// This is presentation/research targeting evidence only. It is not a durable
/// scooter identity and it does not prove that any candidate is an AOVOPRO ES80.
public struct PassiveBluetoothCandidateScanSnapshot: Equatable, Sendable {
    public struct Candidate: Equatable, Sendable {
        public let id: UUID
        public let isConnectable: Bool?

        init(id: UUID, isConnectable: Bool?) {
            self.id = id
            self.isConnectable = isConnectable
        }
    }

    public let epoch: PassiveBluetoothCandidateScanEpoch
    public let candidates: [Candidate]

    init(
        epoch: PassiveBluetoothCandidateScanEpoch,
        candidates: [Candidate]
    ) throws {
        var seen = Set<UUID>()
        for candidate in candidates {
            guard seen.insert(candidate.id).inserted else {
                throw PassiveBluetoothCandidateScanSnapshotError
                    .duplicatePeripheralIdentifier(candidate.id)
            }
        }

        self.epoch = epoch
        self.candidates = candidates.sorted {
            $0.id.uuidString < $1.id.uuidString
        }
    }
}

enum PassiveBluetoothCandidateScanSnapshotError: Error, Equatable, Sendable {
    case duplicatePeripheralIdentifier(UUID)
}

/// Evidence summary for the minimal physical target-correlation experiment:
/// snapshot nearby candidates with the intended scooter OFF, then snapshot a
/// fresh scan epoch after the operator powers only that scooter ON.
///
/// A single delta candidate is still only a physical-correlation candidate for
/// explicit operator selection. It is not authentication, permanent identity,
/// GATT/protocol verification, or permission to issue vehicle commands.
public struct PassiveBluetoothPowerCycleTargetCorrelationReport: Equatable, Sendable {
    public enum Disposition: Equatable, Sendable {
        /// The powered-on snapshot does not come from a strictly later scan epoch.
        /// Reusing one catalog cannot establish an OFF -> ON candidate delta.
        case invalidScanEpochOrder

        /// No newly selectable candidate appeared after the intended power-on.
        case noNewSelectableCandidate

        /// More than one newly selectable candidate appeared; guessing is banned.
        case ambiguousNewSelectableCandidates([UUID])

        /// Exactly one newly selectable UUID was absent from the complete OFF
        /// snapshot. This may be offered for explicit operator selection only.
        case singleNewSelectableCandidate(UUID)
    }

    public let baselineEpoch: PassiveBluetoothCandidateScanEpoch
    public let poweredOnEpoch: PassiveBluetoothCandidateScanEpoch

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
        baselineEpoch: PassiveBluetoothCandidateScanEpoch,
        poweredOnEpoch: PassiveBluetoothCandidateScanEpoch,
        baselineObservedIdentifiers: [UUID],
        poweredOnSelectableIdentifiers: [UUID],
        newSelectableIdentifiers: [UUID],
        disposition: Disposition
    ) {
        self.baselineEpoch = baselineEpoch
        self.poweredOnEpoch = poweredOnEpoch
        self.baselineObservedIdentifiers = baselineObservedIdentifiers
        self.poweredOnSelectableIdentifiers = poweredOnSelectableIdentifiers
        self.newSelectableIdentifiers = newSelectableIdentifiers
        self.disposition = disposition
    }
}

public enum PassiveBluetoothPowerCycleTargetCorrelation {
    /// Compare two already-authoritative scan snapshots without using names,
    /// RSSI, UUID prefixes, or any guessed product signature.
    ///
    /// The caller cannot publicly mint either snapshot or epoch. Until the live
    /// controller exposes generation-fenced snapshot production, this algorithm
    /// deliberately remains impossible to drive from app code with invented
    /// generation numbers.
    public static func assess(
        baseline: PassiveBluetoothCandidateScanSnapshot,
        poweredOn: PassiveBluetoothCandidateScanSnapshot
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

        guard poweredOn.epoch.rawValue > baseline.epoch.rawValue else {
            return .init(
                baselineEpoch: baseline.epoch,
                poweredOnEpoch: poweredOn.epoch,
                baselineObservedIdentifiers: baselineObserved,
                poweredOnSelectableIdentifiers: poweredOnSelectable,
                newSelectableIdentifiers: [],
                disposition: .invalidScanEpochOrder
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
            baselineEpoch: baseline.epoch,
            poweredOnEpoch: poweredOn.epoch,
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
