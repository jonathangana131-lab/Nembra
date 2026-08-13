import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture first-fold VoiceOver source contract")
struct CaptureFirstFoldVoiceOverSourceTests {
    @Test("localized visual compaction preserves spoken physical-lock authority")
    func localizedVisualCopyPreservesSpokenAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let strings = try readRepositoryFile("NembraApp/Resources/Localizable.strings")

        let authorityKey = "Link the Tuya Smart account that owns this scooter. Bluetooth and physical evidence stay locked until the reviewed field build and fresh scooter authority are verified."
        let compactValue = "Link the Tuya Smart account that owns this scooter."
        #expect(strings.contains("\"\(authorityKey)\" = \"\(compactValue)\";"))

        let rootHero = try sourceRegion(
            in: app,
            from: "private var rootHero: some View",
            to: "private var buildAuthorityStatus: some View"
        )
        #expect(rootHero.contains("Text(\"\(authorityKey)\")"))

        // SwiftUI Text created from a string literal is localized by default, and VoiceOver
        // speaks that rendered value unless an explicit accessibility semantic overrides it.
        // Once Localizable.strings shortens this key for the sighted first fold, the compact
        // visible value must not silently become the only spoken authority warning.
        let spoken = try explicitVerbatimAccessibilityText(in: rootHero)
        let normalized = spoken.lowercased()
        #expect(normalized.contains("bluetooth"))
        #expect(normalized.contains("physical evidence"))
        #expect(normalized.contains("lock"))
        #expect(normalized.contains("build"))
        #expect(normalized.contains("scooter"))
        #expect(normalized.contains("authority"))
    }

    private func explicitVerbatimAccessibilityText(in source: String) throws -> String {
        for marker in [
            ".accessibilityLabel(Text(verbatim: \"",
            ".accessibilityValue(Text(verbatim: \""
        ] {
            guard let start = source.range(of: marker) else { continue }
            let tail = source[start.upperBound...]
            guard let end = tail.range(of: "\"))") else {
                throw SourceContractError.malformedAccessibilityOverride
            }
            return String(tail[..<end.lowerBound])
        }
        throw SourceContractError.missingVerbatimAccessibilityOverride
    }

    private func sourceRegion(in source: String, from startMarker: String, to endMarker: String) throws -> String {
        guard let start = source.range(of: startMarker),
              let end = source.range(of: endMarker, range: start.upperBound..<source.endIndex),
              start.lowerBound < end.lowerBound else {
            throw SourceContractError.missingSourceRegion
        }
        return String(source[start.lowerBound..<end.lowerBound])
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
        case missingSourceRegion
        case missingVerbatimAccessibilityOverride
        case malformedAccessibilityOverride
    }
}
