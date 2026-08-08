import Foundation
import NembraCore

public struct PassiveBluetoothValueStreamKey: Hashable, Sendable, Comparable {
    public let peripheralIdentifier: String
    public let serviceUUID: String
    public let characteristicUUID: String

    public init(peripheralIdentifier: String, serviceUUID: String, characteristicUUID: String) {
        self.peripheralIdentifier = peripheralIdentifier
        self.serviceUUID = serviceUUID
        self.characteristicUUID = characteristicUUID
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.peripheralIdentifier != rhs.peripheralIdentifier { return lhs.peripheralIdentifier < rhs.peripheralIdentifier }
        if lhs.serviceUUID != rhs.serviceUUID { return lhs.serviceUUID < rhs.serviceUUID }
        return lhs.characteristicUUID < rhs.characteristicUUID
    }
}

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

    public init(key: PassiveBluetoothValueStreamKey, sampleCount: Int, continuitySegmentCount: Int, origins: Set<PassiveBluetoothValueOrigin>, minimumPayloadByteCount: Int, maximumPayloadByteCount: Int, uniquePayloadCount: Int, consecutiveDuplicatePayloadCount: Int, firstReceiptUptimeNanoseconds: UInt64, lastReceiptUptimeNanoseconds: UInt64, callbackIntervalCount: Int, minimumCallbackIntervalSeconds: Double?, medianCallbackIntervalSeconds: Double?, meanCallbackIntervalSeconds: Double?, maximumCallbackIntervalSeconds: Double?) {
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
    private struct ContinuitySegment: Hashable {
        let lastGlobalBoundarySequence: UInt64
        let lastPeripheralDisconnectSequence: UInt64
    }

    private struct Accumulator {
        var sampleCount = 0
        var segmentIdentifiers: Set<ContinuitySegment> = []
        var origins: Set<PassiveBluetoothValueOrigin> = []
        var minimumPayloadByteCount = Int.max
        var maximumPayloadByteCount = 0
        var uniquePayloads: Set<Data> = []
        var consecutiveDuplicatePayloadCount = 0
        var firstUptime = UInt64.max
        var lastUptime: UInt64 = 0
        var callbackIntervalsNanoseconds: [UInt64] = []
        var lastSampleBySegment: [ContinuitySegment: (uptime: UInt64, payload: Data)] = [:]

        mutating func ingest(_ value: PassiveBluetoothValueObservation, uptime: UInt64, segment: ContinuitySegment) {
            sampleCount += 1
            segmentIdentifiers.insert(segment)
            origins.insert(value.origin)
            minimumPayloadByteCount = min(minimumPayloadByteCount, value.payload.count)
            maximumPayloadByteCount = max(maximumPayloadByteCount, value.payload.count)
            uniquePayloads.insert(value.payload)
            firstUptime = min(firstUptime, uptime)
            lastUptime = max(lastUptime, uptime)
            if let previous = lastSampleBySegment[segment] {
                callbackIntervalsNanoseconds.append(uptime - previous.uptime)
                if previous.payload == value.payload { consecutiveDuplicatePayloadCount += 1 }
            }
            lastSampleBySegment[segment] = (uptime, value.payload)
        }

        func finalize(key: PassiveBluetoothValueStreamKey) -> PassiveBluetoothValueStreamStatistics {
            let sortedIntervals = callbackIntervalsNanoseconds.sorted()
            let intervalSeconds = sortedIntervals.map { Double($0) / 1_000_000_000 }
            let mean = intervalSeconds.isEmpty ? nil : intervalSeconds.reduce(0, +) / Double(intervalSeconds.count)
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

    public static func summarize(_ session: PassiveBluetoothCaptureSession) -> [PassiveBluetoothValueStreamStatistics] {
        var lastGlobalBoundarySequence: UInt64 = 0
        var lastDisconnectSequenceByPeripheral: [String: UInt64] = [:]
        var accumulators: [PassiveBluetoothValueStreamKey: Accumulator] = [:]

        for record in session.records {
            switch record.event {
            case .interruption:
                lastGlobalBoundarySequence = record.sequenceNumber
            case let .connection(observation) where observation.state == .disconnected:
                lastDisconnectSequenceByPeripheral[observation.peripheralIdentifier] = record.sequenceNumber
            case let .value(value):
                let key = PassiveBluetoothValueStreamKey(peripheralIdentifier: value.peripheralIdentifier, serviceUUID: value.serviceUUID, characteristicUUID: value.characteristicUUID)
                let segment = ContinuitySegment(lastGlobalBoundarySequence: lastGlobalBoundarySequence, lastPeripheralDisconnectSequence: lastDisconnectSequenceByPeripheral[value.peripheralIdentifier, default: 0])
                accumulators[key, default: Accumulator()].ingest(value, uptime: record.receivedAtUptimeNanoseconds, segment: segment)
            default:
                continue
            }
        }

        return accumulators.keys.sorted().compactMap { key in accumulators[key]?.finalize(key: key) }
    }

    private static func median(_ sortedValues: [Double]) -> Double? {
        guard !sortedValues.isEmpty else { return nil }
        let middle = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) { return (sortedValues[middle - 1] + sortedValues[middle]) / 2 }
        return sortedValues[middle]
    }
}
