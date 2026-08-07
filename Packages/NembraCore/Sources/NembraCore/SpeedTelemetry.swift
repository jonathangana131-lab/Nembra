import Foundation

/// The origin of one speed value before any display interpolation.
public enum SpeedTelemetrySource: String, Codable, Sendable {
    /// Speed reported by the scooter over its Bluetooth protocol.
    case scooterBluetooth
    /// `CLLocation.speed` or equivalent Core Location speed evidence.
    case gps
    /// A bounded short-horizon estimate informed by device motion.
    /// This is never an authoritative absolute speed measurement.
    case motionAssist
}

/// Separates absolute measurements from short-horizon estimates used only to
/// improve display responsiveness between authoritative measurements.
public enum SpeedTelemetryProvenance: String, Codable, Sendable {
    case absoluteMeasurement
    case shortHorizonEstimate
}

public enum SpeedTelemetryValidationError: Error, Equatable, Sendable {
    case invalidSpeed
    case invalidAccuracy
    case invalidProvenanceForSource
}

/// Any subsystem that can emit raw speed evidence conforms to this contract.
/// The scooter BLE service, Core Location adapter, and bounded motion-assist
/// estimator can therefore be benchmarked with the same diagnostics pipeline.
public protocol SpeedTelemetryProvider: Sendable {
    func speedTelemetryUpdates() async -> AsyncStream<SpeedTelemetrySample>
}

/// One immutable piece of raw speed evidence.
///
/// `receivedAtUptimeNanoseconds` is the ordering/interval clock. It must come
/// from a monotonic clock (for example `DispatchTime.now().uptimeNanoseconds`)
/// so wall-clock changes cannot corrupt packet-frequency measurements.
///
/// `measurementDate` is optional because many BLE packets do not contain a
/// source timestamp. When present (for example from Core Location), it can be
/// compared with `receivedAtDate` to estimate delivery latency.
public struct SpeedTelemetrySample: Equatable, Codable, Sendable {
    public let source: SpeedTelemetrySource
    public let provenance: SpeedTelemetryProvenance
    public let metersPerSecond: Double
    public let receivedAtUptimeNanoseconds: UInt64
    public let receivedAtDate: Date
    public let measurementDate: Date?
    public let speedAccuracyMetersPerSecond: Double?

    private enum CodingKeys: String, CodingKey {
        case source
        case provenance
        case metersPerSecond
        case receivedAtUptimeNanoseconds
        case receivedAtDate
        case measurementDate
        case speedAccuracyMetersPerSecond
    }

    public init(
        source: SpeedTelemetrySource,
        provenance: SpeedTelemetryProvenance,
        metersPerSecond: Double,
        receivedAtUptimeNanoseconds: UInt64,
        receivedAtDate: Date,
        measurementDate: Date? = nil,
        speedAccuracyMetersPerSecond: Double? = nil
    ) throws {
        guard metersPerSecond.isFinite, metersPerSecond >= 0 else {
            throw SpeedTelemetryValidationError.invalidSpeed
        }
        if let speedAccuracyMetersPerSecond {
            guard speedAccuracyMetersPerSecond.isFinite, speedAccuracyMetersPerSecond >= 0 else {
                throw SpeedTelemetryValidationError.invalidAccuracy
            }
        }
        switch source {
        case .scooterBluetooth, .gps:
            guard provenance == .absoluteMeasurement else {
                throw SpeedTelemetryValidationError.invalidProvenanceForSource
            }
        case .motionAssist:
            guard provenance == .shortHorizonEstimate else {
                throw SpeedTelemetryValidationError.invalidProvenanceForSource
            }
        }

        self.source = source
        self.provenance = provenance
        self.metersPerSecond = metersPerSecond
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.receivedAtDate = receivedAtDate
        self.measurementDate = measurementDate
        self.speedAccuracyMetersPerSecond = speedAccuracyMetersPerSecond
    }

    /// Imported samples must cross the same validation boundary as live provider
    /// samples. Synthesized Codable would assign stored properties directly and
    /// could otherwise recreate impossible source/provenance or numeric states.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            source: container.decode(SpeedTelemetrySource.self, forKey: .source),
            provenance: container.decode(SpeedTelemetryProvenance.self, forKey: .provenance),
            metersPerSecond: container.decode(Double.self, forKey: .metersPerSecond),
            receivedAtUptimeNanoseconds: container.decode(UInt64.self, forKey: .receivedAtUptimeNanoseconds),
            receivedAtDate: container.decode(Date.self, forKey: .receivedAtDate),
            measurementDate: container.decodeIfPresent(Date.self, forKey: .measurementDate),
            speedAccuracyMetersPerSecond: container.decodeIfPresent(Double.self, forKey: .speedAccuracyMetersPerSecond)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(provenance, forKey: .provenance)
        try container.encode(metersPerSecond, forKey: .metersPerSecond)
        try container.encode(receivedAtUptimeNanoseconds, forKey: .receivedAtUptimeNanoseconds)
        try container.encode(receivedAtDate, forKey: .receivedAtDate)
        try container.encodeIfPresent(measurementDate, forKey: .measurementDate)
        try container.encodeIfPresent(speedAccuracyMetersPerSecond, forKey: .speedAccuracyMetersPerSecond)
    }

    public var kilometersPerHour: Double {
        metersPerSecond * 3.6
    }

    public var milesPerHour: Double {
        metersPerSecond * 2.236_936_292_054_4
    }

    public var isAuthoritativeMeasurement: Bool {
        provenance == .absoluteMeasurement
    }

    /// Delivery latency is known only when the source provides a meaningful
    /// measurement timestamp. Negative values are discarded rather than
    /// interpreted because wall-clock adjustments can otherwise create lies.
    public var deliveryLatencyMilliseconds: Double? {
        guard let measurementDate else { return nil }
        let latency = receivedAtDate.timeIntervalSince(measurementDate) * 1_000
        guard latency.isFinite, latency >= 0 else { return nil }
        return latency
    }
}
