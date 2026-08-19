import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture first-fold copy source contract")
struct CaptureFirstFoldCopySourceTests {
    @Test("standalone Capture bundles the calm account-link first fold")
    func calmAccountLinkCopyIsBundled() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let strings = try readRepositoryFile("NembraApp/Resources/Localizable.strings")
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")

        let hero = "Link your scooter"
        let action = "Link scooter account"
        let readOnlyBoundary = "Account link only · no Bluetooth or scooter changes"

        // Keep the sighted first fold direct and truthful without turning it into a runbook.
        #expect(app.contains("Text(\"\(hero)\")"))
        #expect(app.contains(": \"\(action)\""))
        #expect(app.contains("Text(\"\(readOnlyBoundary)\")"))
        #expect(app.contains("Label(\"Details\", systemImage: \"info.circle\")"))
        #expect(!app.contains("Prepare the scooter link"))
        #expect(!app.contains("Prepare account metadata"))

        // These strings are in the standalone target, not an unattached copy proposal.
        #expect(strings.contains("\"\(hero)\" = \"\(hero)\";"))
        #expect(strings.contains("\"\(action)\" = \"\(action)\";"))
        #expect(strings.contains("\"\(readOnlyBoundary)\" = \"\(readOnlyBoundary)\";"))
        #expect(strings.contains("\"Details\" = \"Details\";"))

        // A copy file that is not in the target bundle is not a product change.
        #expect(project.contains("A10000000000000000000008 /* Localizable.strings in Resources */"))
        #expect(project.contains("B10000000000000000000008 /* Localizable.strings */"))
        #expect(project.contains("path = NembraApp/Resources/Localizable.strings"))
        #expect(project.contains("A10000000000000000000008 /* Localizable.strings in Resources */,"))
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
}
