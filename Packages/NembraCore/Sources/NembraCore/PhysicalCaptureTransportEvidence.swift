import Foundation

/// Immutable historical evidence from a real physical Bluetooth capture.
///
/// This type intentionally stops at the transport layer. It must not be used to mint
/// speed, battery, power, mode, odometer, or other scooter telemetry semantics.
public struct PhysicalCaptureTransportEvidence: Codable, Equatable, Sendable {
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

    /// No application characteristic payloads were received in C7D09A22, so this evidence
    /// cannot authorize any ES80 data-point meaning.
    public var authorizesTelemetrySemantics: Bool { characteristicValueEventCount > 0 }
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
