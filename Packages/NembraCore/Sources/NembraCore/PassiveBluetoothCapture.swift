import Foundation

/// Validation errors for Nembra's non-mutating Bluetooth capture domain.
public enum PassiveBluetoothCaptureValidationError: Error, Equatable, Sendable {
    case emptyPeripheralIdentifier
    case emptyBluetoothIdentifier
    case emptyStockAppField
    case emptyInterruptionReason
    case nonMonotonicSequence
    case nonMonotonicReceiptTime
    case unsupportedSchemaVersion(Int)
}

/// Characteristic properties observed during GATT discovery.
///
/// `write` and `writeWithoutResponse` describe properties advertised by the
/// peripheral. Their presence here does not authorize or perform any write.
public enum PassiveBluetoothCharacteristicProperty: String, CaseIterable, Codable, Sendable {
    case broadcast
    case read
    case writeWithoutResponse
    case write
    case notify
    case indicate
    case authenticatedSignedWrites
    case extendedProperties
    case notifyEncryptionRequired
    case indicateEncryptionRequired
}

/// Origins that can produce captured characteristic payloads without changing
/// scooter state. There is deliberately no write-command case in this capture
/// model.
public enum PassiveBluetoothValueOrigin: String, CaseIterable, Codable, Sendable {
    case notification
    case indication
    /// A subscribed value callback where the acquisition API cannot truthfully
    /// distinguish notification from indication. CoreBluetooth may require this
    /// classification instead of guessing between the two GATT mechanisms.
    case subscriptionUpdate
    case readResponse
}

/// A raw advertisement snapshot. Manufacturer/service bytes are preserved as-is
/// so later protocol work can correlate them without retroactively inventing
/// fields that were not present in the original capture.
public struct PassiveBluetoothAdvertisementObservation: Equatable, Codable, Sendable {
    public let peripheralIdentifier: String
    public let localName: String?
    public let rssi: Int?
    public let isConnectable: Bool?
    public let manufacturerData: Data?
    public let serviceUUIDs: [String]
    public let overflowServiceUUIDs: [String]
    public let solicitedServiceUUIDs: [String]
    public let serviceData: [String: Data]
    public let txPowerLevel: Int?

    public init(
        peripheralIdentifier: String,
        localName: String? = nil,
        rssi: Int? = nil,
        isConnectable: Bool? = nil,
        manufacturerData: Data? = nil,
        serviceUUIDs: [String] = [],
        overflowServiceUUIDs: [String] = [],
        solicitedServiceUUIDs: [String] = [],
        serviceData: [String: Data] = [:],
        txPowerLevel: Int? = nil
    ) throws {
        guard !peripheralIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PassiveBluetoothCaptureValidationError.emptyPeripheralIdentifier
        }
        try Self.validateBluetoothIdentifiers(serviceUUIDs)
        try Self.validateBluetoothIdentifiers(overflowServiceUUIDs)
        try Self.validateBluetoothIdentifiers(solicitedServiceUUIDs)
        try Self.validateBluetoothIdentifiers(Array(serviceData.keys))

        self.peripheralIdentifier = peripheralIdentifier
        self.localName = localName
        self.rssi = rssi
        self.isConnectable = isConnectable
        self.manufacturerData = manufacturerData
        self.serviceUUIDs = serviceUUIDs
        self.overflowServiceUUIDs = overflowServiceUUIDs
        self.solicitedServiceUUIDs = solicitedServiceUUIDs
        self.serviceData = serviceData
        self.txPowerLevel = txPowerLevel
    }

    private static func validateBluetoothIdentifiers(_ identifiers: [String]) throws {
        guard identifiers.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw PassiveBluetoothCaptureValidationError.emptyBluetoothIdentifier
        }
    }
}

public struct PassiveBluetoothServiceObservation: Equatable, Codable, Sendable {
    public let peripheralIdentifier: String
    public let serviceUUID: String
    public let isPrimary: Bool

    public init(peripheralIdentifier: String, serviceUUID: String, isPrimary: Bool) throws {
        guard !peripheralIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PassiveBluetoothCaptureValidationError.emptyPeripheralIdentifier
        }
        guard !serviceUUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PassiveBluetoothCaptureValidationError.emptyBluetoothIdentifier
        }

        self.peripheralIdentifier = peripheralIdentifier
        self.serviceUUID = serviceUUID
        self.isPrimary = isPrimary
    }
}

/// Records the GATT edge between a discovered parent service and one service it
/// includes. This preserves topology that would otherwise be lost if capture
/// stored only a flat list of service UUIDs.
public struct PassiveBluetoothIncludedServiceObservation: Equatable, Codable, Sendable {
    public let peripheralIdentifier: String
    public let parentServiceUUID: String
    public let includedServiceUUID: String
    public let includedServiceIsPrimary: Bool

    public init(
        peripheralIdentifier: String,
        parentServiceUUID: String,
        includedServiceUUID: String,
        includedServiceIsPrimary: Bool
    ) throws {
        guard !peripheralIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PassiveBluetoothCaptureValidationError.emptyPeripheralIdentifier
        }
        guard !parentServiceUUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !includedServiceUUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PassiveBluetoothCaptureValidationError.emptyBluetoothIdentifier
        }

        self.peripheralIdentifier = peripheralIdentifier
        self.parentServiceUUID = parentServiceUUID
        self.includedServiceUUID = includedServiceUUID
        self.includedServiceIsPrimary = includedServiceIsPrimary
    }
}

public struct PassiveBluetoothCharacteristicObservation: Equatable, Codable, Sendable {
    public let peripheralIdentifier: String
    public let serviceUUID: String
    public let characteristicUUID: String
    public let properties: Set<PassiveBluetoothCharacteristicProperty>

    public init(
        peripheralIdentifier: String,
        serviceUUID: String,
        characteristicUUID: String,
        properties: Set<PassiveBluetoothCharacteristicProperty>
    ) throws {
        guard !peripheralIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PassiveBluetoothCaptureValidationError.emptyPeripheralIdentifier
        }
        guard !serviceUUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !characteristicUUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PassiveBluetoothCaptureValidationError.emptyBluetoothIdentifier
        }

        self.peripheralIdentifier = peripheralIdentifier
        self.serviceUUID = serviceUUID
        self.characteristicUUID = characteristicUUID
        self.properties = properties
    }
}

/// Records descriptor discovery without pretending an arbitrary CoreBluetooth
/// descriptor value can be losslessly stringified. Typed descriptor-value
/// evidence can be added later when an acquisition path has a truthful codec.
public struct PassiveBluetoothDescriptorObservation: Equatable, Codable, Sendable {
    public let peripheralIdentifier: String
    public let serviceUUID: String
    public let characteristicUUID: String
    public let descriptorUUID: String

    public init(
        peripheralIdentifier: String,
        serviceUUID: String,
        characteristicUUID: String,
        descriptorUUID: String
    ) throws {
        guard !peripheralIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PassiveBluetoothCaptureValidationError.emptyPeripheralIdentifier
        }
        guard !serviceUUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !characteristicUUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !descriptorUUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PassiveBluetoothCaptureValidationError.emptyBluetoothIdentifier
        }

        self.peripheralIdentifier = peripheralIdentifier
        self.serviceUUID = serviceUUID
        self.characteristicUUID = characteristicUUID
        self.descriptorUUID = descriptorUUID
    }
}

public struct PassiveBluetoothValueObservation: Equatable, Codable, Sendable {
    public let peripheralIdentifier: String
    public let serviceUUID: String
    public let characteristicUUID: String
    public let origin: PassiveBluetoothValueOrigin
    public let payload: Data

    public init(
        peripheralIdentifier: String,
        serviceUUID: String,
        characteristicUUID: String,
        origin: PassiveBluetoothValueOrigin,
        payload: Data
    ) throws {
        guard !peripheralIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PassiveBluetoothCaptureValidationError.emptyPeripheralIdentifier
        }
        guard !serviceUUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !characteristicUUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PassiveBluetoothCaptureValidationError.emptyBluetoothIdentifier
        }

        self.peripheralIdentifier = peripheralIdentifier
        self.serviceUUID = serviceUUID
        self.characteristicUUID = characteristicUUID
        self.origin = origin
        self.payload = payload
    }
}

/// A human-observed stock-app state marker captured at a known point in time.
/// This is correlation evidence only; it does not assert any DP or byte meaning.
public struct PassiveBluetoothStockAppObservation: Equatable, Codable, Sendable {
    public let field: String
    public let displayedValue: String
    public let note: String?

    public init(field: String, displayedValue: String, note: String? = nil) throws {
        guard !field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !displayedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PassiveBluetoothCaptureValidationError.emptyStockAppField
        }
        self.field = field
        self.displayedValue = displayedValue
        self.note = note
    }
}

/// Marks a known capture continuity break such as disconnect, Bluetooth state
/// transition, process restart, or observer restart. A later decoder must never
/// silently pretend bytes on opposite sides of this marker were continuous.
public struct PassiveBluetoothCaptureInterruption: Equatable, Codable, Sendable {
    public let reason: String

    public init(reason: String) throws {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PassiveBluetoothCaptureValidationError.emptyInterruptionReason
        }
        self.reason = reason
    }
}

public enum PassiveBluetoothCaptureEvent: Equatable, Codable, Sendable {
    case advertisement(PassiveBluetoothAdvertisementObservation)
    case service(PassiveBluetoothServiceObservation)
    case includedService(PassiveBluetoothIncludedServiceObservation)
    case characteristic(PassiveBluetoothCharacteristicObservation)
    case descriptor(PassiveBluetoothDescriptorObservation)
    case value(PassiveBluetoothValueObservation)
    case stockAppState(PassiveBluetoothStockAppObservation)
    case interruption(PassiveBluetoothCaptureInterruption)

    /// Synthesized Codable initializers on nested evidence structs do not call
    /// their public validating initializers. Reconstructing each event here
    /// ensures imported artifacts cannot bypass field-level truth constraints.
    fileprivate func validateForCapture() throws {
        switch self {
        case let .advertisement(observation):
            _ = try PassiveBluetoothAdvertisementObservation(
                peripheralIdentifier: observation.peripheralIdentifier,
                localName: observation.localName,
                rssi: observation.rssi,
                isConnectable: observation.isConnectable,
                manufacturerData: observation.manufacturerData,
                serviceUUIDs: observation.serviceUUIDs,
                overflowServiceUUIDs: observation.overflowServiceUUIDs,
                solicitedServiceUUIDs: observation.solicitedServiceUUIDs,
                serviceData: observation.serviceData,
                txPowerLevel: observation.txPowerLevel
            )
        case let .service(observation):
            _ = try PassiveBluetoothServiceObservation(
                peripheralIdentifier: observation.peripheralIdentifier,
                serviceUUID: observation.serviceUUID,
                isPrimary: observation.isPrimary
            )
        case let .includedService(observation):
            _ = try PassiveBluetoothIncludedServiceObservation(
                peripheralIdentifier: observation.peripheralIdentifier,
                parentServiceUUID: observation.parentServiceUUID,
                includedServiceUUID: observation.includedServiceUUID,
                includedServiceIsPrimary: observation.includedServiceIsPrimary
            )
        case let .characteristic(observation):
            _ = try PassiveBluetoothCharacteristicObservation(
                peripheralIdentifier: observation.peripheralIdentifier,
                serviceUUID: observation.serviceUUID,
                characteristicUUID: observation.characteristicUUID,
                properties: observation.properties
            )
        case let .descriptor(observation):
            _ = try PassiveBluetoothDescriptorObservation(
                peripheralIdentifier: observation.peripheralIdentifier,
                serviceUUID: observation.serviceUUID,
                characteristicUUID: observation.characteristicUUID,
                descriptorUUID: observation.descriptorUUID
            )
        case let .value(observation):
            _ = try PassiveBluetoothValueObservation(
                peripheralIdentifier: observation.peripheralIdentifier,
                serviceUUID: observation.serviceUUID,
                characteristicUUID: observation.characteristicUUID,
                origin: observation.origin,
                payload: observation.payload
            )
        case let .stockAppState(observation):
            _ = try PassiveBluetoothStockAppObservation(
                field: observation.field,
                displayedValue: observation.displayedValue,
                note: observation.note
            )
        case let .interruption(observation):
            _ = try PassiveBluetoothCaptureInterruption(reason: observation.reason)
        }
    }
}

/// One ordered record in a capture session.
///
/// The monotonic uptime is the process-local ordering clock. Wall-clock `Date`
/// is retained only as useful metadata and is never allowed to repair ordering.
public struct PassiveBluetoothCaptureRecord: Equatable, Codable, Sendable {
    public let sequenceNumber: UInt64
    public let receivedAtUptimeNanoseconds: UInt64
    public let receivedAtDate: Date
    public let event: PassiveBluetoothCaptureEvent

    public init(
        sequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        receivedAtDate: Date,
        event: PassiveBluetoothCaptureEvent
    ) {
        self.sequenceNumber = sequenceNumber
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.receivedAtDate = receivedAtDate
        self.event = event
    }
}

/// Durable, platform-neutral capture artifact for one real-world observation
/// session. This type contains no motorized-vehicle command encoder and no
/// inferred Tuya DP mapping.
public struct PassiveBluetoothCaptureSession: Equatable, Codable, Sendable {
    public let id: UUID
    public let vehicleIdentity: VehicleIdentity
    public let startedAt: Date
    public private(set) var records: [PassiveBluetoothCaptureRecord]

    private enum CodingKeys: String, CodingKey {
        case id
        case vehicleIdentity
        case startedAt
        case records
    }

    public init(
        id: UUID = UUID(),
        vehicleIdentity: VehicleIdentity,
        startedAt: Date,
        records: [PassiveBluetoothCaptureRecord] = []
    ) throws {
        self.id = id
        self.vehicleIdentity = vehicleIdentity
        self.startedAt = startedAt
        self.records = []

        for record in records {
            try append(record)
        }
    }

    /// Decoding deliberately replays records through the same validation path
    /// as live appends. Imported/corrupt JSON therefore cannot bypass sequence,
    /// monotonic-time, or nested evidence truth constraints through synthesized
    /// `Codable` initializers.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let vehicleIdentity = try container.decode(VehicleIdentity.self, forKey: .vehicleIdentity)
        let startedAt = try container.decode(Date.self, forKey: .startedAt)
        let decodedRecords = try container.decode([PassiveBluetoothCaptureRecord].self, forKey: .records)

        try self.init(
            id: id,
            vehicleIdentity: vehicleIdentity,
            startedAt: startedAt,
            records: decodedRecords
        )
    }

    public mutating func append(_ record: PassiveBluetoothCaptureRecord) throws {
        try record.event.validateForCapture()
        if let last = records.last {
            guard record.sequenceNumber > last.sequenceNumber else {
                throw PassiveBluetoothCaptureValidationError.nonMonotonicSequence
            }
            guard record.receivedAtUptimeNanoseconds >= last.receivedAtUptimeNanoseconds else {
                throw PassiveBluetoothCaptureValidationError.nonMonotonicReceiptTime
            }
        }
        records.append(record)
    }

    public mutating func append(
        _ event: PassiveBluetoothCaptureEvent,
        sequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        receivedAtDate: Date
    ) throws {
        try append(
            PassiveBluetoothCaptureRecord(
                sequenceNumber: sequenceNumber,
                receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
                receivedAtDate: receivedAtDate,
                event: event
            )
        )
    }
}

/// Stable, versioned JSON codec for sharing capture artifacts between
/// physical-device sessions and offline parser/tests. Sorted keys keep diffs
/// reviewable while millisecond epoch dates preserve sub-second correlation
/// metadata. A versioned envelope makes future migrations explicit instead of
/// silently reinterpreting irreplaceable physical capture evidence.
public enum PassiveBluetoothCaptureJSON {
    public static let currentSchemaVersion = 1

    private struct Envelope: Codable {
        let schemaVersion: Int
        let session: PassiveBluetoothCaptureSession
    }

    public static func encode(_ session: PassiveBluetoothCaptureSession, prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(
            Envelope(
                schemaVersion: currentSchemaVersion,
                session: session
            )
        )
    }

    public static func decode(_ data: Data) throws -> PassiveBluetoothCaptureSession {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let envelope = try decoder.decode(Envelope.self, from: data)
        guard envelope.schemaVersion == currentSchemaVersion else {
            throw PassiveBluetoothCaptureValidationError.unsupportedSchemaVersion(envelope.schemaVersion)
        }
        return envelope.session
    }
}
