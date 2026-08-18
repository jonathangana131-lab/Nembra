import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Standard account-link visual closure")
struct CaptureStandardAccountLinkVisualClosureSourceTests {
    @Test("human-rejected Standard copy hierarchy is retired without weakening lock truth")
    func rejectedStandardCopyHierarchyIsRetired() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: app,
            from: "private struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController"
        ))

        // #3395 human review rejected the Standard first-run surface as a generic
        // form/onboarding composition with repeated authority prose. This contract
        // intentionally does not prescribe replacement styling; real screenshots
        // and human review remain the aesthetic oracle.
        #expect(!root.contains("Prepare account metadata"))
        #expect(!root.contains("Link the Tuya Smart account that owns this scooter. Bluetooth and physical evidence stay locked until the reviewed field build and fresh scooter authority are verified."))
        #expect(!root.contains("Account setup is available. Bluetooth scanning, connection, and physical evidence stay locked until the reviewed field build is installed."))

        // Product truth must survive the visual simplification.
        #expect(root.contains("Physical capture locked"))
        #expect(root.contains("This public build can prepare account metadata only. Bluetooth and physical evidence collection are locked."))
        #expect(root.contains("This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings."))
    }

    @Test("engineering detail is sightedly demoted while VoiceOver semantics remain explicit")
    func engineeringDisclosureIsDemotedWithoutSemanticLoss() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: app,
            from: "private struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController"
        ))
        let disclosure = String(try section(
            in: root,
            from: "private var engineeringDisclosure: some View",
            to: "@ViewBuilder\n    private func rootSection"
        ))

        // Standard should not promote implementation language to a primary-looking
        // sighted label. Accessibility retains the precise engineering description.
        #expect(!disclosure.contains("Label(isAccessibilityLayout ? \"Details\" : \"Engineering details\""))
        #expect(disclosure.contains(".accessibilityLabel(\"Engineering details\")"))
    }

    @Test("account-link action keeps stable read-only accessibility authority")
    func accountLinkActionKeepsReadOnlyAuthority() throws {
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
