import Foundation
import NembraCore

/// Whether two controlled captures can support direct raw-difference metrics.
///
/// Direct state-to-state metrics are available only when the captures represent
/// distinct observation sessions, carry the same immutable Nembra vehicle
/// context, resolve to the same observed GATT target, and contain no known raw
/// byte-continuity gap. Capture-session, capture-context, identity, and
/// continuity ambiguity remain distinct so downstream tooling can explain why
/// Nembra withheld a score.
public enum PassiveBluetoothControlledComparisonAvailability: String, Equatable, Sendable {
    case comparable
    case sameCaptureSession
    case captureContextMismatch
    case identityAmbiguous
    case continuityAmbiguous
}

/// Stable identity for one comparison stratum. Value origin is part of the
/// identity so a read response can never be silently compared with a
/// notification/subscription callback from the same GATT characteristic.
///
/// Construction is intentionally package-internal. Comparison identities are
/// evidence-derived output from `PassiveBluetoothCaptureComparison.compare`,
/// not caller-authored authority.
public struct PassiveBluetoothValueStreamComparisonIdentity: Hashable, Sendable, Comparable {
    public let key: PassiveBluetoothValueStreamKey
    public let origin: PassiveBluetoothValueOrigin

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key && lhs.origin.rawValue == rhs.origin.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(origin.rawValue)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.key != rhs.key { return lhs.key < rhs.key }
        return lhs.origin.rawValue < rhs.origin.rawValue
    }
}

/// Immutable evidence-derived snapshot for one canonical comparison stratum.
/// The raw capture remains the authority for original GATT spelling and bytes.
public struct PassiveBluetoothValueStreamSnapshot: Equatable, Sendable {
    public let key: PassiveBluetoothValueStreamKey
    public let origin: PassiveBluetoothValueOrigin
    public let sampleCount: Int
    public let continuitySegmentCount: Int
    public let uniquePayloadCount: Int
    public let firstPayload: Data?
    public let lastPayload: Data?
    public let uniquePayloads: Set<Data>

    public var identity: PassiveBluetoothValueStreamComparisonIdentity {
        PassiveBluetoothValueStreamComparisonIdentity(key: key, origin: origin)
    }
}

/// Evidence-derived direct-comparison output. Construction is package-internal
/// so external clients cannot manufacture `.comparable` metrics without passing
/// through the producer's capture-session, capture-context, identity, and
/// continuity gates.
public struct PassiveBluetoothValueStreamComparison: Equatable, Sendable, Identifiable {
    public enum Presence: String, Sendable {
        case baselineOnly
        case comparisonOnly
        case both
    }

    public let key: PassiveBluetoothValueStreamKey
    public let origin: PassiveBluetoothValueOrigin
    public let presence: Presence
    public let differenceAvailability: PassiveBluetoothControlledComparisonAvailability
    public let baseline: PassiveBluetoothValueStreamSnapshot?
    public let comparison: PassiveBluetoothValueStreamSnapshot?
    public let sharedPayloadCount: Int?
    public let baselineOnlyPayloadCount: Int?
    public let comparisonOnlyPayloadCount: Int?
    public let lastPayloadChanged: Bool?

    public var id: PassiveBluetoothValueStreamComparisonIdentity {
        PassiveBluetoothValueStreamComparisonIdentity(key: key, origin: origin)
    }

    /// A descriptive sorting hint only when the captures represent distinct
    /// observation sessions, carry the same Nembra vehicle context, resolve to
    /// the same observed GATT target, and each capture is uninterrupted. `nil`
    /// means Nembra deliberately withheld a cross-capture score because
    /// attribution is ambiguous.
    public var rawDifferenceScore: Int? {
        guard differenceAvailability == .comparable,
              let baselineOnlyPayloadCount,
              let comparisonOnlyPayloadCount else {
            return nil
        }

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

/// Top-level evidence-derived controlled-comparison report. Its memberwise
/// initializer is intentionally package-internal: callers may inspect reports,
/// but only `PassiveBluetoothCaptureComparison.compare` issues them.
///
/// The exact source session IDs and immutable Nembra vehicle identities are
/// retained so a report is mechanically bound to the capture pair/context that
/// earned it. Distinct session IDs are a fail-closed software provenance gate,
/// not proof that two physical captures/rides/devices were actually distinct.
/// Equality of vehicle metadata is likewise only a software evidence gate; it
/// does not authenticate physical hardware.
public struct PassiveBluetoothCaptureComparisonReport: Equatable, Sendable {
    public let baselineCaptureSessionID: UUID
    public let comparisonCaptureSessionID: UUID
    public let baselineVehicleIdentity: VehicleIdentity
    public let comparisonVehicleIdentity: VehicleIdentity
    public let baselineRecordCount: Int
    public let comparisonRecordCount: Int
    public let baselinePeripheralIdentifier: String?
    public let comparisonPeripheralIdentifier: String?
    public let peripheralRelationship: PassiveBluetoothCapturePeripheralRelationship

    /// Authoritative raw-byte continuity breaks in each capture. Continuity is
    /// capture-wide and intentionally separate from target attribution: every
    /// Core event classified `breaksByteContinuity` counts even when a structured
    /// disconnect names another peripheral.
    public let baselineContinuityBreakCount: Int
    public let comparisonContinuityBreakCount: Int
    public let differenceAvailability: PassiveBluetoothControlledComparisonAvailability

    /// Ever-observed hosted GATT services for the resolved target in each
    /// artifact. Advertisement-only UUIDs are deliberately excluded.
    public let baselineServices: Set<String>
    public let comparisonServices: Set<String>

    /// Direct topology deltas are available only for distinct observation
    /// sessions with the same immutable Nembra vehicle context, the same observed
    /// GATT identity, and uninterrupted evidence. `nil` means the comparison is
    /// not attributable enough for a direct topology delta.
    public let addedServices: Set<String>?
    public let removedServices: Set<String>?
    public let sharedServices: Set<String>?
    public let streamComparisons: [PassiveBluetoothValueStreamComparison]
}

/// Compares two immutable passive captures from controlled states.
///
/// Useful examples are `charger disconnected` vs `charger connected`, or
/// `stationary/rested` vs `after a short ride`. The comparison is intentionally
/// byte/statistics based. It never declares a stream to be voltage/current/etc.
///
/// Direct payload/topology difference metrics are fail-closed unless the inputs
/// claim distinct observation-session identities, carry exactly equal immutable
/// Nembra vehicle metadata, resolve to the same observed GATT peripheral, and
/// both capture timelines remain uninterrupted under Core's authoritative
/// raw-byte continuity policy. Distinct session IDs are only a software
/// provenance consistency check; they do not authenticate or prove separate
/// physical captures. Exact vehicle-metadata equality is likewise only a
/// software capture-context consistency check, not physical scooter
/// authentication. Nembra preserves descriptive per-capture evidence but does
/// not invent session, target, vehicle-context, or segment correspondence.
///
/// The report also exposes whether both sessions conservatively resolved to the
/// same CoreBluetooth peripheral identifier from typed GATT-path evidence. That
/// identifier is process/system evidence only; it is not promoted to a permanent
/// physical scooter identity. Advertisement-only and connection-only neighbors
/// never make an otherwise attributable GATT capture ambiguous.
public enum PassiveBluetoothCaptureComparison {
    public static func compare(
        baseline: PassiveBluetoothCaptureSession,
        comparison: PassiveBluetoothCaptureSession
    ) -> PassiveBluetoothCaptureComparisonReport {
        let baselineIdentifier = resolvedGATTPeripheralIdentifier(in: baseline)
        let comparisonIdentifier = resolvedGATTPeripheralIdentifier(in: comparison)
        let peripheralRelationship = relationship(
            baseline: baselineIdentifier,
            comparison: comparisonIdentifier
        )
        let baselineContinuityBreakCount = continuityBreakCount(in: baseline)
        let comparisonContinuityBreakCount = continuityBreakCount(in: comparison)

        let differenceAvailability: PassiveBluetoothControlledComparisonAvailability
        if baseline.id == comparison.id {
            differenceAvailability = .sameCaptureSession
        } else if baseline.vehicleIdentity != comparison.vehicleIdentity {
            differenceAvailability = .captureContextMismatch
        } else if peripheralRelationship != .sameObservedIdentifier {
            differenceAvailability = .identityAmbiguous
        } else if baselineContinuityBreakCount == 0 && comparisonContinuityBreakCount == 0 {
            differenceAvailability = .comparable
        } else {
            differenceAvailability = .continuityAmbiguous
        }

        let baselineStreams = valueStreamSnapshots(in: baseline)
        let comparisonStreams = valueStreamSnapshots(in: comparison)
        let allKeys = Set(baselineStreams.keys).union(comparisonStreams.keys)

        let comparisons = allKeys.map { identity -> PassiveBluetoothValueStreamComparison in
            let lhs = baselineStreams[identity]
            let rhs = comparisonStreams[identity]
            let presence: PassiveBluetoothValueStreamComparison.Presence
            switch (lhs, rhs) {
            case (.some, .some): presence = .both
            case (.some, .none): presence = .baselineOnly
            case (.none, .some): presence = .comparisonOnly
            case (.none, .none):
                preconditionFailure("union key must appear in at least one capture")
            }

            let payloadDifference = differenceAvailability == .comparable
                ? payloadDifference(lhs: lhs, rhs: rhs)
                : nil

            return PassiveBluetoothValueStreamComparison(
                key: identity.key,
                origin: identity.origin,
                presence: presence,
                differenceAvailability: differenceAvailability,
                baseline: lhs,
                comparison: rhs,
                sharedPayloadCount: payloadDifference?.shared,
                baselineOnlyPayloadCount: payloadDifference?.baselineOnly,
                comparisonOnlyPayloadCount: payloadDifference?.comparisonOnly,
                lastPayloadChanged: differenceAvailability == .comparable
                    ? lastPayloadChanged(lhs: lhs, rhs: rhs)
                    : nil
            )
        }
        .sorted(by: comparisonSort)

        let baselineServices = hostedGATTServiceUUIDs(
            in: baseline,
            peripheralIdentifier: baselineIdentifier
        )
        let comparisonServices = hostedGATTServiceUUIDs(
            in: comparison,
            peripheralIdentifier: comparisonIdentifier
        )

        let topologyDelta: (added: Set<String>, removed: Set<String>, shared: Set<String>)? =
            differenceAvailability == .comparable
                ? (
                    added: comparisonServices.subtracting(baselineServices),
                    removed: baselineServices.subtracting(comparisonServices),
                    shared: baselineServices.intersection(comparisonServices)
                )
                : nil

        return PassiveBluetoothCaptureComparisonReport(
            baselineCaptureSessionID: baseline.id,
            comparisonCaptureSessionID: comparison.id,
            baselineVehicleIdentity: baseline.vehicleIdentity,
            comparisonVehicleIdentity: comparison.vehicleIdentity,
            baselineRecordCount: baseline.records.count,
            comparisonRecordCount: comparison.records.count,
            baselinePeripheralIdentifier: baselineIdentifier,
            comparisonPeripheralIdentifier: comparisonIdentifier,
            peripheralRelationship: peripheralRelationship,
            baselineContinuityBreakCount: baselineContinuityBreakCount,
            comparisonContinuityBreakCount: comparisonContinuityBreakCount,
            differenceAvailability: differenceAvailability,
            baselineServices: baselineServices,
            comparisonServices: comparisonServices,
            addedServices: topologyDelta?.added,
            removedServices: topologyDelta?.removed,
            sharedServices: topologyDelta?.shared,
            streamComparisons: comparisons
        )
    }

    private struct ContinuitySegment: Hashable {
        let lastKnownByteContinuityBreakSequence: UInt64
    }

    private struct MutableSnapshot {
        let key: PassiveBluetoothValueStreamKey
        let origin: PassiveBluetoothValueOrigin
        var sampleCount = 0
        var segmentIdentifiers: Set<ContinuitySegment> = []
        var firstPayload: Data?
        var lastPayload: Data?
        var uniquePayloads: Set<Data> = []

        mutating func ingest(payload: Data, segment: ContinuitySegment) {
            sampleCount += 1
            segmentIdentifiers.insert(segment)
            if firstPayload == nil { firstPayload = payload }
            lastPayload = payload
            uniquePayloads.insert(payload)
        }

        func finalize() -> PassiveBluetoothValueStreamSnapshot {
            PassiveBluetoothValueStreamSnapshot(
                key: key,
                origin: origin,
                sampleCount: sampleCount,
                continuitySegmentCount: segmentIdentifiers.count,
                uniquePayloadCount: uniquePayloads.count,
                firstPayload: firstPayload,
                lastPayload: lastPayload,
                uniquePayloads: uniquePayloads
            )
        }
    }

    private static func valueStreamSnapshots(
        in session: PassiveBluetoothCaptureSession
    ) -> [PassiveBluetoothValueStreamComparisonIdentity: PassiveBluetoothValueStreamSnapshot] {
        var lastKnownByteContinuityBreakSequence: UInt64 = 0
        var mutable: [PassiveBluetoothValueStreamComparisonIdentity: MutableSnapshot] = [:]

        for record in session.records {
            if record.event.breaksByteContinuity {
                lastKnownByteContinuityBreakSequence = record.sequenceNumber
            }

            guard case let .value(value) = record.event else { continue }
            // CoreBluetooth UUID text is representation, not physical stream
            // identity. Normalize only the GATT service/characteristic fields
            // used by this comparison layer. The peripheral identifier remains
            // opaque and exact, and the immutable raw capture retains the
            // original strings for provenance/audit.
            let key = PassiveBluetoothValueStreamKey(
                peripheralIdentifier: value.peripheralIdentifier,
                serviceUUID: normalize(value.serviceUUID),
                characteristicUUID: normalize(value.characteristicUUID)
            )
            let identity = PassiveBluetoothValueStreamComparisonIdentity(
                key: key,
                origin: value.origin
            )
            let segment = ContinuitySegment(
                lastKnownByteContinuityBreakSequence: lastKnownByteContinuityBreakSequence
            )
            var snapshot = mutable[
                identity,
                default: MutableSnapshot(key: key, origin: value.origin)
            ]
            snapshot.ingest(payload: value.payload, segment: segment)
            mutable[identity] = snapshot
        }

        return Dictionary(uniqueKeysWithValues: mutable.map { identity, snapshot in
            (identity, snapshot.finalize())
        })
    }

    private static func payloadDifference(
        lhs: PassiveBluetoothValueStreamSnapshot?,
        rhs: PassiveBluetoothValueStreamSnapshot?
    ) -> (shared: Int, baselineOnly: Int, comparisonOnly: Int) {
        let lhsPayloads = lhs?.uniquePayloads ?? []
        let rhsPayloads = rhs?.uniquePayloads ?? []
        return (
            shared: lhsPayloads.intersection(rhsPayloads).count,
            baselineOnly: lhsPayloads.subtracting(rhsPayloads).count,
            comparisonOnly: rhsPayloads.subtracting(lhsPayloads).count
        )
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

    private static func comparisonSort(
        lhs: PassiveBluetoothValueStreamComparison,
        rhs: PassiveBluetoothValueStreamComparison
    ) -> Bool {
        switch (lhs.rawDifferenceScore, rhs.rawDifferenceScore) {
        case let (.some(lhsScore), .some(rhsScore)) where lhsScore != rhsScore:
            return lhsScore > rhsScore
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return lhs.id < rhs.id
        }
    }

    /// Mirrors the package's conservative unscoped transport identity rule:
    /// only typed GATT-path evidence can establish the comparison target.
    /// Advertisement-only and connection-only nearby devices are not promoted
    /// into target identity.
    private static func resolvedGATTPeripheralIdentifier(
        in session: PassiveBluetoothCaptureSession
    ) -> String? {
        var identifiers: Set<String> = []
        for record in session.records {
            switch record.event {
            case let .service(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .includedService(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .characteristic(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .descriptor(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .subscription(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .value(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case .advertisement, .connection, .stockAppState, .interruption:
                continue
            }
        }
        guard identifiers.count == 1 else { return nil }
        return identifiers.first
    }

    private static func continuityBreakCount(
        in session: PassiveBluetoothCaptureSession
    ) -> Int {
        session.records.reduce(into: 0) { count, record in
            if record.event.breaksByteContinuity {
                count += 1
            }
        }
    }

    private static func hostedGATTServiceUUIDs(
        in session: PassiveBluetoothCaptureSession,
        peripheralIdentifier: String?
    ) -> Set<String> {
        guard let peripheralIdentifier else { return [] }
        var services: Set<String> = []

        for record in session.records {
            switch record.event {
            case let .service(observation) where observation.peripheralIdentifier == peripheralIdentifier:
                services.insert(normalize(observation.serviceUUID))

            case let .includedService(observation) where observation.peripheralIdentifier == peripheralIdentifier:
                services.insert(normalize(observation.parentServiceUUID))
                services.insert(normalize(observation.includedServiceUUID))

            case let .characteristic(observation) where observation.peripheralIdentifier == peripheralIdentifier:
                services.insert(normalize(observation.serviceUUID))

            case let .descriptor(observation) where observation.peripheralIdentifier == peripheralIdentifier:
                services.insert(normalize(observation.serviceUUID))

            case let .subscription(observation) where observation.peripheralIdentifier == peripheralIdentifier:
                services.insert(normalize(observation.serviceUUID))

            case let .value(observation) where observation.peripheralIdentifier == peripheralIdentifier:
                services.insert(normalize(observation.serviceUUID))

            default:
                continue
            }
        }

        return services
    }

    private static func normalize(_ identifier: String) -> String {
        identifier.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
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
