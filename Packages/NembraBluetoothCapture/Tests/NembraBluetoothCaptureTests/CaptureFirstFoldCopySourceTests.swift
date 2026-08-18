import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture first-fold copy source contract")
struct CaptureFirstFoldCopySourceTests {
    @Test("standalone Capture bundles the compact standard sighted copy")
    func compactStandardCopyIsBundled() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let strings = try readRepositoryFile("NembraApp/Resources/Localizable.strings")
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")

        let heroKey = "Link the Tuya Smart account that owns this scooter. Bluetooth and physical evidence stay locked until the reviewed field build and fresh scooter authority are verified."
        let heroValue = "Link the Tuya Smart account that owns this scooter."
        let readOnlyKey = "This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings."
        let readOnlyValue = "Account metadata only. This step does not start Bluetooth or change scooter settings."

        // The resource keys must stay anchored to the exact SwiftUI literals they replace.
        #expect(app.contains("Text(\"Prepare the scooter link\")"))
        #expect(app.contains(heroKey))
        #expect(app.contains(readOnlyKey))
        #expect(app.contains(".accessibilitySortPriority(isAccessibilityLayout ? 100 : 0)"))

        #expect(strings.contains("\"Prepare the scooter link\" = \"Link this scooter\";"))
        #expect(strings.contains("\"\(heroKey)\" = \"\(heroValue)\";"))
        #expect(strings.contains("\"\(readOnlyKey)\" = \"\(readOnlyValue)\";"))
        #expect(heroValue.count < heroKey.count / 2)
        #expect(readOnlyValue.count < readOnlyKey.count)

        // A copy file that is not in the target bundle is not a product change.
        #expect(project.contains("A10000000000000000000008 /* Localizable.strings in Resources */"))
        #expect(project.contains("B10000000000000000000008 /* Localizable.strings */"))
        #expect(project.contains("path = NembraApp/Resources/Localizable.strings"))
        #expect(project.contains("A10000000000000000000008 /* Localizable.strings in Resources */,"))
    }

    @Test("human-rejected Standard account-link hierarchy is retired without weakening authority")
    func rejectedStandardAccountLinkHierarchyIsRetired() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: app,
            from: "private struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController"
        ))

        // Direct human review of the exact #3395 Standard pixels rejected this
        // implementation-language/form hierarchy. This contract is deliberately
        // narrow: it retires known rejected markers without pretending source
        // assertions can replace fresh iPhone 12 screenshots or human critique.
        #expect(!root.contains("Prepare account metadata"))
        #expect(!root.contains("Account setup is available. Bluetooth scanning, connection, and physical evidence stay locked until the reviewed field build is installed."))

        let disclosure = String(try section(
            in: root,
            from: "private var engineeringDisclosure: some View",
            to: "@ViewBuilder\n    private func rootSection"
        ))
        #expect(!disclosure.contains("Label(isAccessibilityLayout ? \"Details\" : \"Engineering details\""))

        // Visual simplification may never erase the fail-closed rider meaning.
        #expect(root.contains("Physical capture locked"))
        #expect(root.contains("This public build can prepare account metadata only. Bluetooth and physical evidence collection are locked."))
        #expect(root.contains("This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings."))
        #expect(disclosure.contains(".accessibilityLabel(\"Engineering details\")"))
    }

    @Test("account-link visual successor preserves stable read-only accessibility semantics")
    func accountLinkSuccessorPreservesReadOnlyAccessibilitySemantics() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: app,
            from: "private struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController"
        ))
        let panel = String(try section(
            in: root,
            from: "private var accountSetupPanel: some View",
            to: "private var statusText: some View"
        ))

        #expect(panel.contains("tuya.requestApproval()"))
        #expect(panel.contains("nembra.capture.root.account-link-action"))
        #expect(panel.contains(".accessibilityLabel(\"Create approval QR\")"))
        #expect(panel.contains("Creates the account-metadata approval QR. It does not start Bluetooth or physical Capture."))
        #expect(panel.contains("Tuya Smart user code"))
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
