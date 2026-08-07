import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth offline transcript")
struct PassiveBluetoothOfflineTranscriptTests {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func session() throws -> PassiveBluetoothCaptureSession {
        try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            vehicleIdentity: VehicleIdentity(
                manufacturer: "AOVOPRO",
                model: "ES80",
                displayName: "Research target",
                protocolFamily: "unverified"
            ),
            startedAt: baseDate
        )
    }

    private func value(
        origin: PassiveBluetoothValueOrigin,
        payload: [UInt8],
        peripheral: String = "PERIPHERAL-A",
        service: String = "SERVICE-1",
        characteristic: String = "CHAR-1"
    ) throws -> PassiveBluetoothCaptureEvent {
        .value(
            try PassiveBluetoothValueObservation(
                peripheralIdentifier: peripheral,
                serviceUUID: service,
                characteristicUUID: characteristic,
                origin: origin,
                payload: Data(payload)
            )
        )
    }

    @Test("equal uptime records preserve strict source sequence without fabricated clocks")
    func equalUptimePreservesSequence() throws {
        var capture = try session()
        try capture.append(
            value(origin: .subscriptionUpdate, payload: [0x01, 0x02]),
            sequenceNumber: 10,
            receivedAtUptimeNanoseconds: 500,
            receivedAtDate: baseDate
        )
        try capture.append(
            value(origin: .subscriptionUpdate, payload: [0x03]),
            sequenceNumber: 11,
            receivedAtUptimeNanoseconds: 500,
            receivedAtDate: baseDate.addingTimeInterval(0.001)
        )

        let transcript = try PassiveBluetoothOfflineTranscriptProjector.project(capture)
        #expect(transcript.values.map(\.sequenceNumber) == [10, 11])
        #expect(transcript.values.map(\.receivedAtUptimeNanoseconds) == [500, 500])
        #expect(transcript.values.map(\.sourceRecordIndex) == [0, 1])
        #expect(transcript.values.map(\.continuityGeneration) == [0, 0])
        #expect(transcript.values.map(\.payload) == [Data([0x01, 0x02]), Data([0x03])])
    }

    @Test("acquisition origin is part of exact stream identity")
    func originSeparatesStreams() throws {
        var capture = try session()
        try capture.append(
            value(origin: .readResponse, payload: [0xA0]),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: baseDate
        )
        try capture.append(
            value(origin: .subscriptionUpdate, payload: [0xB0]),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 101,
            receivedAtDate: baseDate
        )

        let transcript = try PassiveBluetoothOfflineTranscriptProjector.project(capture)
        let read = try #require(transcript.values.first)
        let subscribed = try #require(transcript.values.last)

        #expect(read.streamIdentity != subscribed.streamIdentity)
        #expect(read.streamIdentity.origin == .readResponse)
        #expect(subscribed.streamIdentity.origin == .subscriptionUpdate)
        #expect(read.streamIdentity.peripheralIdentifier == subscribed.streamIdentity.peripheralIdentifier)
        #expect(read.streamIdentity.serviceUUID == subscribed.streamIdentity.serviceUUID)
        #expect(read.streamIdentity.characteristicUUID == subscribed.streamIdentity.characteristicUUID)
    }

    @Test("known continuity breaks split later values without mutating source evidence")
    func continuityBoundarySplitsGeneration() throws {
        var capture = try session()
        try capture.append(
            value(origin: .notification, payload: [0x10]),
            sequenceNumber: 20,
            receivedAtUptimeNanoseconds: 1_000,
            receivedAtDate: baseDate
        )
        let interruption = PassiveBluetoothCaptureEvent.interruption(
            try PassiveBluetoothCaptureInterruption(reason: "observer restarted")
        )
        try capture.append(
            interruption,
            sequenceNumber: 21,
            receivedAtUptimeNanoseconds: 1_001,
            receivedAtDate: baseDate.addingTimeInterval(1)
        )
        try capture.append(
            value(origin: .notification, payload: [0x20]),
            sequenceNumber: 22,
            receivedAtUptimeNanoseconds: 1_002,
            receivedAtDate: baseDate.addingTimeInterval(2)
        )

        let transcript = try PassiveBluetoothOfflineTranscriptProjector.project(capture)
        #expect(transcript.values.map(\.continuityGeneration) == [0, 1])
        let boundary = try #require(transcript.continuityBoundaries.only)
        #expect(boundary.sourceRecordIndex == 1)
        #expect(boundary.sequenceNumber == 21)
        #expect(boundary.receivedAtUptimeNanoseconds == 1_001)
        #expect(boundary.generationBefore == 0)
        #expect(boundary.generationAfter == 1)
        #expect(boundary.sourceEvent == interruption)
    }

    @Test("structured disconnect is a byte boundary while connected callback is not")
    func disconnectSplitsButConnectedDoesNot() throws {
        var capture = try session()
        let connected = PassiveBluetoothCaptureEvent.connection(
            try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: "PERIPHERAL-A",
                state: .connected
            )
        )
        let disconnectedObservation = try PassiveBluetoothConnectionObservation(
            peripheralIdentifier: "PERIPHERAL-A",
            state: .disconnected,
            platformEventTimestamp: 42.5,
            isReconnecting: false,
            error: PassiveBluetoothErrorObservation(domain: "CBErrorDomain", code: 7)
        )
        let disconnected = PassiveBluetoothCaptureEvent.connection(disconnectedObservation)

        try capture.append(connected, sequenceNumber: 1, receivedAtUptimeNanoseconds: 10, receivedAtDate: baseDate)
        try capture.append(value(origin: .indication, payload: [1]), sequenceNumber: 2, receivedAtUptimeNanoseconds: 11, receivedAtDate: baseDate)
        try capture.append(disconnected, sequenceNumber: 3, receivedAtUptimeNanoseconds: 12, receivedAtDate: baseDate)
        try capture.append(value(origin: .indication, payload: [2]), sequenceNumber: 4, receivedAtUptimeNanoseconds: 13, receivedAtDate: baseDate)

        let transcript = try PassiveBluetoothOfflineTranscriptProjector.project(capture)
        #expect(transcript.values.map(\.continuityGeneration) == [0, 1])
        #expect(transcript.continuityBoundaries.count == 1)
        #expect(transcript.continuityBoundaries[0].sourceEvent == disconnected)
    }

    @Test("stock app markers retain exact source chronology and continuity generation")
    func markersRemainCorrelationEvidence() throws {
        var capture = try session()
        let before = try PassiveBluetoothStockAppObservation(
            field: "power",
            displayedValue: "0 W",
            note: "stationary"
        )
        let after = try PassiveBluetoothStockAppObservation(
            field: "power",
            displayedValue: "412 W",
            note: "short acceleration"
        )

        try capture.append(.stockAppState(before), sequenceNumber: 30, receivedAtUptimeNanoseconds: 2_000, receivedAtDate: baseDate)
        try capture.append(
            .interruption(try PassiveBluetoothCaptureInterruption(reason: "known gap")),
            sequenceNumber: 31,
            receivedAtUptimeNanoseconds: 2_001,
            receivedAtDate: baseDate
        )
        try capture.append(.stockAppState(after), sequenceNumber: 32, receivedAtUptimeNanoseconds: 2_001, receivedAtDate: baseDate.addingTimeInterval(0.5))

        let transcript = try PassiveBluetoothOfflineTranscriptProjector.project(capture)
        #expect(transcript.stockAppMarkers.count == 2)
        #expect(transcript.stockAppMarkers[0].observation == before)
        #expect(transcript.stockAppMarkers[0].continuityGeneration == 0)
        #expect(transcript.stockAppMarkers[1].observation == after)
        #expect(transcript.stockAppMarkers[1].continuityGeneration == 1)
        #expect(transcript.stockAppMarkers[1].receivedAtUptimeNanoseconds == 2_001)
        #expect(transcript.stockAppMarkers[1].sequenceNumber == 32)
    }

    @Test("projection preserves session metadata and never manufactures evidence")
    func emptyAndNonValueCaptureRemainSparse() throws {
        var capture = try session()
        let subscription = try PassiveBluetoothSubscriptionObservation(
            peripheralIdentifier: "PERIPHERAL-A",
            serviceUUID: "SERVICE-1",
            characteristicUUID: "CHAR-1",
            requestedEnabled: true,
            resultingIsNotifying: true
        )
        try capture.append(
            .subscription(subscription),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: baseDate
        )

        let transcript = try PassiveBluetoothOfflineTranscriptProjector.project(capture)
        #expect(transcript.captureSessionID == capture.id)
        #expect(transcript.captureStartedAt == capture.startedAt)
        #expect(transcript.sourceRecordCount == 1)
        #expect(transcript.values.isEmpty)
        #expect(transcript.stockAppMarkers.isEmpty)
        #expect(transcript.continuityBoundaries.isEmpty)
    }
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}
