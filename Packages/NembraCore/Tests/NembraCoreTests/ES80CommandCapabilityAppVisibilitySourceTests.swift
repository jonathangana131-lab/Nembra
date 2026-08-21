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
