import Foundation
import Testing

@Suite("Dashboard learned-range accessibility semantics")
struct DashboardLearnedRangeAccessibilitySourceTests {
    @Test("battery toggle uses canonical learned-range VoiceOver terminology")
    func batteryToggleUsesLearnedRangeTerminology() throws {
        let source = try readRepositoryFile("NembraApp/Features/Dashboard/DashboardView.swift")
        let instrument = try section(
            in: source,
            from: "private var batteryRangeInstrument",
            to: "private var batteryChargeBar"
        )
        let body = String(instrument)

        #expect(body.contains(".accessibilityLabel(batteryReadout == .charge ? \"Battery\" : \"Learned range\")"))
        #expect(!body.contains("\"Estimated range\""))
        #expect(body.contains(".accessibilityIdentifier(\"dashboard.battery-range\")"))
    }

    @Test("unearned learned range remains explicitly unavailable")
    func unearnedLearnedRangeRemainsUnavailable() throws {
        let source = try readRepositoryFile("NembraApp/Features/Dashboard/DashboardView.swift")
        let accessibilityValue = try section(
            in: source,
            from: "private var batteryAccessibilityValue",
            to: "private var batteryPrimaryColor"
        )
        let body = String(accessibilityValue)

        #expect(body.contains("case .range:"))
        #expect(body.contains("Unavailable until a verified learned range model exists"))
        #expect(!body.contains("manufacturer"))
        #expect(!body.contains("advertised"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
