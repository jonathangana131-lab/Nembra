import Testing
@testable import NembraCore

@Suite("Primary vehicle target")
struct VehicleTargetTests {
    @Test("AOVOPRO ES80 is the primary unverified vehicle profile identity")
    func es80Identity() {
        #expect(VehicleProfile.aovoproES80.identity.manufacturer == "AOVOPRO")
        #expect(VehicleProfile.aovoproES80.identity.model == "ES80")
        #expect(VehicleProfile.aovoproES80.identity.displayName == "AOVOPRO ES80")
        #expect(VehicleProfile.aovoproES80.identity.protocolFamily.contains("hardware validation pending"))
    }

    @Test("ES80 keeps writable controls fail closed until physical protocol proof exists")
    func es80ConservativeProtocolCapabilities() {
        let capabilities = VehicleProfile.aovoproES80.capabilities

        // Read-only product expectations remain broad research leads. Their actual
        // values still require downstream source/evidence authority before display.
        #expect(capabilities.supportsBatteryPercent)
        #expect(capabilities.supportsLiveSpeed)
        #expect(capabilities.supportsOdometer)

        // Stock-app/user observation does not authorize Nembra writes. These flags
        // gate shipping Home/Vehicle control surfaces and stay false until physical
        // protocol semantics plus acknowledgement/confirmation behavior are accepted.
        #expect(!capabilities.supportsLock)
        #expect(!capabilities.supportsHeadlight)
        #expect(!capabilities.supportsCruise)
        #expect(!capabilities.supportsStartMode)
        #expect(!capabilities.supportsSpeedLimit)

        // Do not project deferred MAXSHOT/Tuya findings onto the ES80.
        #expect(!capabilities.supportsPowerWatts)
        #expect(!capabilities.supportsCurrentAmps)
        #expect(capabilities.supportedRideModes.isEmpty)
        #expect(capabilities.speedLimitRangesBySlot.isEmpty)
        #expect(capabilities.verifiedSpeedLimitSlotByRideMode.isEmpty)
    }

    @Test("Simulator retains synthetic control coverage without widening ES80 authority")
    func simulatorControlsRemainAvailable() {
        let capabilities = VehicleProfile.simulatorQA.capabilities
        #expect(capabilities.supportsLock)
        #expect(capabilities.supportsHeadlight)
        #expect(capabilities.supportsCruise)
        #expect(capabilities.supportsStartMode)
        #expect(capabilities.supportsSpeedLimit)
        #expect(!capabilities.supportedRideModes.isEmpty)
    }

    @Test("deferred MAXSHOT profile remains preserved")
    func maxshotProfileStillExists() {
        #expect(VehicleProfile.maxshotV1SPro.identity.displayName == "MAXSHOT V1S Pro")
        #expect(VehicleProfile.maxshotV1SPro.capabilities.speedLimitRangesBySlot[.limit3]?.maximumKilometersPerHour == 35)
    }
}
