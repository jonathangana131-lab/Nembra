import Foundation
import Testing

@Suite("Vehicle command authority source contract")
struct VehicleCommandAuthoritySourceTests {
    @Test("A connected transport is not command authority by itself")
    func liveEvidenceIsRequired() throws {
        let store = try vehicleStoreSource()

        #expect(store.contains("var hasLiveVehicleCommandAuthority: Bool"))
        #expect(store.contains("state.connection == .connected && state.dataAvailability == .live"))
        #expect(!store.contains("var hasLiveVehicleCommandAuthority: Bool {\n        state.connection == .connected\n    }"))
    }

    @Test("Every vehicle write crosses the central authority gate")
    func everyWriteUsesCentralGate() throws {
        let store = try vehicleStoreSource()

        #expect(store.contains("guard canBeginVehicleCommand(.headlight) else { return }"))
        #expect(store.contains("guard canBeginVehicleCommand(.lock) else { return }"))
        #expect(store.contains("guard canBeginVehicleCommand(.cruise) else { return }"))
        #expect(store.contains("canBeginVehicleCommand(.mode) else { return }"))
        #expect(store.contains("guard canBeginVehicleCommand(.startMode) else { return }"))
        #expect(store.contains("canBeginVehicleCommand(.speedLimit) else { return }"))
        #expect(store.contains("hasLiveVehicleCommandAuthority,"))
    }

    @Test("Capability checks remain fail closed after live-evidence admission")
    func capabilitiesStillGateCommands() throws {
        let store = try vehicleStoreSource()

        #expect(store.contains("return capabilities.supportsHeadlight"))
        #expect(store.contains("return capabilities.supportsLock"))
        #expect(store.contains("return capabilities.supportsCruise"))
        #expect(store.contains("return !capabilities.supportedRideModes.isEmpty"))
        #expect(store.contains("return capabilities.supportsStartMode"))
        #expect(store.contains("return capabilities.supportsSpeedLimit"))
        #expect(store.contains("&& !capabilities.speedLimitRangesBySlot.isEmpty"))
    }

    private func vehicleStoreSource() throws -> String {
        try readRepositoryFile("NembraApp/App/VehicleStore.swift")
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
        return String(decoding: data, as: UTF8.self)
    }
}
