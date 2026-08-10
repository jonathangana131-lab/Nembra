import Testing
@testable import NembraCore

@Suite("Simulator propulsion receipt domain")
struct SimulatorPowerReceiptDomainTests {
    @Test("zero receipt uptime is rejected before it can enter source currentness")
    func zeroReceiptUptimeFailsClosed() {
        #expect(throws: SimulatorPowerObservationError.invalidReceiptUptime) {
            _ = try SimulatorPowerObservation(
                watts: 0,
                receiptSequenceNumber: 1,
                receivedAtUptimeNanoseconds: 0,
                continuityGeneration: 1
            )
        }
    }

    @Test("positive monotonic uptime preserves legitimate zero-watt observations")
    func positiveReceiptUptimeIsAccepted() throws {
        let observation = try SimulatorPowerObservation(
            watts: 0,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            continuityGeneration: 1
        )

        #expect(observation.watts == 0)
        #expect(observation.receiptSequenceNumber == 1)
        #expect(observation.receivedAtUptimeNanoseconds == 1)
        #expect(observation.continuityGeneration == 1)
    }
}
