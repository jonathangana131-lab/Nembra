import Foundation
import Testing

@Suite("ES80 command capability app visibility")
struct ES80CommandCapabilityAppVisibilitySourceTests {
    @Test("Home quick controls mount only when the profile authorizes their command capability")
    func homeQuickControlsAreCapabilityGated() throws {
        let source = try readRepositoryFile("NembraApp/Features/Home/HomeView.swift")

        #expect(source.contains("if vehicle.profile.capabilities.supportsHeadlight"))
        #expect(source.contains("if vehicle.profile.capabilities.supportsLock"))
    }

    @Test("Vehicle Controls hides every unverified ES80 command family behind profile capability gates")
    func vehicleControlsAreCapabilityGated() throws {
        let source = try readRepositoryFile("NembraApp/Features/Home/VehicleControlsView.swift")

        #expect(source.contains("if vehicle.profile.capabilities.supportsHeadlight"))
        #expect(source.contains("if vehicle.profile.capabilities.supportsLock"))
        #expect(source.contains("if vehicle.profile.capabilities.supportsCruise"))
        #expect(source.contains("if vehicle.profile.capabilities.supportsStartMode"))
        #expect(source.contains("if !userFacingSpeedLimitControls.isEmpty"))
        #expect(source.contains("capabilities.hasUserFacingSpeedLimitMapping"))
    }

    @Test("Primary ES80 profile keeps command gates closed while hardware validation is pending")
    func primaryProfileKeepsCommandGatesClosed() throws {
        let profile = try primaryES80ProfileSource()

        #expect(profile.contains("supportsLock: false"))
        #expect(profile.contains("supportsHeadlight: false"))
        #expect(profile.contains("supportsCruise: false"))
        #expect(profile.contains("supportsStartMode: false"))
        #expect(profile.contains("supportsSpeedLimit: false"))
    }

    @Test("Primary ES80 profile does not assign telemetry semantics before authenticated physical evidence")
    func primaryProfileKeepsTelemetrySemanticsClosed() throws {
        let profile = try primaryES80ProfileSource()

        #expect(profile.contains("supportsOdometer: false"))
        #expect(profile.contains("supportsLiveSpeed: false"))
        #expect(profile.contains("supportsBatteryPercent: false"))
        #expect(profile.contains("supportsPowerWatts: false"))
        #expect(profile.contains("supportsCurrentAmps: false"))
        #expect(profile.contains("supportedRideModes: []"))
        #expect(profile.contains("speedLimitRangesBySlot: [:]"))
        #expect(profile.contains("verifiedSpeedLimitSlotByRideMode: [:]"))
    }

    @Test("Production ride detector remains disabled until ES80 physical policy is measured")
    func productionRideDetectorRemainsFailClosed() throws {
        let source = try readRepositoryFile("NembraApp/App/AppBootstrap.swift")
        guard let start = source.range(of: "} else {\n            // Production history/route storage"),
              let end = source.range(of: "\n        let simulatorAutoCompletesRide", range: start.upperBound..<source.endIndex) else {
            Issue.record("Production ride bootstrap section was not found")
            throw SourceContractError.sectionMissing
        }

        let production = source[start.lowerBound..<end.lowerBound]
        #expect(production.contains("no production ride detector or"))
        #expect(production.contains("until real AOVOPRO ES80 timing"))
        #expect(production.contains("configuration: nil"))
        #expect(production.contains("checkpointStore: nil"))
        #expect(production.contains("historyStore: nil"))
        #expect(!production.contains("RideApplicationConfiguration.simulatorQA()"))
    }

    private func primaryES80ProfileSource() throws -> Substring {
        let source = try readRepositoryFile("Packages/NembraCore/Sources/NembraCore/VehicleDomain.swift")
        guard let start = source.range(of: "public static let aovoproES80 = VehicleProfile("),
              let end = source.range(of: "/// Explicitly synthetic capability profile", range: start.upperBound..<source.endIndex) else {
            Issue.record("AOVOPRO ES80 profile section was not found")
            throw SourceContractError.sectionMissing
        }
        return source[start.lowerBound..<end.lowerBound]
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
