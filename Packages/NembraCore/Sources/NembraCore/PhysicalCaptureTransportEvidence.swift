import Foundation

/// Immutable historical evidence from a real physical Bluetooth capture.
///
/// This type intentionally stops at the transport layer. It must not be used to mint
/// speed, battery, power, mode, odometer, or other scooter telemetry semantics.
public struct PhysicalCaptureTransportEvidence: Codable, Equatable, Sendable {
    public enum Provenance: String, Codable, Equatable, Sendable {
        case physicalCapture
    }

    /// Transport-family identity is intentionally separate from telemetry/data-point meaning.
    public enum TransportFamily: String, Codable, Equatable, Sendable {
        case unknown
        case tuyaFD50
    }

    /// How strongly the capture itself establishes the transport-family classification.
    public enum TransportFamilyCertainty: String, Codable, Equatable, Sendable {
        case unclassified
        case verifiedPhysicalTransport
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
    public let transportFamily: TransportFamily
    public let transportFamilyCertainty: TransportFamilyCertainty

    public init(
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
        provenance: Provenance = .physicalCapture,
        transportFamily: TransportFamily = .unknown,
        transportFamilyCertainty: TransportFamilyCertainty = .unclassified
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
        self.transportFamily = transportFamily
        self.transportFamilyCertainty = transportFamilyCertainty
    }

    /// A CoreBluetooth peripheral UUID is capture-local evidence, not a durable scooter identity.
    public var isStablePhysicalDeviceIdentity: Bool { false }

    /// Transport evidence never authorizes vehicle telemetry semantics by itself.
    ///
    /// Even a real non-empty application payload proves only that application-layer bytes were
    /// observed. Speed, battery, voltage, current, power, mode, odometer, command acknowledgement,
    /// or any other field meaning requires a separately accepted decoding/correlation contract.
    public var authorizesTelemetrySemantics: Bool { false }
}

public extension PhysicalCaptureTransportEvidence {
    /// First accepted physical ES80 transport artifact.
    ///
    /// Verified by capture C7D09A22. The service/characteristic identifiers establish the
    /// Tuya FD50 transport family, while telemetry/data-point semantics remain unknown because
    /// the capture received zero application characteristic payloads.
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
        meanConnectedIntervalSeconds: 29.930,
        transportFamily: .tuyaFD50,
        transportFamilyCertainty: .verifiedPhysicalTransport
    )
}
