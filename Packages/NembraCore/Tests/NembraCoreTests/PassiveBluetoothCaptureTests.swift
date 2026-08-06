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

    @Test("raw advertisement bytes and CoreBluetooth discovery fields survive capture unchanged")
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

    @Test("captured value origins contain no motorized write action and permit ambiguous subscription delivery")
    func valueOriginsAreNonMutating() {
        #expect(Set(PassiveBluetoothValueOrigin.allCases) == [.notification, .indication, .subscriptionUpdate, .readResponse])
    }

    @Test("characteristic security properties survive capture without authorizing writes")
    func preservesCharacteristicSecurityProperties() throws {
        let characteristic = try PassiveBluetoothCharacteristicObservation(
            peripheralIdentifier: "physical-es80-placeholder",
            serviceUUID: "FD50",
            characteristicUUID: "00000001-0000-0000-0000-000000000000",
            properties: [.read, .notify, .notifyEncryptionRequired, .write, .indicateEncryptionRequired]
        )
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: .now)
        try session.append(
            .characteristic(characteristic),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: .now
        )

        let decoded = try PassiveBluetoothCaptureJSON.decode(PassiveBluetoothCaptureJSON.encode(session))
        guard case let .characteristic(captured) = decoded.records[0].event else {
            Issue.record("Expected characteristic event")
            return
        }
        #expect(captured.properties == [.read, .notify, .notifyEncryptionRequired, .write, .indicateEncryptionRequired])
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

    @Test("JSON export round trips raw bytes, identity, continuity markers, and sub-second dates")
    func jsonRoundTrip() throws {
        let value = try PassiveBluetoothValueObservation(
            peripheralIdentifier: "physical-es80-placeholder",
            serviceUUID: "FD50",
            characteristicUUID: "00000001-0000-0000-0000-000000000000",
            origin: .subscriptionUpdate,
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
        let decoded = try PassiveBluetoothCaptureJSON.decode(data)
        #expect(decoded == session)
    }

    @Test("JSON import cannot bypass record ordering validation")
    func jsonImportRevalidatesRecordOrder() throws {
        struct UncheckedSessionPayload: Encodable {
            let id: UUID
            let vehicleIdentity: VehicleIdentity
            let startedAt: Date
            let records: [PassiveBluetoothCaptureRecord]
        }

        let gap = try PassiveBluetoothCaptureInterruption(reason: "fixture")
        let event = PassiveBluetoothCaptureEvent.interruption(gap)
        let payload = UncheckedSessionPayload(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000082")!,
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 2_000),
            records: [
                PassiveBluetoothCaptureRecord(
                    sequenceNumber: 2,
                    receivedAtUptimeNanoseconds: 20,
                    receivedAtDate: Date(timeIntervalSince1970: 2_001),
                    event: event
                ),
                PassiveBluetoothCaptureRecord(
                    sequenceNumber: 1,
                    receivedAtUptimeNanoseconds: 21,
                    receivedAtDate: Date(timeIntervalSince1970: 2_002),
                    event: event
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(payload)

        #expect(throws: PassiveBluetoothCaptureValidationError.nonMonotonicSequence) {
            _ = try PassiveBluetoothCaptureJSON.decode(data)
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

    @Test("invalid blank identifiers fail closed instead of creating plausible evidence")
    func rejectsBlankIdentifiers() {
        #expect(throws: PassiveBluetoothCaptureValidationError.emptyBluetoothIdentifier) {
            _ = try PassiveBluetoothServiceObservation(
                peripheralIdentifier: "physical-es80-placeholder",
                serviceUUID: "   ",
                isPrimary: true
            )
        }
    }
}
