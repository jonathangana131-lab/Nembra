import Foundation

/// Validation errors for Nembra's non-mutating Bluetooth capture domain.
public enum PassiveBluetoothCaptureValidationError: Error, Equatable, Sendable {
    case emptyPeripheralIdentifier
    case emptyBluetoothIdentifier
    case emptyStockAppField
    case emptyInterruptionReason
    case emptyErrorDomain
    case nonFinitePlatformEventTimestamp
    case invalidConnectionMetadata
    case nonMonotonicSequence
    case nonMonotonicReceiptTime
    case unsupportedSchemaVersion(Int)
    case eventNotSupportedBySchemaVersion(Int)
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

/// Stable platform-neutral error evidence. Preserve domain/code instead of a
/// localized description so exported captures remain comparable across locale
/// and OS versions.
public struct PassiveBluetoothErrorObservation: Equatable, Codable, Sendable {
    public let domain: String
    public let code: Int

    public init(domain: String, code: Int) throws {
        guard !domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PassiveBluetoothCaptureValidationError.emptyErrorDomain
        }
        self.domain = domain
        self.code = code
    }
}

/// Connection callbacks are evidence in their own right and must not be reduced
/// to free-form interruption text. The record's receipt clocks still describe
/// when Nembra received the callback; `platformEventTimestamp` is separate
/// platform-supplied metadata, currently useful for CoreBluetooth's modern
/// disconnect callback.
public enum PassiveBluetoothConnectionState: String, CaseIterable, Codable, Sendable {
    case connected
    case failedToConnect
    case disconnected
}

public struct PassiveBluetoothConnectionObservation: Equatable, Codable, Sendable {
    public let peripheralIdentifier: String
    public let state: PassiveBluetoothConnectionState
    public let platformEventTimestamp: TimeInterval?
    public let isReconnecting: Bool?
    public let error: PassiveBluetoothErrorObservation?

    public init(
        peripheralIdentifier: String,
        state: PassiveBluetoothConnectionState,
        platformEventTimestamp: TimeInterval? = nil,
        isReconnecting: Bool? = nil,
        error: PassiveBluetoothErrorObservation? = nil
    ) throws {
        guard !peripheralIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PassiveBluetoothCaptureValidationError.emptyPeripheralIdentifier
        }
        if let platformEventTimestamp, !platformEventTimestamp.isFinite {
            throw PassiveBluetoothCaptureValidationError.nonFinitePlatformEventTimestamp
        }
        guard state == .disconnected || (platformEventTimestamp == nil && isReconnecting == nil) else {
            throw PassiveBluetoothCaptureValidationError.invalidConnectionMetadata
        }
        guard state != .connected || error == nil else {
            throw PassiveBluetoothCaptureValidationError.invalidConnectionMetadata
        }

        self.peripheralIdentifier = peripheralIdentifier
        self.state = state
        self.platformEventTimestamp = platformEventTimestamp
        self.isReconnecting = isReconnecting
        self.error = error
    }
}

/// Result/state evidence for a value-update subscription callback. The optional
/// requested state is present only when the acquisition adapter can prove which
/// `setNotifyValue` request this callback answers. `resultingIsNotifying` is the
/// observed characteristic state after the callback. An error is transport/
/// subscription evidence, never a scooter command acknowledgement.
public struct PassiveBluetoothSubscriptionObservation: Equatable, Codable, Sendable {
    public let peripheralIdentifier: String
    public let serviceUUID: String
    public let characteristicUUID: String
    public let requestedEnabled: Bool?
    public let resultingIsNotifying: Bool
    public let error: PassiveBluetoothErrorObservation?

    public init(
        peripheralIdentifier: String,
        serviceUUID: String,
        characteristicUUID: String,
        requestedEnabled: Bool? = nil,
        resultingIsNotifying: Bool,
        error: PassiveBluetoothErrorObservation? = nil
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
        self.requestedEnabled = requestedEnabled
        self.resultingIsNotifying = resultingIsNotifying
        self.error = error
    }
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

    private enum CodingKeys: String, CodingKey {
        case peripheralIdentifier
        case serviceUUID
        case characteristicUUID
        case properties
    }

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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let peripheralIdentifier = try container.decode(String.self, forKey: .peripheralIdentifier)
        let serviceUUID = try container.decode(String.self, forKey: .serviceUUID)
        let characteristicUUID = try container.decode(String.self, forKey: .characteristicUUID)
        let properties = Set(
            try container.decode([PassiveBluetoothCharacteristicProperty].self, forKey: .properties)
        )
        try self.init(
            peripheralIdentifier: peripheralIdentifier,
            serviceUUID: serviceUUID,
            characteristicUUID: characteristicUUID,
            properties: properties
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(peripheralIdentifier, forKey: .peripheralIdentifier)
        try container.encode(serviceUUID, forKey: .serviceUUID)
        try container.encode(characteristicUUID, forKey: .characteristicUUID)
        try container.encode(properties.sorted { $0.rawValue < $1.rawValue }, forKey: .properties)
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
/// transition, an app-process restart within the same device boot, or observer
/// restart. A later decoder must never silently treat bytes across this marker
/// as continuous. A physical device reboot starts a new capture session because
/// the boot-relative receipt uptime clock resets.
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
    case connection(PassiveBluetoothConnectionObservation)
    case service(PassiveBluetoothServiceObservation)
    case includedService(PassiveBluetoothIncludedServiceObservation)
    case characteristic(PassiveBluetoothCharacteristicObservation)
    case descriptor(PassiveBluetoothDescriptorObservation)
    case subscription(PassiveBluetoothSubscriptionObservation)
    case value(PassiveBluetoothValueObservation)
    case stockAppState(PassiveBluetoothStockAppObservation)
    case interruption(PassiveBluetoothCaptureInterruption)

    /// Whether raw value evidence on opposite sides of this event must be
    /// analyzed as separate continuity segments. Structured disconnects carry
    /// this semantic directly; generic interruption events cover every other
    /// known observation gap.
    public var breaksByteContinuity: Bool {
        switch self {
        case let .connection(observation):
            return observation.state == .disconnected
        case .interruption:
            return true
        default:
            return false
        }
    }

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
        case let .connection(observation):
            let error = try observation.error.map {
                try PassiveBluetoothErrorObservation(domain: $0.domain, code: $0.code)
            }
            _ = try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: observation.peripheralIdentifier,
                state: observation.state,
                platformEventTimestamp: observation.platformEventTimestamp,
                isReconnecting: observation.isReconnecting,
                error: error
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
        case let .subscription(observation):
            let error = try observation.error.map {
                try PassiveBluetoothErrorObservation(domain: $0.domain, code: $0.code)
            }
            _ = try PassiveBluetoothSubscriptionObservation(
                peripheralIdentifier: observation.peripheralIdentifier,
                serviceUUID: observation.serviceUUID,
                characteristicUUID: observation.characteristicUUID,
                requestedEnabled: observation.requestedEnabled,
                resultingIsNotifying: observation.resultingIsNotifying,
                error: error
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
/// The acquisition adapter supplies a monotonic uptime ordering clock. The
/// current iOS adapter uses `DispatchTime.now().uptimeNanoseconds`, which is
/// system-boot-relative rather than process-relative. Wall-clock `Date` is
/// retained only as metadata and never repairs ordering. A capture session must
/// start fresh after a physical device reboot unless a future explicit clock
/// epoch model is added.
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

/// Platform-neutral in-memory capture state for one real-world observation
/// session. Durable serialization is intentionally available only through
/// `PassiveBluetoothCaptureJSON`, whose envelope owns the schema version. The
/// session itself does not conform to `Codable`, preventing callers from
/// accidentally persisting an unversioned long-lived evidence artifact.
public struct PassiveBluetoothCaptureSession: Equatable, Sendable {
    public let id: UUID
    public let vehicleIdentity: VehicleIdentity
    public let startedAt: Date
    public private(set) var records: [PassiveBluetoothCaptureRecord]

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
/// physical-device sessions and offline parser/tests. Sorted keys plus explicit
/// deterministic characteristic-property encoding keep semantically identical
/// artifacts reviewable while millisecond epoch dates preserve sub-second
/// correlation metadata. Schema v2 adds structured connection/subscription
/// evidence; v1 remains readable so existing raw evidence is not discarded.
public enum PassiveBluetoothCaptureJSON {
    public static let currentSchemaVersion = 2
    private static let supportedSchemaVersions: Set<Int> = [1, 2]

    private struct VersionProbe: Decodable {
        let schemaVersion: Int
    }

    private struct SessionPayload: Codable {
        let id: UUID
        let vehicleIdentity: VehicleIdentity
        let startedAt: Date
        let records: [PassiveBluetoothCaptureRecord]

        init(_ session: PassiveBluetoothCaptureSession) {
            id = session.id
            vehicleIdentity = session.vehicleIdentity
            startedAt = session.startedAt
            records = session.records
        }

        func validatedSession() throws -> PassiveBluetoothCaptureSession {
            try PassiveBluetoothCaptureSession(
                id: id,
                vehicleIdentity: vehicleIdentity,
                startedAt: startedAt,
                records: records
            )
        }
    }

    private struct Envelope: Codable {
        let schemaVersion: Int
        let session: SessionPayload
    }

    public static func encode(_ session: PassiveBluetoothCaptureSession, prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(
            Envelope(
                schemaVersion: currentSchemaVersion,
                session: SessionPayload(session)
            )
        )
    }

    public static func decode(_ data: Data) throws -> PassiveBluetoothCaptureSession {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let probe = try decoder.decode(VersionProbe.self, from: data)
        guard supportedSchemaVersions.contains(probe.schemaVersion) else {
            throw PassiveBluetoothCaptureValidationError.unsupportedSchemaVersion(probe.schemaVersion)
        }

        let envelope = try decoder.decode(Envelope.self, from: data)
        let session = try envelope.session.validatedSession()
        try validateEventVocabulary(in: session, schemaVersion: envelope.schemaVersion)
        return session
    }

    private static func validateEventVocabulary(
        in session: PassiveBluetoothCaptureSession,
        schemaVersion: Int
    ) throws {
        guard schemaVersion == 1 else { return }
        for record in session.records {
            switch record.event {
            case .connection, .subscription:
                throw PassiveBluetoothCaptureValidationError.eventNotSupportedBySchemaVersion(schemaVersion)
            default:
                continue
            }
        }
    }
}
