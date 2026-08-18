import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture first-fold copy source contract")
struct CaptureFirstFoldCopySourceTests {
    @Test("standalone Capture bundles compact user-language Standard copy")
    func compactStandardCopyIsBundled() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let strings = try readRepositoryFile("NembraApp/Resources/Localizable.strings")
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")

        let heroKey = "Link the Tuya Smart account that owns this scooter. Bluetooth and physical evidence stay locked until the reviewed field build and fresh scooter authority are verified."
        let heroValue = "Link the Tuya Smart account that owns this scooter."
        let buildLockKey = "Account setup is available. Bluetooth scanning, connection, and physical evidence stay locked until the reviewed field build is installed."
        let buildLockValue = "Bluetooth stays locked until the reviewed field build is installed."
        let accountHeadingKey = "Prepare account metadata"
        let accountHeadingValue = "Link scooter account"
        let readOnlyKey = "This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings."
        let readOnlyValue = "Account metadata only. This step does not start Bluetooth or change scooter settings."

        // Resource keys stay anchored to exact SwiftUI literals so this remains a
        // sighted-copy repair; authority/accessibility source semantics are unchanged.
        #expect(app.contains("Text(\"Prepare the scooter link\")"))
        #expect(app.contains(heroKey))
        #expect(app.contains(buildLockKey))
        #expect(app.contains(accountHeadingKey))
        #expect(app.contains(readOnlyKey))
        #expect(app.contains(".accessibilitySortPriority(isAccessibilityLayout ? 100 : 0)"))

        #expect(strings.contains("\"Prepare the scooter link\" = \"Link this scooter\";"))
        #expect(strings.contains("\"\(heroKey)\" = \"\(heroValue)\";"))
        #expect(strings.contains("\"\(buildLockKey)\" = \"\(buildLockValue)\";"))
        #expect(strings.contains("\"\(accountHeadingKey)\" = \"\(accountHeadingValue)\";"))
        #expect(strings.contains("\"\(readOnlyKey)\" = \"\(readOnlyValue)\";"))
        #expect(heroValue.count < heroKey.count / 2)
        #expect(buildLockValue.count < buildLockKey.count)
        #expect(readOnlyValue.count < readOnlyKey.count)

        // A copy file that is not in the target bundle is not a product change.
        #expect(project.contains("A10000000000000000000008 /* Localizable.strings in Resources */"))
        #expect(project.contains("B10000000000000000000008 /* Localizable.strings */"))
        #expect(project.contains("path = NembraApp/Resources/Localizable.strings"))
        #expect(project.contains("A10000000000000000000008 /* Localizable.strings in Resources */,"))
    }

    @Test("human-rejected Standard structure remains red until product hierarchy changes")
    func rejectedStandardStructureStillRequiresProductRepair() throws {
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
        let disclosure = String(try section(
            in: root,
            from: "private var engineeringDisclosure: some View",
            to: "@ViewBuilder\n    private func rootSection"
        ))

        // #3395 human review rejected the exact Standard first-run shape as a
        // conventional rounded field + floating prominent QR CTA, and found the
        // sighted Engineering details disclosure too prominent. We reject only
        // that exact combination, leaving the successor free to choose a better
        // Nembra-native composition. Fresh screenshots remain the visual oracle.
        let hasRejectedRoundedField = panel.contains(".background(Color.white.opacity(0.085), in: RoundedRectangle(cornerRadius: 14, style: .continuous))")
        let hasRejectedStandaloneProminentQR = panel.contains("Label(isAccessibilityLayout ? \"Create QR\" : \"Create approval QR\"") && panel.contains(".buttonStyle(.borderedProminent)")
        #expect(!(hasRejectedRoundedField && hasRejectedStandaloneProminentQR))
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
