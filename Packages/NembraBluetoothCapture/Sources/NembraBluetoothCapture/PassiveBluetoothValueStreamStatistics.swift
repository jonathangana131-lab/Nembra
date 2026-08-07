import Foundation
import NembraCore

public struct PassiveBluetoothValueStreamKey: Hashable, Sendable, Comparable {
    public let peripheralIdentifier: String
    public let serviceUUID: String
    public let characteristicUUID: String

    public init(
        peripheralIdentifier: String,
        serviceUUID: String,
        characteristicUUID: String
    ) {
        self.peripheralIdentifier = peripheralIdentifier
        self.serviceUUID = serviceUUID
        self.characteristicUUID = characteristicUUID
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.peripheralIdentifier != rhs.peripheralIdentifier {
            return lhs.peripheralIdentifier < rhs.peripheralIdentifier
        }
        if lhs.serviceUUID != rhs.serviceUUID {
            return lhs.serviceUUID < rhs.serviceUUID
        }
        return lhs.characteristicUUID < rhs.characteristicUUID
    }
}

/// Descriptive statistics for the raw CoreBluetooth value callbacks associated
/// with one characteristic. These numbers describe *capture callback behavior*,
/// not a decoded scooter field's authoritative measurement cadence.
public struct PassiveBluetoothValueStreamStatistics: Equatable, Sendable {
    public let key: PassiveBluetoothValueStreamKey
    public let sampleCount: Int
    public let continuitySegmentCount: Int
    public let origins: Set<PassiveBluetoothValueOrigin>
    public let minimumPayloadByteCount: Int
    public let maximumPayloadByteCount: Int
    public let uniquePayloadCount: Int
    public let consecutiveDuplicatePayloadCount: Int
    public let firstReceiptUptimeNanoseconds: UInt64
    public let lastReceiptUptimeNanoseconds: UInt64
    public let callbackIntervalCount: Int
    public let minimumCallbackIntervalSeconds: Double?
    public let medianCallbackIntervalSeconds: Double?
    public let meanCallbackIntervalSeconds: Double?
    public let maximumCallbackIntervalSeconds: Double?

    public init(
        key: PassiveBluetoothValueStreamKey,
        sampleCount: Int,
        continuitySegmentCount: Int,
        origins: Set<PassiveBluetoothValueOrigin>,
        minimumPayloadByteCount: Int,
        maximumPayloadByteCount: Int,
        uniquePayloadCount: Int,
        consecutiveDuplicatePayloadCount: Int,
        firstReceiptUptimeNanoseconds: UInt64,
        lastReceiptUptimeNanoseconds: UInt64,
        callbackIntervalCount: Int,
        minimumCallbackIntervalSeconds: Double?,
        medianCallbackIntervalSeconds: Double?,
        meanCallbackIntervalSeconds: Double?,
        maximumCallbackIntervalSeconds: Double?
    ) {
        self.key = key
        self.sampleCount = sampleCount
        self.continuitySegmentCount = continuitySegmentCount
        self.origins = origins
        self.minimumPayloadByteCount = minimumPayloadByteCount
        self.maximumPayloadByteCount = maximumPayloadByteCount
        self.uniquePayloadCount = uniquePayloadCount
        self.consecutiveDuplicatePayloadCount = consecutiveDuplicatePayloadCount
        self.firstReceiptUptimeNanoseconds = firstReceiptUptimeNanoseconds
        self.lastReceiptUptimeNanoseconds = lastReceiptUptimeNanoseconds
        self.callbackIntervalCount = callbackIntervalCount
        self.minimumCallbackIntervalSeconds = minimumCallbackIntervalSeconds
        self.medianCallbackIntervalSeconds = medianCallbackIntervalSeconds
        self.meanCallbackIntervalSeconds = meanCallbackIntervalSeconds
        self.maximumCallbackIntervalSeconds = maximumCallbackIntervalSeconds
    }
}

public enum PassiveBluetoothValueStreamAnalysis {
    private struct SegmentIdentifier: Hashable {
        let global: Int
        let path: Int
    }

    private struct Accumulator {
        var sampleCount = 0
        var segmentIdentifiers: Set<SegmentIdentifier> = []
        var origins: Set<PassiveBluetoothValueOrigin> = []
        var minimumPayloadByteCount = Int.max
        var maximumPayloadByteCount = 0
        var uniquePayloads: Set<Data> = []
        var consecutiveDuplicatePayloadCount = 0
        var firstUptime = UInt64.max
        var lastUptime: UInt64 = 0
        var callbackIntervalsNanoseconds: [UInt64] = []
        var lastSampleBySegment: [SegmentIdentifier: (uptime: UInt64, payload: Data)] = [:]

        mutating func ingest(
            _ value: PassiveBluetoothValueObservation,
            uptime: UInt64,
            segment: SegmentIdentifier
        ) {
            sampleCount += 1
            segmentIdentifiers.insert(segment)
            origins.insert(value.origin)
            minimumPayloadByteCount = min(minimumPayloadByteCount, value.payload.count)
            maximumPayloadByteCount = max(maximumPayloadByteCount, value.payload.count)
            uniquePayloads.insert(value.payload)
            firstUptime = min(firstUptime, uptime)
            lastUptime = max(lastUptime, uptime)

            if let previous = lastSampleBySegment[segment] {
                // Capture validation guarantees global monotonic uptime, so this
                // subtraction cannot underflow for a later record in one segment.
                callbackIntervalsNanoseconds.append(uptime - previous.uptime)
                if previous.payload == value.payload {
                    consecutiveDuplicatePayloadCount += 1
                }
            }
            lastSampleBySegment[segment] = (uptime, value.payload)
        }

        func finalize(key: PassiveBluetoothValueStreamKey) -> PassiveBluetoothValueStreamStatistics {
            let sortedIntervals = callbackIntervalsNanoseconds.sorted()
            let intervalSeconds = sortedIntervals.map { Double($0) / 1_000_000_000 }
            let mean = intervalSeconds.isEmpty
                ? nil
                : intervalSeconds.reduce(0, +) / Double(intervalSeconds.count)

            return PassiveBluetoothValueStreamStatistics(
                key: key,
                sampleCount: sampleCount,
                continuitySegmentCount: segmentIdentifiers.count,
                origins: origins,
                minimumPayloadByteCount: minimumPayloadByteCount == Int.max ? 0 : minimumPayloadByteCount,
                maximumPayloadByteCount: maximumPayloadByteCount,
                uniquePayloadCount: uniquePayloads.count,
                consecutiveDuplicatePayloadCount: consecutiveDuplicatePayloadCount,
                firstReceiptUptimeNanoseconds: firstUptime == UInt64.max ? 0 : firstUptime,
                lastReceiptUptimeNanoseconds: lastUptime,
                callbackIntervalCount: intervalSeconds.count,
                minimumCallbackIntervalSeconds: intervalSeconds.first,
                medianCallbackIntervalSeconds: median(intervalSeconds),
                meanCallbackIntervalSeconds: mean,
                maximumCallbackIntervalSeconds: intervalSeconds.last
            )
        }
    }

    /// Summarizes only raw `.value` records. Any parent-model event whose
    /// `breaksByteContinuity` flag is true starts a new global segment. A known
    /// CoreBluetooth notification-state transition starts a new segment only for
    /// that exact peripheral/service/characteristic path, so a disable/resume gap
    /// cannot be mistaken for callback cadence while unrelated streams remain
    /// continuous. Subscription state is transport evidence only; it is never a
    /// scooter command acknowledgement.
    public static func summarize(
        _ session: PassiveBluetoothCaptureSession
    ) -> [PassiveBluetoothValueStreamStatistics] {
        var currentGlobalSegment = 0
        var currentPathSegmentByKey: [PassiveBluetoothValueStreamKey: Int] = [:]
        var notifyingStateByKey: [PassiveBluetoothValueStreamKey: Bool] = [:]
        var accumulators: [PassiveBluetoothValueStreamKey: Accumulator] = [:]

        for record in session.records {
            if record.event.breaksByteContinuity {
                currentGlobalSegment += 1
                currentPathSegmentByKey.removeAll(keepingCapacity: true)
                notifyingStateByKey.removeAll(keepingCapacity: true)
                continue
            }

            switch record.event {
            case let .subscription(subscription):
                let key = PassiveBluetoothValueStreamKey(
                    peripheralIdentifier: subscription.peripheralIdentifier,
                    serviceUUID: subscription.serviceUUID,
                    characteristicUUID: subscription.characteristicUUID
                )
                let nextState = subscription.resultingIsNotifying
                let previousState = notifyingStateByKey[key]
                let hasCapturedValues = (accumulators[key]?.sampleCount ?? 0) > 0

                if let previousState {
                    if previousState != nextState {
                        currentPathSegmentByKey[key, default: 0] += 1
                    }
                } else if !nextState && hasCapturedValues {
                    // If values preceded the first observed subscription-state
                    // callback, a newly observed non-notifying state is enough to
                    // prove that future callbacks are not continuous with them.
                    currentPathSegmentByKey[key, default: 0] += 1
                }
                notifyingStateByKey[key] = nextState

            case let .value(value):
                let key = PassiveBluetoothValueStreamKey(
                    peripheralIdentifier: value.peripheralIdentifier,
                    serviceUUID: value.serviceUUID,
                    characteristicUUID: value.characteristicUUID
                )
                let segment = SegmentIdentifier(
                    global: currentGlobalSegment,
                    path: currentPathSegmentByKey[key, default: 0]
                )
                accumulators[key, default: Accumulator()].ingest(
                    value,
                    uptime: record.receivedAtUptimeNanoseconds,
                    segment: segment
                )

            default:
                continue
            }
        }

        return accumulators.keys.sorted().compactMap { key in
            accumulators[key]?.finalize(key: key)
        }
    }

    private static func median(_ sortedValues: [Double]) -> Double? {
        guard !sortedValues.isEmpty else { return nil }
        let middle = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middle - 1] + sortedValues[middle]) / 2
        }
        return sortedValues[middle]
    }
}
