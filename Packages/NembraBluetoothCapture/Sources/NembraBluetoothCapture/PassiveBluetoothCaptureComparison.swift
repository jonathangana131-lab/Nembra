import Foundation
import NembraCore

public struct PassiveBluetoothValueStreamSnapshot: Equatable, Sendable {
    public let key: PassiveBluetoothValueStreamKey
    public let sampleCount: Int
    public let uniquePayloadCount: Int
    public let firstPayload: Data?
    public let lastPayload: Data?
    public let uniquePayloads: Set<Data>

    public init(
        key: PassiveBluetoothValueStreamKey,
        sampleCount: Int,
        uniquePayloadCount: Int,
        firstPayload: Data?,
        lastPayload: Data?,
        uniquePayloads: Set<Data>
    ) {
        self.key = key
        self.sampleCount = sampleCount
        self.uniquePayloadCount = uniquePayloadCount
        self.firstPayload = firstPayload
        self.lastPayload = lastPayload
        self.uniquePayloads = uniquePayloads
    }
}

public struct PassiveBluetoothValueStreamComparison: Equatable, Sendable, Identifiable {
    public enum Presence: String, Sendable {
        case baselineOnly
        case comparisonOnly
        case both
    }

    public let key: PassiveBluetoothValueStreamKey
    public let presence: Presence
    public let baseline: PassiveBluetoothValueStreamSnapshot?
    public let comparison: PassiveBluetoothValueStreamSnapshot?
    public let sharedPayloadCount: Int
    public let baselineOnlyPayloadCount: Int
    public let comparisonOnlyPayloadCount: Int
    public let lastPayloadChanged: Bool?

    public var id: PassiveBluetoothValueStreamKey { key }

    public init(
        key: PassiveBluetoothValueStreamKey,
        presence: Presence,
        baseline: PassiveBluetoothValueStreamSnapshot?,
        comparison: PassiveBluetoothValueStreamSnapshot?,
        sharedPayloadCount: Int,
        baselineOnlyPayloadCount: Int,
        comparisonOnlyPayloadCount: Int,
        lastPayloadChanged: Bool?
    ) {
        self.key = key
        self.presence = presence
        self.baseline = baseline
        self.comparison = comparison
        self.sharedPayloadCount = sharedPayloadCount
        self.baselineOnlyPayloadCount = baselineOnlyPayloadCount
        self.comparisonOnlyPayloadCount = comparisonOnlyPayloadCount
        self.lastPayloadChanged = lastPayloadChanged
    }

    /// A descriptive sorting hint only. A high score means the raw stream
    /// differed more between the controlled sessions; it does not establish why.
    public var rawDifferenceScore: Int {
        var score = baselineOnlyPayloadCount + comparisonOnlyPayloadCount
        if presence != .both { score += 2 }
        if lastPayloadChanged == true { score += 1 }
        return score
    }
}

public enum PassiveBluetoothCapturePeripheralRelationship: String, Sendable {
    /// Both captures conservatively resolved to the same CoreBluetooth
    /// peripheral identifier. This is useful continuity evidence, not a globally
    /// stable hardware identity claim.
    case sameObservedIdentifier

    /// Both captures resolved to exactly one GATT peripheral, but the identifiers
    /// differ. The comparison must not be presented as proven same-scooter data.
    case differentObservedIdentifiers

    /// At least one capture has no single unambiguous GATT peripheral.
    case unresolved
}

public struct PassiveBluetoothCaptureComparisonReport: Equatable, Sendable {
    public let baselineRecordCount: Int
    public let comparisonRecordCount: Int
    public let baselinePeripheralIdentifier: String?
    public let comparisonPeripheralIdentifier: String?
    public let peripheralRelationship: PassiveBluetoothCapturePeripheralRelationship
    public let baselineServices: Set<String>
    public let comparisonServices: Set<String>
    public let addedServices: Set<String>
    public let removedServices: Set<String>
    public let sharedServices: Set<String>
    public let streamComparisons: [PassiveBluetoothValueStreamComparison]

    public init(
        baselineRecordCount: Int,
        comparisonRecordCount: Int,
        baselinePeripheralIdentifier: String?,
        comparisonPeripheralIdentifier: String?,
        peripheralRelationship: PassiveBluetoothCapturePeripheralRelationship,
        baselineServices: Set<String>,
        comparisonServices: Set<String>,
        addedServices: Set<String>,
        removedServices: Set<String>,
        sharedServices: Set<String>,
        streamComparisons: [PassiveBluetoothValueStreamComparison]
    ) {
        self.baselineRecordCount = baselineRecordCount
        self.comparisonRecordCount = comparisonRecordCount
        self.baselinePeripheralIdentifier = baselinePeripheralIdentifier
        self.comparisonPeripheralIdentifier = comparisonPeripheralIdentifier
        self.peripheralRelationship = peripheralRelationship
        self.baselineServices = baselineServices
        self.comparisonServices = comparisonServices
        self.addedServices = addedServices
        self.removedServices = removedServices
        self.sharedServices = sharedServices
        self.streamComparisons = streamComparisons
    }
}

/// Compares two immutable passive captures from controlled states.
///
/// Useful examples are `charger disconnected` vs `charger connected`, or
/// `stationary/rested` vs `after a short ride`. The comparison is intentionally
/// byte/statistics based. It never declares a stream to be voltage/current/etc.
///
/// The report also exposes whether both sessions conservatively resolved to the
/// same CoreBluetooth peripheral identifier. That identifier is process/system
/// evidence only; it is not promoted to a permanent physical scooter identity.
public enum PassiveBluetoothCaptureComparison {
    public static func compare(
        baseline: PassiveBluetoothCaptureSession,
        comparison: PassiveBluetoothCaptureSession
    ) -> PassiveBluetoothCaptureComparisonReport {
        let baselineFingerprint = PassiveBluetoothTransportFingerprint.analyze(baseline)
        let comparisonFingerprint = PassiveBluetoothTransportFingerprint.analyze(comparison)
        let baselineStreams = valueStreamSnapshots(in: baseline)
        let comparisonStreams = valueStreamSnapshots(in: comparison)
        let allKeys = Set(baselineStreams.keys).union(comparisonStreams.keys)

        let comparisons = allKeys.map { key -> PassiveBluetoothValueStreamComparison in
            let lhs = baselineStreams[key]
            let rhs = comparisonStreams[key]
            let presence: PassiveBluetoothValueStreamComparison.Presence
            switch (lhs, rhs) {
            case (.some, .some): presence = .both
            case (.some, .none): presence = .baselineOnly
            case (.none, .some): presence = .comparisonOnly
            case (.none, .none):
                preconditionFailure("union key must appear in at least one capture")
            }

            let lhsPayloads = lhs?.uniquePayloads ?? []
            let rhsPayloads = rhs?.uniquePayloads ?? []
            let shared = lhsPayloads.intersection(rhsPayloads)
            let lhsOnly = lhsPayloads.subtracting(rhsPayloads)
            let rhsOnly = rhsPayloads.subtracting(lhsPayloads)

            return PassiveBluetoothValueStreamComparison(
                key: key,
                presence: presence,
                baseline: lhs,
                comparison: rhs,
                sharedPayloadCount: shared.count,
                baselineOnlyPayloadCount: lhsOnly.count,
                comparisonOnlyPayloadCount: rhsOnly.count,
                lastPayloadChanged: lastPayloadChanged(lhs: lhs, rhs: rhs)
            )
        }
        .sorted { lhs, rhs in
            if lhs.rawDifferenceScore != rhs.rawDifferenceScore {
                return lhs.rawDifferenceScore > rhs.rawDifferenceScore
            }
            return lhs.key < rhs.key
        }

        let baselineServices = baselineFingerprint.observedServiceUUIDs
        let comparisonServices = comparisonFingerprint.observedServiceUUIDs
        let baselineIdentifier = nonEmpty(baselineFingerprint.peripheralIdentifier)
        let comparisonIdentifier = nonEmpty(comparisonFingerprint.peripheralIdentifier)

        return PassiveBluetoothCaptureComparisonReport(
            baselineRecordCount: baseline.records.count,
            comparisonRecordCount: comparison.records.count,
            baselinePeripheralIdentifier: baselineIdentifier,
            comparisonPeripheralIdentifier: comparisonIdentifier,
            peripheralRelationship: relationship(
                baseline: baselineIdentifier,
                comparison: comparisonIdentifier
            ),
            baselineServices: baselineServices,
            comparisonServices: comparisonServices,
            addedServices: comparisonServices.subtracting(baselineServices),
            removedServices: baselineServices.subtracting(comparisonServices),
            sharedServices: baselineServices.intersection(comparisonServices),
            streamComparisons: comparisons
        )
    }

    private static func valueStreamSnapshots(
        in session: PassiveBluetoothCaptureSession
    ) -> [PassiveBluetoothValueStreamKey: PassiveBluetoothValueStreamSnapshot] {
        struct MutableSnapshot {
            var sampleCount = 0
            var firstPayload: Data?
            var lastPayload: Data?
            var uniquePayloads: Set<Data> = []
        }

        var mutable: [PassiveBluetoothValueStreamKey: MutableSnapshot] = [:]
        for record in session.records {
            guard case let .value(value) = record.event else { continue }
            let key = PassiveBluetoothValueStreamKey(
                peripheralIdentifier: value.peripheralIdentifier,
                serviceUUID: value.serviceUUID,
                characteristicUUID: value.characteristicUUID
            )
            var snapshot = mutable[key, default: MutableSnapshot()]
            snapshot.sampleCount += 1
            if snapshot.firstPayload == nil { snapshot.firstPayload = value.payload }
            snapshot.lastPayload = value.payload
            snapshot.uniquePayloads.insert(value.payload)
            mutable[key] = snapshot
        }

        return Dictionary(uniqueKeysWithValues: mutable.map { key, snapshot in
            (
                key,
                PassiveBluetoothValueStreamSnapshot(
                    key: key,
                    sampleCount: snapshot.sampleCount,
                    uniquePayloadCount: snapshot.uniquePayloads.count,
                    firstPayload: snapshot.firstPayload,
                    lastPayload: snapshot.lastPayload,
                    uniquePayloads: snapshot.uniquePayloads
                )
            )
        })
    }

    private static func lastPayloadChanged(
        lhs: PassiveBluetoothValueStreamSnapshot?,
        rhs: PassiveBluetoothValueStreamSnapshot?
    ) -> Bool? {
        guard let lhs, let rhs,
              let lhsLast = lhs.lastPayload,
              let rhsLast = rhs.lastPayload else {
            return nil
        }
        return lhsLast != rhsLast
    }

    private static func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    private static func relationship(
        baseline: String?,
        comparison: String?
    ) -> PassiveBluetoothCapturePeripheralRelationship {
        guard let baseline, let comparison else { return .unresolved }
        return baseline == comparison
            ? .sameObservedIdentifier
            : .differentObservedIdentifiers
    }
}
