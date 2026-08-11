import Foundation
import NembraCore
import Testing

@Suite("Stock-app marker receipt truth")
struct PassiveBluetoothStockAppMarkerReceiptTests {
    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    @Test("marker round trip preserves Nembra receipt clocks without inventing stock-app refresh time")
    func markerReceiptClocksRemainCaptureReceiptEvidence() throws {
        let marker = try PassiveBluetoothStockAppObservation(
            field: "Battery",
            displayedValue: "73%",
            note: "Operator submitted while observing the stock app"
        )
        let receiptUptime: UInt64 = 8_765_432_100
        let receiptDate = Date(timeIntervalSince1970: 1_786_123_456)

        var session = try PassiveBluetoothCaptureSession(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1_786_123_400)
        )
        try session.append(
            .stockAppState(marker),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: receiptUptime,
            receivedAtDate: receiptDate
        )

        let encoded = try PassiveBluetoothCaptureJSON.encode(session, prettyPrinted: false)
        let decoded = try PassiveBluetoothCaptureJSON.decode(encoded)
        let record = try #require(decoded.records.first)

        #expect(record.receivedAtUptimeNanoseconds == receiptUptime)
        #expect(record.receivedAtDate == receiptDate)
        guard case let .stockAppState(decodedMarker) = record.event else {
            Issue.record("Expected stock-app marker")
            return
        }
        #expect(decodedMarker == marker)
    }
}