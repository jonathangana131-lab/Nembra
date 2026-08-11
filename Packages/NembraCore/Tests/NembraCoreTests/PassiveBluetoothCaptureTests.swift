import Foundation
import Testing
@testable import NembraCore

@Suite("Passive Bluetooth protocol capture")
struct PassiveBluetoothCaptureTests {
    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    @Test("raw advertisement bytes and unknown identifiers survive capture unchanged")
    func preservesRawAdvertisementEvidence() throws {
        let advertisement = try PassiveBluetoothAdvertisementObservation(
            peripheralIdentifier: "physical-es80-placeholder",
            localName: "Observed Name",
            rssi: -58,
            isConnectable: true,
            manufacturerData: Data([0x12, 0x34, 0xAB, 0xCD]),
            serviceUUIDs: ["FD50", "12345678-1234-5678-1234-567812345678"],
            overflowServiceUUIDs: ["ABCD"],
            solicitedServiceUUIDs: ["DCBA"],
            serviceData: ["FD50": Data([0xAA, 0x55])],
            txPowerLevel: -8
        )

        var session = try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000080")!,
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )
        try session.append(
            .advertisement(advertisement),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 10,
            receivedAtDate: Date(timeIntervalSince1970: 1_001)
        )

        #expect(session.records.count == 1)
        guard case let .advertisement(captured) = session.records[0].event else {
            Issue.record("Expected advertisement event")
            return
        }
        #expect(captured.manufacturerData == Data([0x12, 0x34, 0xAB, 0xCD]))
        #expect(captured.serviceUUIDs == ["FD50", "12345678-1234-5678-1234-567812345678"])
        #expect(captured.overflowServiceUUIDs == ["ABCD"])
        #expect(captured.solicitedServiceUUIDs == ["DCBA"])
        #expect(captured.serviceData["FD50"] == Data([0xAA, 0x55]))
        #expect(captured.txPowerLevel == -8)
    }

    @Test("characteristic security properties survive capture without authorizing writes")
    func preservesCharacteristicSecurityProperties() throws {
        let characteristic = try PassiveBluetoothCharacteristicObservation(
            peripheralIdentifier: "physical-es80-placeholder",
            serviceUUID: "FD50",
            characteristicUUID: "FFE1",
            properties: [.read, .notify, .notifyEncryptionRequired, .write, .indicateEncryptionRequired]
        )
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: Date(timeIntervalSince1970: 1_500))
        try session.append(
            .characteristic(characteristic),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 15,
            receivedAtDate: Date(timeIntervalSince1970: 1_501)
        )

        let decoded = try PassiveBluetoothCaptureJSON.decode(PassiveBluetoothCaptureJSON.encode(session))
        guard case let .characteristic(captured) = decoded.records[0].event else {
            Issue.record("Expected characteristic event")
            return
        }
        #expect(captured.properties == [.read, .notify, .notifyEncryptionRequired, .write, .indicateEncryptionRequired])
        #expect(Set(PassiveBluetoothValueOrigin.allCases).contains(.subscriptionUpdate))
    }

    @Test("characteristic property arrays encode in deterministic raw-value order")
    func characteristicPropertiesEncodeDeterministically() throws {
        let characteristic = try PassiveBluetoothCharacteristicObservation(
            peripheralIdentifier: "physical-es80-placeholder",
            serviceUUID: "FD50",
            characteristicUUID: "FFE1",
            properties: Set(PassiveBluetoothCharacteristicProperty.allCases)
        )
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: Date(timeIntervalSince1970: 1_550))
        try session.append(
            .characteristic(characteristic),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 15,
            receivedAtDate: Date(timeIntervalSince1970: 1_551)
        )

        let data = try PassiveBluetoothCaptureJSON.encode(session, prettyPrinted: false)
        let json = String(decoding: data, as: UTF8.self)
        let expectedProperties = PassiveBluetoothCharacteristicProperty.allCases
            .map(\.rawValue)
            .sorted()
            .map { "\"\($0)\"" }
            .joined(separator: ",")
        #expect(json.contains("\"properties\":[\(expectedProperties)]"))
    }

    @Test("included-service relationships survive versioned capture round trip")
    func preservesIncludedServiceRelationships() throws {
        let included = try PassiveBluetoothIncludedServiceObservation(
            peripheralIdentifier: "physical-es80-placeholder",
            parentServiceUUID: "FD50",
            includedServiceUUID: "180A",
            includedServiceIsPrimary: false
        )
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: Date(timeIntervalSince1970: 1_600))
        try session.append(
            .includedService(included),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 16,
            receivedAtDate: Date(timeIntervalSince1970: 1_601)
        )

        let decoded = try PassiveBluetoothCaptureJSON.decode(PassiveBluetoothCaptureJSON.encode(session))
        guard case let .includedService(captured) = decoded.records[0].event else {
            Issue.record("Expected included-service event")
            return
        }
        #expect(captured.parentServiceUUID == "FD50")
        #expect(captured.includedServiceUUID == "180A")
        #expect(captured.includedServiceIsPrimary == false)
    }

    @Test("descriptor UUID discovery survives versioned capture round trip")
    func preservesDescriptorDiscovery() throws {
        let descriptor = try PassiveBluetoothDescriptorObservation(
            peripheralIdentifier: "physical-es80-placeholder",
            serviceUUID: "FD50",
            characteristicUUID: "00000002-0000-1001-8001-00805F9B07D0",
            descriptorUUID: "2902"
        )
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: Date(timeIntervalSince1970: 1_700))
        try session.append(
            .descriptor(descriptor),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 17,
            receivedAtDate: Date(timeIntervalSince1970: 1_701)
        )

        let decoded = try PassiveBluetoothCaptureJSON.decode(PassiveBluetoothCaptureJSON.encode(session))
        guard case let .descriptor(captured) = decoded.records[0].event else {
            Issue.record("Expected descriptor event")
            return
        }
        #expect(captured.serviceUUID == "FD50")
        #expect(captured.characteristicUUID == "00000002-0000-1001-8001-00805F9B07D0")
        #expect(captured.descriptorUUID == "2902")
    }

    @Test("connection callbacks preserve structured state, platform timestamp, reconnect flag, and error evidence")
    func preservesStructuredConnectionLifecycle() throws {
        let disconnectError = try PassiveBluetoothErrorObservation(domain: "CBErrorDomain", code: 7)
        let disconnected = try PassiveBluetoothConnectionObservation(
            peripheralIdentifier: "physical-es80-placeholder",
            state: .disconnected,
            platformEventTimestamp: 812_345.25,
            isReconnecting: true,
            error: disconnectError
        )
        let failed = try PassiveBluetoothConnectionObservation(
            peripheralIdentifier: "physical-es80-placeholder",
            state: .failedToConnect,
            error: try PassiveBluetoothErrorObservation(domain: "CBErrorDomain", code: 10)
        )

        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: Date(timeIntervalSince1970: 1_800))
        try session.append(
            .connection(disconnected),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 18,
            receivedAtDate: Date(timeIntervalSince1970: 1_801)
        )
        try session.append(
            .connection(failed),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 19,
            receivedAtDate: Date(timeIntervalSince1970: 1_802)
        )

        let decoded = try PassiveBluetoothCaptureJSON.decode(PassiveBluetoothCaptureJSON.encode(session))
        guard case let .connection(capturedDisconnect) = decoded.records[0].event,
              case let .connection(capturedFailure) = decoded.records[1].event else {
            Issue.record("Expected structured connection events")
            return
        }
        #expect(capturedDisconnect.state == .disconnected)
        #expect(capturedDisconnect.platformEventTimestamp == 812_345.25)
        #expect(capturedDisconnect.isReconnecting == true)
        #expect(capturedDisconnect.error == disconnectError)
        #expect(capturedFailure.state == .failedToConnect)
        #expect(capturedFailure.platformEventTimestamp == nil)
        #expect(capturedFailure.isReconnecting == nil)
        #expect(capturedFailure.error?.code == 10)
    }

    @Test("connection metadata fails closed when platform-only fields contradict callback state")
    func rejectsContradictoryConnectionMetadata() {
        #expect(throws: PassiveBluetoothCaptureValidationError.invalidConnectionMetadata) {
            _ = try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: "physical-es80-placeholder",
                state: .connected,
                platformEventTimestamp: 1
            )
        }
        #expect(throws: PassiveBluetoothCaptureValidationError.invalidConnectionMetadata) {
            _ = try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: "physical-es80-placeholder",
                state: .connected,
                error: try PassiveBluetoothErrorObservation(domain: "CBErrorDomain", code: 1)
            )
        }
        #expect(throws: PassiveBluetoothCaptureValidationError.nonFinitePlatformEventTimestamp) {
            _ = try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: "physical-es80-placeholder",
                state: .disconnected,
                platformEventTimestamp: .infinity
            )
        }
    }

    @Test("disconnect and explicit interruption are byte-continuity boundaries")
    func continuityBoundarySemanticsAreExplicit() throws {
        let connected = try PassiveBluetoothConnectionObservation(
            peripheralIdentifier: "physical-es80-placeholder",
            state: .connected
        )
        let disconnected = try PassiveBluetoothConnectionObservation(
            peripheralIdentifier: "physical-es80-placeholder",
            state: .disconnected
        )
        let interruption = try PassiveBluetoothCaptureInterruption(reason: "observer restart")
        let subscription = try PassiveBluetoothSubscriptionObservation(
            peripheralIdentifier: "physical-es80-placeholder",
            serviceUUID: "FD50",
            characteristicUUID: "FFE2",
            requestedEnabled: true,
            resultingIsNotifying: true
        )

        #expect(PassiveBluetoothCaptureEvent.connection(disconnected).breaksByteContinuity)
        #expect(PassiveBluetoothCaptureEvent.interruption(interruption).breaksByteContinuity)
        #expect(!PassiveBluetoothCaptureEvent.connection(connected).breaksByteContinuity)
        #expect(!PassiveBluetoothCaptureEvent.subscription(subscription).breaksByteContinuity)
    }

    @Test("subscription callbacks preserve request context, resulting state, and failure evidence")
    func preservesSubscriptionStateAndResult() throws {
        let subscriptionError = try PassiveBluetoothErrorObservation(domain: "CBATTErrorDomain", code: 14)
        let subscription = try PassiveBluetoothSubscriptionObservation(
            peripheralIdentifier: "physical-es80-placeholder",
            serviceUUID: "FD50",
            characteristicUUID: "00000002-0000-1001-8001-00805F9B07D0",
            requestedEnabled: true,
            resultingIsNotifying: false,
            error: subscriptionError
        )
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: Date(timeIntervalSince1970: 1_900))
        try session.append(
            .subscription(subscription),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 20,
            receivedAtDate: Date(timeIntervalSince1970: 1_901)
        )

        let decoded = try PassiveBluetoothCaptureJSON.decode(PassiveBluetoothCaptureJSON.encode(session))
        guard case let .subscription(captured) = decoded.records[0].event else {
            Issue.record("Expected subscription event")
            return
        }
        #expect(captured.requestedEnabled == true)
        #expect(captured.resultingIsNotifying == false)
        #expect(captured.error == subscriptionError)
    }

    @Test("value origins remain non-mutating and permit ambiguous subscription delivery")
    func valueOriginsAreNonMutating() {
        #expect(Set(PassiveBluetoothValueOrigin.allCases) == [.notification, .indication, .subscriptionUpdate, .readResponse])
    }

    @Test("session rejects sequence regression")
    func rejectsSequenceRegression() throws {
        let interruption = try PassiveBluetoothCaptureInterruption(reason: "observer restart")
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: .now)
        try session.append(
            .interruption(interruption),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 20,
            receivedAtDate: .now
        )

        #expect(throws: PassiveBluetoothCaptureValidationError.nonMonotonicSequence) {
            try session.append(
                .interruption(interruption),
                sequenceNumber: 2,
                receivedAtUptimeNanoseconds: 21,
                receivedAtDate: .now
            )
        }
    }

    @Test("session rejects uptime regression even when wall clock moves forward")
    func rejectsUptimeRegression() throws {
        let interruption = try PassiveBluetoothCaptureInterruption(reason: "Bluetooth transition")
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: Date(timeIntervalSince1970: 100))
        try session.append(
            .interruption(interruption),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: Date(timeIntervalSince1970: 101)
        )

        #expect(throws: PassiveBluetoothCaptureValidationError.nonMonotonicReceiptTime) {
            try session.append(
                .interruption(interruption),
                sequenceNumber: 2,
                receivedAtUptimeNanoseconds: 99,
                receivedAtDate: Date(timeIntervalSince1970: 999)
            )
        }
    }

    @Test("stock app markers remain correlation evidence rather than decoded protocol claims")
    func recordsStockAppCorrelationMarker() throws {
        let marker = try PassiveBluetoothStockAppObservation(
            field: "Battery",
            displayedValue: "73%",
            note: "Observed in stock Tuya UI during capture"
        )
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: .now)
        try session.append(
            .stockAppState(marker),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: .now
        )

        guard case let .stockAppState(captured) = session.records[0].event else {
            Issue.record("Expected stock-app marker")
            return
        }
        #expect(captured.field == "Battery")
        #expect(captured.displayedValue == "73%")
    }

    @Test("JSON export round trips raw bytes, identity, and continuity markers")
    func jsonRoundTrip() throws {
        let value = try PassiveBluetoothValueObservation(
            peripheralIdentifier: "physical-es80-placeholder",
            serviceUUID: "FD50",
            characteristicUUID: "00000001-0000-0000-0000-000000000000",
            origin: .notification,
            payload: Data([0x55, 0xAA, 0x01, 0x7F])
        )
        let gap = try PassiveBluetoothCaptureInterruption(reason: "disconnect")
        var session = try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000081")!,
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1_000.123)
        )
        try session.append(.value(value), sequenceNumber: 1, receivedAtUptimeNanoseconds: 10, receivedAtDate: Date(timeIntervalSince1970: 1_001.456))
        try session.append(.interruption(gap), sequenceNumber: 2, receivedAtUptimeNanoseconds: 11, receivedAtDate: Date(timeIntervalSince1970: 1_002.789))

        let data = try PassiveBluetoothCaptureJSON.encode(session)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == PassiveBluetoothCaptureJSON.currentSchemaVersion)

        let decoded = try PassiveBluetoothCaptureJSON.decode(data)
        #expect(decoded == session)
    }

    @Test("schema v1 captures remain readable after adding structured lifecycle evidence")
    func decodesSchemaV1Capture() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: Date(timeIntervalSince1970: 1_950))
        try session.append(
            .interruption(try PassiveBluetoothCaptureInterruption(reason: "legacy fixture")),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: Date(timeIntervalSince1970: 1_951)
        )

        let encoded = try PassiveBluetoothCaptureJSON.encode(session, prettyPrinted: false)
        let currentToken = "\"schemaVersion\":\(PassiveBluetoothCaptureJSON.currentSchemaVersion)"
        var json = String(decoding: encoded, as: UTF8.self)
        #expect(json.contains(currentToken))
        json = json.replacingOccurrences(of: currentToken, with: "\"schemaVersion\":1")

        #expect(try PassiveBluetoothCaptureJSON.decode(Data(json.utf8)) == session)
    }

    @Test("schema v1 rejects v2-only connection and subscription events")
    func schemaV1RejectsV2OnlyEventVocabulary() throws {
        let events: [PassiveBluetoothCaptureEvent] = [
            .connection(
                try PassiveBluetoothConnectionObservation(
                    peripheralIdentifier: "physical-es80-placeholder",
                    state: .connected
                )
            ),
            .subscription(
                try PassiveBluetoothSubscriptionObservation(
                    peripheralIdentifier: "physical-es80-placeholder",
                    serviceUUID: "FD50",
                    characteristicUUID: "FFE2",
                    requestedEnabled: true,
                    resultingIsNotifying: true
                )
            )
        ]

        for (offset, event) in events.enumerated() {
            var session = try PassiveBluetoothCaptureSession(
                vehicleIdentity: es80,
                startedAt: Date(timeIntervalSince1970: 2_000 + Double(offset))
            )
            try session.append(
                event,
                sequenceNumber: 1,
                receivedAtUptimeNanoseconds: UInt64(offset + 1),
                receivedAtDate: Date(timeIntervalSince1970: 2_001 + Double(offset))
            )

            let encoded = try PassiveBluetoothCaptureJSON.encode(session, prettyPrinted: false)
            let currentToken = "\"schemaVersion\":\(PassiveBluetoothCaptureJSON.currentSchemaVersion)"
            var json = String(decoding: encoded, as: UTF8.self)
            #expect(json.contains(currentToken))
            json = json.replacingOccurrences(of: currentToken, with: "\"schemaVersion\":1")

            #expect(throws: PassiveBluetoothCaptureValidationError.eventNotSupportedBySchemaVersion(1)) {
                _ = try PassiveBluetoothCaptureJSON.decode(Data(json.utf8))
            }
        }
    }

    @Test("JSON import cannot bypass record ordering validation")
    func jsonImportRevalidatesRecordOrder() throws {
        struct UncheckedSessionPayload: Encodable {
            let id: UUID
            let vehicleIdentity: VehicleIdentity
            let startedAt: Date
            let records: [PassiveBluetoothCaptureRecord]
        }

        struct UncheckedEnvelope: Encodable {
            let schemaVersion: Int
            let session: UncheckedSessionPayload
        }

        let gap = try PassiveBluetoothCaptureInterruption(reason: "fixture")
        let event = PassiveBluetoothCaptureEvent.interruption(gap)
        let payload = UncheckedSessionPayload(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000082")!,
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 2_100),
            records: [
                PassiveBluetoothCaptureRecord(
                    sequenceNumber: 2,
                    receivedAtUptimeNanoseconds: 20,
                    receivedAtDate: Date(timeIntervalSince1970: 2_101),
                    event: event
                ),
                PassiveBluetoothCaptureRecord(
                    sequenceNumber: 1,
                    receivedAtUptimeNanoseconds: 21,
                    receivedAtDate: Date(timeIntervalSince1970: 2_102),
                    event: event
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(
            UncheckedEnvelope(
                schemaVersion: PassiveBluetoothCaptureJSON.currentSchemaVersion,
                session: payload
            )
        )

        #expect(throws: PassiveBluetoothCaptureValidationError.nonMonotonicSequence) {
            _ = try PassiveBluetoothCaptureJSON.decode(data)
        }
    }

    @Test("JSON import rejects unsupported schema versions")
    func rejectsUnsupportedSchemaVersion() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: Date(timeIntervalSince1970: 2_500))
        try session.append(
            .interruption(try PassiveBluetoothCaptureInterruption(reason: "schema fixture")),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: Date(timeIntervalSince1970: 2_501)
        )

        let encoded = try PassiveBluetoothCaptureJSON.encode(session, prettyPrinted: false)
        let currentToken = "\"schemaVersion\":\(PassiveBluetoothCaptureJSON.currentSchemaVersion)"
        var json = String(decoding: encoded, as: UTF8.self)
        #expect(json.contains(currentToken))
        json = json.replacingOccurrences(of: currentToken, with: "\"schemaVersion\":999")

        #expect(throws: PassiveBluetoothCaptureValidationError.unsupportedSchemaVersion(999)) {
            _ = try PassiveBluetoothCaptureJSON.decode(Data(json.utf8))
        }
    }

    @Test("JSON import cannot bypass nested evidence validation")
    func jsonImportRevalidatesNestedEvidence() throws {
        let service = try PassiveBluetoothServiceObservation(
            peripheralIdentifier: "physical-es80-placeholder",
            serviceUUID: "FD50",
            isPrimary: true
        )
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: Date(timeIntervalSince1970: 3_000))
        try session.append(
            .service(service),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 30,
            receivedAtDate: Date(timeIntervalSince1970: 3_001)
        )

        let encoded = try PassiveBluetoothCaptureJSON.encode(session, prettyPrinted: false)
        var json = String(decoding: encoded, as: UTF8.self)
        #expect(json.contains("\"serviceUUID\":\"FD50\""))
        json = json.replacingOccurrences(of: "\"serviceUUID\":\"FD50\"", with: "\"serviceUUID\":\"   \"")

        #expect(throws: PassiveBluetoothCaptureValidationError.emptyBluetoothIdentifier) {
            _ = try PassiveBluetoothCaptureJSON.decode(Data(json.utf8))
        }
    }

    @Test("JSON import revalidates nested error evidence")
    func jsonImportRevalidatesNestedErrorEvidence() throws {
        let subscription = try PassiveBluetoothSubscriptionObservation(
            peripheralIdentifier: "physical-es80-placeholder",
            serviceUUID: "FD50",
            characteristicUUID: "FFE2",
            requestedEnabled: true,
            resultingIsNotifying: false,
            error: try PassiveBluetoothErrorObservation(domain: "CBATTErrorDomain", code: 14)
        )
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: Date(timeIntervalSince1970: 3_100))
        try session.append(
            .subscription(subscription),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 31,
            receivedAtDate: Date(timeIntervalSince1970: 3_101)
        )

        let encoded = try PassiveBluetoothCaptureJSON.encode(session, prettyPrinted: false)
        var json = String(decoding: encoded, as: UTF8.self)
        #expect(json.contains("\"domain\":\"CBATTErrorDomain\""))
        json = json.replacingOccurrences(of: "\"domain\":\"CBATTErrorDomain\"", with: "\"domain\":\"   \"")

        #expect(throws: PassiveBluetoothCaptureValidationError.emptyErrorDomain) {
            _ = try PassiveBluetoothCaptureJSON.decode(Data(json.utf8))
        }
    }

    @Test("invalid blank identifiers fail closed instead of creating plausible evidence")
    func rejectsBlankIdentifiers() {
        #expect(throws: PassiveBluetoothCaptureValidationError.emptyBluetoothIdentifier) {
            _ = try PassiveBluetoothServiceObservation(
                peripheralIdentifier: "physical-es80-placeholder",
                serviceUUID: "   ",
                isPrimary: true
            )
        }
        #expect(throws: PassiveBluetoothCaptureValidationError.emptyBluetoothIdentifier) {
            _ = try PassiveBluetoothDescriptorObservation(
                peripheralIdentifier: "physical-es80-placeholder",
                serviceUUID: "FD50",
                characteristicUUID: "FFE1",
                descriptorUUID: " "
            )
        }
        #expect(throws: PassiveBluetoothCaptureValidationError.emptyErrorDomain) {
            _ = try PassiveBluetoothErrorObservation(domain: " ", code: 1)
        }
    }
}
