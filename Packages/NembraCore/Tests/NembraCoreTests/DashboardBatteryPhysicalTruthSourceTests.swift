import Foundation
import Testing

@Suite("Dashboard battery physical truth")
struct DashboardBatteryPhysicalTruthSourceTests {
    @Test("Cockpit battery reads only display-authoritative battery evidence")
    func batteryUsesDisplayAuthority() throws {
        let source = try dashboardSource()

        #expect(source.contains("vehicle.batteryDisplayPercent"))
        #expect(source.contains("vehicle.batteryDataAvailability == .retained"))
        #expect(source.contains("LAST KNOWN"))
        #expect(source.contains("Unavailable until battery evidence is display-authoritative"))
        #expect(!source.contains("vehicle.state.batteryPercent"))
    }

    @Test("Cockpit never fabricates learned range from charge")
    func learnedRangeFailsClosed() throws {
        let source = try dashboardSource()

        #expect(source.contains("case .range: \"—\""))
        #expect(source.contains("NOT CALIBRATED"))
        #expect(source.contains("Unavailable until a verified learned range model exists"))
        #expect(source.contains("Until a verified\n/// ES80 battery source and learned range model exist, range presents as unavailable"))
        #expect(!source.contains("advertisedRange"))
        #expect(!source.contains("batteryPercent *"))
        #expect(!source.contains("batteryPercent /"))
    }

    private func dashboardSource() throws -> String {
        try readRepositoryFile("NembraApp/Features/Dashboard/DashboardView.swift")
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
