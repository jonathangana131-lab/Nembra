import Foundation
import Testing

@Suite("Vehicle Controls physical-truth boundary")
struct VehicleControlsPhysicalTruthBoundarySourceTests {
    @Test("Physical command families remain capability-gated")
    func commandFamiliesRemainCapabilityGated() throws {
        let source = try vehicleControlsSource()

        #expect(source.contains("if vehicle.profile.capabilities.supportsHeadlight"))
        #expect(source.contains("if vehicle.profile.capabilities.supportsLock"))
        #expect(source.contains("if !supportedModes.isEmpty"))
        #expect(source.contains("if !userFacingSpeedLimitControls.isEmpty"))
        #expect(source.contains("if vehicle.profile.capabilities.supportsCruise"))
        #expect(source.contains("if vehicle.profile.capabilities.supportsStartMode"))
    }

    @Test("Locking requires independently qualified stopped-speed evidence")
    func lockRequiresQualifiedSpeedEvidence() throws {
        let source = try vehicleControlsSource()

        #expect(source.contains("vehicle.canLockFromCurrentSpeedEvidence"))
        #expect(source.contains("enabled: vehicle.canLockFromCurrentSpeedEvidence"))
        #expect(source.contains("Stopped-speed evidence required"))
    }

    @Test("Speed-limit presentation only exposes verified profile mappings and ranges")
    func speedLimitsRemainVerifiedProfileOwned() throws {
        let source = try vehicleControlsSource()

        #expect(source.contains("Only mappings and ranges verified by the active scooter profile appear here."))
        #expect(source.contains("userFacingSpeedLimitControls"))
        #expect(source.contains("verified range"))
    }

    @Test("Start behavior does not invent physical meaning")
    func startBehaviorRemainsPhysicalTruthBounded() throws {
        let source = try vehicleControlsSource()

        #expect(source.contains("Nembra does not assign physical meaning beyond what the active profile has verified."))
    }

    @Test("Vehicle Controls never bypasses VehicleStore with direct Tuya DP or destructive device operations")
    func noDirectTransportOrDestructiveShortcuts() throws {
        let source = try vehicleControlsSource()

        #expect(!source.contains("writeDataPoint"))
        #expect(!source.contains("setDataPoint"))
        #expect(!source.contains("publishDps"))
        #expect(!source.contains("publishDpsWithSuccess"))
        #expect(!source.contains("unbind"))
        #expect(!source.contains("removeDevice"))
        #expect(!source.contains("resetDevice"))
        #expect(!source.contains("factoryReset"))
    }

    @Test("Primary ES80 profile keeps every Vehicle Controls physical command family closed before authenticated payload evidence")
    func primaryES80CommandSemanticsRemainClosed() throws {
        let source = try readRepositoryFile("Packages/NembraCore/Sources/NembraCore/VehicleDomain.swift")
        guard let start = source.range(of: "public static let aovoproES80 = VehicleProfile("),
              let end = source.range(of: "/// Explicitly synthetic capability profile", range: start.upperBound..<source.endIndex) else {
            Issue.record("AOVOPRO ES80 profile section was not found")
            throw SourceContractError.sectionMissing
        }

        let profile = source[start.lowerBound..<end.lowerBound]
        #expect(profile.contains("supportsLock: false"))
        #expect(profile.contains("supportsHeadlight: false"))
        #expect(profile.contains("supportsCruise: false"))
        #expect(profile.contains("supportsStartMode: false"))
        #expect(profile.contains("supportsSpeedLimit: false"))
        #expect(profile.contains("supportedRideModes: []"))
        #expect(profile.contains("speedLimitRangesBySlot: [:]"))
        #expect(profile.contains("verifiedSpeedLimitSlotByRideMode: [:]"))
    }

    private func vehicleControlsSource() throws -> String {
        try readRepositoryFile("NembraApp/Features/Home/VehicleControlsView.swift")
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
