import Foundation

/// Immutable historical evidence from a real physical Bluetooth capture.
///
/// This type intentionally stops at the transport layer. It must not be used to mint
/// speed, battery, power, mode, odometer, or other scooter telemetry semantics.
public struct PhysicalCaptureTransportEvidence: Encodable, Equatable, Sendable {
    public enum Provenance: String, Codable, Equatable, Sendable {
        case physicalCapture
    }

    public let captureID: String
    public let observedPeripheralID: String
    public let advertisedLocalName: String
    public let serviceUUID: String
    public let writeCharacteristicUUID: String
    public let notifyCharacteristicUUID: String
    public let completedScenarioCount: Int
    public let characteristicValueEventCount: Int
    public let peripheralInitiatedDisconnectCount: Int
    public let meanConnectedIntervalSeconds: Double
    public let provenance: Provenance

    // Physical provenance is authority-bearing. Keep construction module-internal so external
    // product/package callers cannot manufacture arbitrary values labeled as a physical capture.
    // The type is intentionally Encodable-only: public Decodable conformance would reopen a
    // caller-constructible authority path through arbitrary JSON. Accepted physical facts are
    // exposed through reviewed static ledger entries below; tests may use @testable fixtures.
    init(
        captureID: String,
        observedPeripheralID: String,
        advertisedLocalName: String,
        serviceUUID: String,
        writeCharacteristicUUID: String,
        notifyCharacteristicUUID: String,
        completedScenarioCount: Int,
        characteristicValueEventCount: Int,
        peripheralInitiatedDisconnectCount: Int,
        meanConnectedIntervalSeconds: Double,
        provenance: Provenance = .physicalCapture
    ) {
        self.captureID = captureID
        self.observedPeripheralID = observedPeripheralID
        self.advertisedLocalName = advertisedLocalName
        self.serviceUUID = serviceUUID
        self.writeCharacteristicUUID = writeCharacteristicUUID
        self.notifyCharacteristicUUID = notifyCharacteristicUUID
        self.completedScenarioCount = completedScenarioCount
        self.characteristicValueEventCount = characteristicValueEventCount
        self.peripheralInitiatedDisconnectCount = peripheralInitiatedDisconnectCount
        self.meanConnectedIntervalSeconds = meanConnectedIntervalSeconds
        self.provenance = provenance
    }

    /// A CoreBluetooth peripheral UUID is capture-local evidence, not a durable scooter identity.
    public var isStablePhysicalDeviceIdentity: Bool { false }

    /// This transport summary does not, by itself, prove byte-exact FD50 notification contents.
    ///
    /// In particular, a structured SmartLife SDK application update must not be re-described as
    /// raw characteristic bytes merely because it arrived during an authenticated BLE session.
    /// Byte authority requires a separately preserved byte-exact observation artifact.
    public var authorizesRawFD50NotificationBytes: Bool { false }

    /// Transport evidence never authorizes vehicle telemetry semantics by itself.
    ///
    /// Even a real non-empty application-level update proves only that an application value/update
    /// was observed at that boundary. Speed, battery, voltage, current, power, mode, odometer,
    /// command acknowledgement, or any other field meaning requires a separately accepted
    /// decoding/correlation contract.
    public var authorizesTelemetrySemantics: Bool { false }
}

public extension PhysicalCaptureTransportEvidence {
    /// First accepted physical ES80 transport artifact.
    ///
    /// Verified by capture C7D09A22. The GATT identifiers match Tuya FD50 transport,
    /// while telemetry/data-point semantics remain unknown because the capture received
    /// zero application characteristic payloads.
    static let c7d09a22 = Self(
        captureID: "C7D09A22-96DA-4E46-9BEF-E36F670ADB0E",
        observedPeripheralID: "6815A5F5-4D1E-E004-BAE8-6DF924123907",
        advertisedLocalName: "demo",
        serviceUUID: "FD50",
        writeCharacteristicUUID: "00000001-0000-1001-8001-00805F9B07D0",
        notifyCharacteristicUUID: "00000002-0000-1001-8001-00805F9B07D0",
        completedScenarioCount: 17,
        characteristicValueEventCount: 0,
        peripheralInitiatedDisconnectCount: 15,
        meanConnectedIntervalSeconds: 29.930
    )
}