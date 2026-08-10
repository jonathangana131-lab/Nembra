import Foundation

/// Source identity for an accepted power observation.
///
/// Only Simulator QA is defined today. Adding a physical source requires separate
/// verified hardware/protocol evidence; this enum must not be used to imply ES80
/// power authority before that evidence exists.
public enum PowerTelemetrySource: String, Codable, Equatable, Sendable {
    case simulatorQA = "simulator-qa"
}

/// Provenance of one power observation.
public enum PowerTelemetryProvenance: String, Codable, Equatable, Sendable {
    /// The source directly produced this power value for the synthetic fixture.
    case absoluteMeasurement = "absolute-measurement"
}

/// Immutable source receipt for one accepted power observation.
///
/// `receivedAtUptimeNanoseconds` is the source receipt clock. UI appearance,
/// display timelines, command acknowledgements, mode changes, and aggregate state
/// publications must never replace it with a newer clock merely to keep a value
/// looking live.
public struct PowerTelemetrySample: Equatable, Sendable {
    public let source: PowerTelemetrySource
    public let provenance: PowerTelemetryProvenance
    public let watts: Double
    public let receivedAtUptimeNanoseconds: UInt64
    public let receivedAtDate: Date

    public init?(
        source: PowerTelemetrySource,
        provenance: PowerTelemetryProvenance,
        watts: Double,
        receivedAtUptimeNanoseconds: UInt64,
        receivedAtDate: Date
    ) {
        guard watts.isFinite, watts >= 0 else { return nil }
        self.source = source
        self.provenance = provenance
        self.watts = watts == 0 ? 0 : watts
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.receivedAtDate = receivedAtDate
    }
}

/// Source-owned continuity state for power evidence.
///
/// This enum intentionally does not impose a physical freshness timeout. The
/// current Simulator Energy Rail package owns its separate presentation freshness
/// horizon. `.live` here means the source has not observed a continuity break since
/// this receipt; it does not mean an arbitrarily old receipt may be displayed as
/// fresh forever.
public enum PowerEvidenceAvailability: Equatable, Sendable {
    case unavailable
    case retained(PowerTelemetrySample)
    case live(PowerTelemetrySample)

    public var sample: PowerTelemetrySample? {
        switch self {
        case .unavailable:
            nil
        case let .retained(sample), let .live(sample):
            sample
        }
    }
}

/// Optional field-specific provider for power evidence.
///
/// Availability is current source state, not a raw event log. Implementations must
/// register a returned stream and yield the current availability atomically, and
/// should use newest-only buffering so a slow consumer cannot replay obsolete
/// `.live` state after a newer demotion. New equal-watt source receipts remain
/// distinct because their immutable receipt clocks differ.
public protocol PowerEvidenceProvider: Sendable {
    func powerEvidenceUpdates() async -> AsyncStream<PowerEvidenceAvailability>
    func powerEvidenceSnapshot() async -> PowerEvidenceAvailability
}

public extension PowerEvidenceProvider {
    func powerEvidenceSnapshot() async -> PowerEvidenceAvailability {
        let stream = await powerEvidenceUpdates()
        var iterator = stream.makeAsyncIterator()
        return await iterator.next() ?? .unavailable
    }
}
