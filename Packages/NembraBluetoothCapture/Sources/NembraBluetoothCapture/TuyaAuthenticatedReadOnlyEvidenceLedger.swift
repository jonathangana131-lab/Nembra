import Foundation

/// Physical target constants already established by Capture C7D09A22.
/// Keeping the notify UUID exact prevents authenticated bytes from another characteristic
/// from being promoted into the ES80 application-payload evidence stream.
public enum TuyaFD50AuthenticatedReadOnlyTarget: Sendable {
    public static let transportFamily = "tuya-fd50"
    public static let serviceUUID = "FD50"
    public static let notificationCharacteristicUUID = "00000002-0000-1001-8001-00805F9B07D0"
}

public struct TuyaAuthenticatedReadOnlyNotificationReceipt: Equatable, Sendable {
    public let receiptIndex: UInt64
    public let connectionGeneration: UInt64
    public let monotonicNanoseconds: UInt64
    public let characteristicUUID: String
    public let payload: Data

    fileprivate init(
        receiptIndex: UInt64,
        connectionGeneration: UInt64,
        monotonicNanoseconds: UInt64,
        characteristicUUID: String,
        payload: Data
    ) {
        self.receiptIndex = receiptIndex
        self.connectionGeneration = connectionGeneration
        self.monotonicNanoseconds = monotonicNanoseconds
        self.characteristicUUID = characteristicUUID
        self.payload = payload
    }
}

/// Immutable evidence from exactly one authenticated connection generation.
/// Authentication credential fields are intentionally absent from the type, so callers cannot
/// accidentally serialize a local/session/auth key beside the admitted application bytes.
public struct TuyaAuthenticatedReadOnlyEvidenceArtifact: Equatable, Sendable {
    public struct RedactionContract: Encodable, Equatable, Sendable {
        public let accountPasswordExcluded: Bool
        public let cloudTokenExcluded: Bool
        public let appSecretExcluded: Bool
        public let localKeyExcluded: Bool
        public let sessionKeyExcluded: Bool
        public let authKeyExcluded: Bool
        public let qrAuthorizationTokenExcluded: Bool

        public init() {
            accountPasswordExcluded = true
            cloudTokenExcluded = true
            appSecretExcluded = true
            localKeyExcluded = true
            sessionKeyExcluded = true
            authKeyExcluded = true
            qrAuthorizationTokenExcluded = true
        }
    }

    public let connectionGeneration: UInt64
    public let authenticatedAtUptimeNanoseconds: UInt64
    public let latestObservedUptimeNanoseconds: UInt64
    public let authMethod: TuyaReadOnlyAuthenticationMethod
    public let notifications: [TuyaAuthenticatedReadOnlyNotificationReceipt]
    public let redactions = RedactionContract()

    fileprivate init(
        connectionGeneration: UInt64,
        authenticatedAtUptimeNanoseconds: UInt64,
        latestObservedUptimeNanoseconds: UInt64,
        authMethod: TuyaReadOnlyAuthenticationMethod,
        notifications: [TuyaAuthenticatedReadOnlyNotificationReceipt]
    ) {
        self.connectionGeneration = connectionGeneration
        self.authenticatedAtUptimeNanoseconds = authenticatedAtUptimeNanoseconds
        self.latestObservedUptimeNanoseconds = latestObservedUptimeNanoseconds
        self.authMethod = authMethod
        self.notifications = notifications
    }

    public var preflightSnapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot {
        TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: authMethod,
            connectionStartedAtUptimeNanoseconds: nil,
            authenticatedAtUptimeNanoseconds: authenticatedAtUptimeNanoseconds,
            latestObservedUptimeNanoseconds: latestObservedUptimeNanoseconds,
            applicationPayloadCount: notifications.count,
            connectionGeneration: connectionGeneration
        )
    }

    public var preflightVerdict: TuyaAuthenticatedReadOnlyPreflight.Verdict {
        TuyaAuthenticatedReadOnlyPreflight.verdict(for: preflightSnapshot)
    }

    public func encodedJSON() throws -> Data {
        struct Export: Encodable {
            struct Notification: Encodable {
                let receiptIndex: UInt64
                let monotonicNanoseconds: UInt64
                let characteristicUUID: String
                let payloadBase64: String
                let payloadHex: String
            }

            let schemaVersion: Int
            let artifactType: String
            let transportFamily: String
            let authMethod: TuyaReadOnlyAuthenticationMethod
            let connectionGeneration: UInt64
            let authenticatedAtUptimeNanoseconds: UInt64
            let latestObservedUptimeNanoseconds: UInt64
            let applicationNotificationCount: Int
            let notifications: [Notification]
            let redactions: RedactionContract
        }

        let export = Export(
            schemaVersion: 1,
            artifactType: "NembraTuyaAuthenticatedReadOnlyEvidence",
            transportFamily: TuyaFD50AuthenticatedReadOnlyTarget.transportFamily,
            authMethod: authMethod,
            connectionGeneration: connectionGeneration,
            authenticatedAtUptimeNanoseconds: authenticatedAtUptimeNanoseconds,
            latestObservedUptimeNanoseconds: latestObservedUptimeNanoseconds,
            applicationNotificationCount: notifications.count,
            notifications: notifications.map { receipt in
                Export.Notification(
                    receiptIndex: receipt.receiptIndex,
                    monotonicNanoseconds: receipt.monotonicNanoseconds,
                    characteristicUUID: receipt.characteristicUUID,
                    payloadBase64: receipt.payload.base64EncodedString(),
                    payloadHex: receipt.payload.map { String(format: "%02x", $0) }.joined()
                )
            },
            redactions: redactions
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(export)
    }
}

/// Single-generation admission ledger for the next authenticated physical preflight.
///
/// The ledger never performs BLE writes and never receives credentials. Its only authority is to
/// preserve already-authenticated application notification evidence in receipt order and seal it.
public actor TuyaAuthenticatedReadOnlyEvidenceLedger {
    public enum AdmissionError: Error, Equatable, Sendable {
        case invalidConnectionGeneration
        case invalidAuthenticatedUptime
        case generationMismatch
        case emptyPayload
        case unexpectedCharacteristic
        case nonMonotonicUptime
        case receiptIndexOverflow
        case sealed
    }

    private let connectionGeneration: UInt64
    private let authenticatedAtUptimeNanoseconds: UInt64
    private let authMethod: TuyaReadOnlyAuthenticationMethod
    private let expectedNotificationCharacteristicUUID: String

    private var latestObservedUptimeNanoseconds: UInt64
    private var nextReceiptIndex: UInt64 = 1
    private var notifications: [TuyaAuthenticatedReadOnlyNotificationReceipt] = []
    private var sealedArtifact: TuyaAuthenticatedReadOnlyEvidenceArtifact?

    public init(
        connectionGeneration: UInt64,
        authenticatedAtUptimeNanoseconds: UInt64,
        authMethod: TuyaReadOnlyAuthenticationMethod,
        expectedNotificationCharacteristicUUID: String = TuyaFD50AuthenticatedReadOnlyTarget.notificationCharacteristicUUID
    ) throws {
        guard connectionGeneration > 0 else { throw AdmissionError.invalidConnectionGeneration }
        guard authenticatedAtUptimeNanoseconds > 0 else { throw AdmissionError.invalidAuthenticatedUptime }
        self.connectionGeneration = connectionGeneration
        self.authenticatedAtUptimeNanoseconds = authenticatedAtUptimeNanoseconds
        self.authMethod = authMethod
        self.expectedNotificationCharacteristicUUID = Self.normalizeUUID(expectedNotificationCharacteristicUUID)
        self.latestObservedUptimeNanoseconds = authenticatedAtUptimeNanoseconds
    }

    /// Records source-owned evidence that this authenticated generation is still connected.
    /// This is deliberately separate from receipt admission so a quiet authenticated link can prove
    /// survival beyond the old ~30-second rejection window without inventing application payloads.
    public func observeAuthenticatedConnectionAlive(
        connectionGeneration: UInt64,
        monotonicNanoseconds: UInt64
    ) throws {
        try requireOpenGeneration(connectionGeneration)
        try advanceUptime(monotonicNanoseconds)
    }

    public func admitApplicationNotification(
        connectionGeneration: UInt64,
        monotonicNanoseconds: UInt64,
        characteristicUUID: String,
        payload: Data
    ) throws {
        try requireOpenGeneration(connectionGeneration)
        guard !payload.isEmpty else { throw AdmissionError.emptyPayload }
        guard Self.normalizeUUID(characteristicUUID) == expectedNotificationCharacteristicUUID else {
            throw AdmissionError.unexpectedCharacteristic
        }
        try advanceUptime(monotonicNanoseconds)
        guard nextReceiptIndex != .max else { throw AdmissionError.receiptIndexOverflow }

        notifications.append(
            TuyaAuthenticatedReadOnlyNotificationReceipt(
                receiptIndex: nextReceiptIndex,
                connectionGeneration: self.connectionGeneration,
                monotonicNanoseconds: monotonicNanoseconds,
                characteristicUUID: expectedNotificationCharacteristicUUID,
                payload: payload
            )
        )
        nextReceiptIndex += 1
    }

    /// Freezes the exact admitted prefix. No caller-supplied time is accepted at seal, so finishing
    /// cannot manufacture extra authenticated survival time.
    public func seal() throws -> TuyaAuthenticatedReadOnlyEvidenceArtifact {
        if let sealedArtifact { return sealedArtifact }
        let artifact = TuyaAuthenticatedReadOnlyEvidenceArtifact(
            connectionGeneration: connectionGeneration,
            authenticatedAtUptimeNanoseconds: authenticatedAtUptimeNanoseconds,
            latestObservedUptimeNanoseconds: latestObservedUptimeNanoseconds,
            authMethod: authMethod,
            notifications: notifications
        )
        sealedArtifact = artifact
        return artifact
    }

    public func currentPreflightSnapshot() -> TuyaAuthenticatedReadOnlyPreflightSnapshot {
        TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: authMethod,
            connectionStartedAtUptimeNanoseconds: nil,
            authenticatedAtUptimeNanoseconds: authenticatedAtUptimeNanoseconds,
            latestObservedUptimeNanoseconds: latestObservedUptimeNanoseconds,
            applicationPayloadCount: notifications.count,
            connectionGeneration: connectionGeneration
        )
    }

    private func requireOpenGeneration(_ suppliedGeneration: UInt64) throws {
        guard sealedArtifact == nil else { throw AdmissionError.sealed }
        guard suppliedGeneration == connectionGeneration else { throw AdmissionError.generationMismatch }
    }

    private func advanceUptime(_ uptime: UInt64) throws {
        guard uptime >= authenticatedAtUptimeNanoseconds,
              uptime >= latestObservedUptimeNanoseconds else {
            throw AdmissionError.nonMonotonicUptime
        }
        latestObservedUptimeNanoseconds = uptime
    }

    private static func normalizeUUID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
