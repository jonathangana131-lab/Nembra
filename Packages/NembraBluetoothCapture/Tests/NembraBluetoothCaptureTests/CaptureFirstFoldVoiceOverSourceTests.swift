import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture first-fold VoiceOver source contract")
struct CaptureFirstFoldVoiceOverSourceTests {
    @Test("first fold speaks the public physical lock before offering explanation")
    func publicFirstFoldPreservesSpokenAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let strings = try readRepositoryFile("NembraApp/Resources/Localizable.strings")
        let root = try sourceRegion(
            in: app,
            from: "@MainActor\nprivate struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController:"
        )

        #expect(strings.contains("\"Link your scooter\" = \"Link your scooter\";"))
        #expect(strings.contains("\"Link scooter account\" = \"Link scooter account\";"))

        let hero = try sourceRegion(
            in: root,
            from: "private var rootHero: some View",
            to: "private var buildAuthorityStatus: some View"
        )
        #expect(hero.contains("Text(\"Link your scooter\")"))
        #expect(hero.contains("Sign in once, choose the intended scooter, then follow one instruction at a time."))

        let authority = try sourceRegion(
            in: root,
            from: "private var buildAuthorityStatus: some View",
            to: "private var accountSetupPanel: some View"
        )
        #expect(authority.contains(".accessibilityElement(children: .combine)"))
        #expect(authority.contains(".accessibilitySortPriority(isAccessibilityLayout ? 100 : 0)"))
        #expect(authority.contains(".accessibilityLabel(fieldBuildIsAuthoritative ? \"Field build ready\" : \"Physical capture locked\")"))
        #expect(authority.contains("This public build cannot authorize Bluetooth or collect physical evidence."))

        let account = try sourceRegion(
            in: root,
            from: "private var accountSetupPanel: some View",
            to: "private var scooterChooserPanel: some View"
        )
        #expect(account.contains("Label(\"Review field requirements\", systemImage: \"lock.shield\")"))
        #expect(account.contains(".accessibilityHint(\"Shows why this public build cannot start account or Bluetooth authorization.\")"))
        #expect(account.contains(".accessibilityIdentifier(\"nembra.capture.root.account-link-action\")"))
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
    }
}
