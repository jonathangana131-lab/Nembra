import Foundation
import Testing
import NembraCore

@Suite("Energy Rail public Simulator authority boundary")
struct PropulsionEnergyRailPublicAuthorityTests {
    @Test("public runtime admits only source-sealed Simulator availability")
    func genuineSourceAvailabilityDrivesPublicRuntime() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let live = await service.simulatorPowerEvidenceSnapshot()
        #expect(live.currentness == .live)
        #expect(live.observation != nil)

        var runtime = try PropulsionEnergyRailSimulatorRuntime()
        #expect(runtime.synchronizeSource(live))
        let liveProjection = runtime.projection(
            atUptimeNanoseconds: live.observation?.receivedAtUptimeNanoseconds ?? 1
        )
        #expect(liveProjection.currentness == .live)
        #expect(liveProjection.acceptedWatts == 356)

        await service.disconnect()
        let retained = await service.simulatorPowerEvidenceSnapshot()
        #expect(retained.currentness == .retained)
        #expect(retained.observation == live.observation)
        #expect(runtime.synchronizeSource(retained))

        let retainedProjection = runtime.projection(
            atUptimeNanoseconds: retained.observation?.receivedAtUptimeNanoseconds ?? 1
        )
        #expect(retainedProjection.currentness == .retained)
        #expect(retainedProjection.acceptedWatts == 356)
        #expect(retainedProjection.allowsLiveMotion == false)
    }

    @Test("negative transport veto cannot be replayed back to live by the same receipt")
    func negativeVetoCannotPromoteSameReceipt() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let live = await service.simulatorPowerEvidenceSnapshot()
        guard let observation = live.observation else {
            Issue.record("Expected genuine Simulator live power evidence")
            return
        }

        var runtime = try PropulsionEnergyRailSimulatorRuntime()
        #expect(runtime.synchronizeSource(live))
        #expect(runtime.retainCurrentSource())
        #expect(runtime.projection(atUptimeNanoseconds: observation.receivedAtUptimeNanoseconds).currentness == .retained)

        // The availability object is authentic, but it carries the exact same source
        // receipt already demoted by app lifecycle authority. Runtime chronology must
        // not let that old receipt regain LIVE just because it is replayed.
        #expect(runtime.synchronizeSource(live) == false)
        #expect(runtime.projection(atUptimeNanoseconds: observation.receivedAtUptimeNanoseconds).currentness == .retained)
    }

    @Test("unavailable public source state never manufactures numeric power")
    func unavailableCannotMintNumericPower() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()
        #expect(runtime.synchronizeSource(.unavailable))
        let projection = runtime.projection(atUptimeNanoseconds: 1)
        #expect(projection.currentness == .unavailable)
        #expect(projection.acceptedWatts == nil)
        #expect(projection.displayWatts == nil)
        #expect(projection.railFraction == nil)
    }

    @Test("raw receipt-field admission stays outside the public API")
    func rawReceiptAdmissionIsNotPublic() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let runtimeSourceURL = packageRoot
            .appendingPathComponent("Sources/NembraCore/PropulsionEnergyRailSimulatorRuntime.swift")
        let source = try String(contentsOf: runtimeSourceURL, encoding: .utf8)

        #expect(source.contains("public mutating func synchronizeSource("))
        #expect(source.contains("public mutating func retainCurrentSource()"))
        #expect(source.contains("package mutating func acceptLiveSource("))
        #expect(source.contains("package mutating func retainSource("))
        #expect(!source.contains("public mutating func acceptLiveSource("))
        #expect(!source.contains("public mutating func retainSource("))
    }
}
