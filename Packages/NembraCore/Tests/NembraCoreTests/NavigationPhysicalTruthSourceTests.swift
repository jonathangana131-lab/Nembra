import Foundation
import Testing

@Suite("Navigation physical truth")
struct NavigationPhysicalTruthSourceTests {
    @Test("Compact Navigation launcher requires qualified live stopped-speed evidence")
    func compactLauncherRequiresQualifiedLiveSpeed() throws {
        let source = try navigationHostSection()

        #expect(source.contains("guard verticalSizeClass == .compact else { return true }"))
        #expect(source.contains("guard let speed = vehicle.simulatorQualifiedLiveSpeedKilometersPerHour else { return false }"))
        #expect(source.contains("return speed < 0.5"))
        #expect(!source.contains("vehicle.state.telemetry.speed"))
        #expect(!source.contains("vehicle.state.connection == .connected"))
    }

    @Test("Navigation destination workflow stays independent of scooter DP semantics")
    func destinationWorkflowDoesNotClaimScooterTelemetry() throws {
        let source = try navigationViewSection()

        #expect(source.contains("Map results stay separate from scooter telemetry."))
        #expect(source.contains("Nembra will preview it here without using scooter telemetry."))
        #expect(source.contains("They do not contain scooter telemetry."))
        #expect(source.contains("item.openInMaps()"))
        #expect(!source.contains("hasLiveVehicleCommandAuthority"))
        #expect(!source.contains("VehicleTelemetry"))
    }

    private func navigationHostSection() throws -> Substring {
        let source = try readRepositoryFile("NembraApp/App/NembraApp.swift")
        guard let start = source.range(of: "private struct NembraNavigationHost<Content: View>: View"),
              let end = source.range(of: "private typealias NembraRecentDestination", range: start.upperBound..<source.endIndex) else {
            Issue.record("NembraNavigationHost source section was not found")
            throw SourceContractError.sectionMissing
        }
        return source[start.lowerBound..<end.lowerBound]
    }

    private func navigationViewSection() throws -> Substring {
        let source = try readRepositoryFile("NembraApp/App/NembraApp.swift")
        guard let start = source.range(of: "private struct NembraNavigationView: View") else {
            Issue.record("NembraNavigationView source section was not found")
            throw SourceContractError.sectionMissing
        }
        return source[start.lowerBound..<source.endIndex]
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
