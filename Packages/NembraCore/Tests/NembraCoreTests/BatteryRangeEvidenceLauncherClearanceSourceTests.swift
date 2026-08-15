import Foundation
import Testing

@Suite("Battery/Range evidence launcher clearance")
struct BatteryRangeEvidenceLauncherClearanceSourceTests {
    @Test("Evidence values grow vertically and reserve the navigation launcher footprint")
    func evidenceValuesClearPersistentLauncher() throws {
        let source = try readRepositoryFile("NembraApp/Features/Home/VehicleControlsView.swift")
        let row = try evidenceRowSection(in: source)

        #expect(row.contains("VStack(alignment: .leading"))
        #expect(row.contains("multilineTextAlignment(.leading)"))
        #expect(row.contains("fixedSize(horizontal: false, vertical: true)"))
        #expect(row.contains("padding(.trailing, 72)"))
        #expect(!row.contains("multilineTextAlignment(.trailing)"))
    }

    @Test("Evidence row keeps title/value VoiceOver aggregation")
    func evidenceVoiceOverContract() throws {
        let source = try readRepositoryFile("NembraApp/Features/Home/VehicleControlsView.swift")
        let row = try evidenceRowSection(in: source)

        #expect(row.contains("accessibilityElement(children: .ignore)"))
        #expect(row.contains("accessibilityLabel(title)"))
        #expect(row.contains("accessibilityValue(value)"))
    }

    private func evidenceRowSection(in source: String) throws -> Substring {
        guard let start = source.range(
            of: "private func evidenceRow(title: String, value: String, symbol: String) -> some View"
        ), let end = source.range(of: "@ViewBuilder\n    private var dataBadge", range: start.upperBound..<source.endIndex) else {
            Issue.record("BatteryRangeView evidenceRow section was not found")
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
