import Foundation

/// Validation errors for Nembra's non-mutating Bluetooth capture domain.
public enum PassiveBluetoothCaptureValidationError: Error, Equatable, Sendable {
    case emptyPeripheralIdentifier
    case emptyBluetoothIdentifier
    case emptyStockAppField
    case emptyInterruptionReason
    case nonMonotonicSequence
    case nonMonotonicReceiptTime
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
}

/// Origins that can produce captured characteristic payloads without changing
/// scooter state. There is deliberately no write-command case in this capture
/// model.
public enum PassiveBluetoothValueOrigin: String, CaseIterable, Codable, Sendable {
    case notification
    case indication
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
    public let serviceData: [String: Data]

    public init(
        peripheralIdentifier: String,
        localName: String? = nil,
        rssi: Int? = nil,
        isConnectable: Bool? = nil,
        manufacturerData: Data? = nil,
        serviceUUIDs: [String] = [],
        serviceData: [String: Data] = [:]
    ) throws {
        guard !peripheralIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PassiveBluetoothCaptureValidationError.emptyPeripheralIdentifier
        }
        try Self.validateBluetoothIdentifiers(serviceUUIDs)
        try Self.validateBluetoothIdentifiers(Array(serviceData.keys))

        self.peripheralIdentifier = peripheralIdentifier
        self.localName = localName
        self.rssi = rssi
        self.isConnectable = isConnectable
        self.manufacturerData = manufacturerData
        self.serviceUUIDs = serviceUUIDs
        self.serviceData = serviceData
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
    case characteristic(PassiveBluetoothCharacteristicObservation)
    case value(PassiveBluetoothValueObservation)
    case stockAppState(PassiveBluetoothStockAppObservation)
    case interruption(PassiveBluetoothCaptureInterruption)
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
    /// as live appends. Imported/corrupt JSON therefore cannot bypass sequence
    /// or monotonic-time truth constraints through synthesized `Codable`.
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

/// Stable JSON codec for sharing a capture artifact between physical-device
/// sessions and offline parser/tests. Sorted keys keep diffs reviewable.
public enum PassiveBluetoothCaptureJSON {
    public static func encode(_ session: PassiveBluetoothCaptureSession, prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(session)
    }

    public static func decode(_ data: Data) throws -> PassiveBluetoothCaptureSession {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PassiveBluetoothCaptureSession.self, from: data)
    }
}
