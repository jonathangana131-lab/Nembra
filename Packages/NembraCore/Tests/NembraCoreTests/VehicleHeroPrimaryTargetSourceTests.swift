import Foundation
import Testing

@Suite("Vehicle hero primary target")
struct VehicleHeroPrimaryTargetSourceTests {
    @Test("AOVOPRO ES80 uses a dedicated presentation-only hero before generic fallback")
    func es80UsesDedicatedArtwork() throws {
        let source = try readRepositoryFile("NembraApp/Features/Home/VehicleHeroView.swift")

        guard let selectionStart = source.range(of: "private var vehicleArtwork: some View") else {
            Issue.record("Vehicle hero artwork selection was not found")
            throw SourceContractError.sectionMissing
        }

        let selection = source[selectionStart.lowerBound...]
        guard let es80 = selection.range(of: "profile.identity.manufacturer == \"AOVOPRO\" && profile.identity.model == \"ES80\""),
              let dedicated = selection.range(of: "AOVOPROES80SideArtwork(connected:"),
              let fallback = selection.range(of: "GenericScooterArtwork(connected:") else {
            Issue.record("ES80 dedicated artwork selection or generic fallback is missing")
            throw SourceContractError.sectionMissing
        }

        #expect(es80.lowerBound < dedicated.lowerBound)
        #expect(dedicated.lowerBound < fallback.lowerBound)
    }

    @Test("ES80 hero stays decorative and does not invent vehicle-state semantics")
    func es80ArtworkStaysPresentationOnly() throws {
        let source = try readRepositoryFile("NembraApp/Features/Home/VehicleHeroView.swift")
        guard let start = source.range(of: "private struct AOVOPROES80SideArtwork: View"),
              let end = source.range(of: "private struct MaxshotV1SProSideArtwork: View", range: start.upperBound..<source.endIndex) else {
            Issue.record("AOVOPRO ES80 artwork source section was not found")
            throw SourceContractError.sectionMissing
        }

        let artwork = source[start.lowerBound..<end.lowerBound]
        #expect(artwork.contains("let connected: Bool"))
        #expect(!artwork.contains("batteryPercent"))
        #expect(!artwork.contains("speedKilometersPerHour"))
        #expect(!artwork.contains("powerWatts"))
        #expect(!artwork.contains("isLocked"))
        #expect(!artwork.contains("isHeadlightOn"))
        #expect(!artwork.contains("isCruiseEnabled"))
    }

    @Test("Vehicle hero artwork remains hidden from accessibility semantics")
    func artworkDoesNotCompeteWithTruthLabels() throws {
        let source = try readRepositoryFile("NembraApp/Features/Home/VehicleHeroView.swift")
        #expect(source.contains("vehicleArtwork\n                .frame(height: 168)\n                .accessibilityHidden(true)"))
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
