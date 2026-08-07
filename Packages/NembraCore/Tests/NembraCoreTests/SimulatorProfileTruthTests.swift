import Testing
@testable import NembraCore

@Suite("Simulator profile truth")
struct SimulatorProfileTruthTests {
    @Test("default simulator service uses an explicitly synthetic profile")
    func defaultSimulatorProfileIsSynthetic() {
        let service = SimulatedScooterService(commandLatencyNanoseconds: 0)

        #expect(service.profile == .simulatorQA)
        #expect(service.profile.identity.displayName == "Nembra Simulator")
        #expect(service.profile.identity.protocolFamily.contains("Synthetic QA"))
        #expect(service.profile != .aovoproES80)
        #expect(service.profile != .maxshotV1SPro)
    }

    @Test("synthetic capabilities stay separate from ES80 hardware claims")
    func simulatorCapabilitiesDoNotExpandES80Profile() {
        let simulator = VehicleProfile.simulatorQA.capabilities
        let es80 = VehicleProfile.aovoproES80.capabilities

        #expect(simulator.supportsPowerWatts)
        #expect(simulator.supportsCurrentAmps)
        #expect(simulator.supportedRideModes == Set(RideMode.allCases))
        #expect(simulator.speedLimitRangesBySlot.count == 3)

        #expect(!es80.supportsPowerWatts)
        #expect(!es80.supportsCurrentAmps)
        #expect(es80.supportedRideModes.isEmpty)
        #expect(es80.speedLimitRangesBySlot.isEmpty)
    }

    @Test("synthetic profile never acquires a physical protocol family")
    func simulatorIdentityStaysSynthetic() {
        let identity = VehicleProfile.simulatorQA.identity

        #expect(identity.manufacturer == "NEMBRA")
        #expect(identity.model == "Simulator")
        #expect(identity.protocolFamily.contains("not physical scooter protocol"))
        #expect(!identity.protocolFamily.contains("Tuya"))
    }
}
