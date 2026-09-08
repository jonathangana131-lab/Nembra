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

    @Test("ES80 keeps all physical semantics fail closed until authenticated payload proof exists")
    func es80ConservativeProtocolCapabilities() {
        let capabilities = VehicleProfile.aovoproES80.capabilities

        // C7D09A22 proved device identity and the unauthenticated rejection behavior,
        // but produced no authenticated application payloads. Product/manual claims
        // therefore remain research leads only; they cannot authorize telemetry or
        // writable controls in the shipping physical profile.
        #expect(!capabilities.supportsBatteryPercent)
        #expect(!capabilities.supportsLiveSpeed)
        #expect(!capabilities.supportsOdometer)
        #expect(!capabilities.supportsPowerWatts)
        #expect(!capabilities.supportsCurrentAmps)

        // Never infer writable semantics from advertised Tuya support, public app
        // behavior, or another scooter profile. Each control remains unavailable
        // until authenticated physical payload evidence establishes the mapping and
        // its acknowledgement/confirmation behavior.
        #expect(!capabilities.supportsLock)
        #expect(!capabilities.supportsHeadlight)
        #expect(!capabilities.supportsCruise)
        #expect(!capabilities.supportsStartMode)
        #expect(!capabilities.supportsSpeedLimit)
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

    @Test("deferred MAXSHOT profile remains preserved without proving ES80 semantics")
    func maxshotProfileStillExists() {
        #expect(VehicleProfile.maxshotV1SPro.identity.displayName == "MAXSHOT V1S Pro")
        #expect(VehicleProfile.maxshotV1SPro.capabilities.speedLimitRangesBySlot[.limit3]?.maximumKilometersPerHour == 35)

        let es80 = VehicleProfile.aovoproES80.capabilities
        #expect(!es80.supportsSpeedLimit)
        #expect(es80.speedLimitRangesBySlot.isEmpty)
        #expect(es80.verifiedSpeedLimitSlotByRideMode.isEmpty)
    }
}
