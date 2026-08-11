import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture root Accessibility XXXL product composition")
struct TuyaCaptureRootAccessibilityXXXLSourceTests {
    @Test("public setup root deliberately recomposes at accessibility text sizes")
    func rootRecomposesAtAccessibilitySizes() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: app,
            from: "private struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController"
        ))

        #expect(root.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
        #expect(root.contains("private var rootHero: some View"))
        #expect(root.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(root.contains("Link the Tuya account that owns this scooter before passive target correlation begins."))
        #expect(root.contains("Text(\"Prepare the scooter link\")"))
        #expect(root.contains(".font(.title2.bold())"))
        #expect(root.contains("private var rootContentSpacing: CGFloat"))
        #expect(root.contains("private var rootHorizontalPadding: CGFloat"))
        #expect(root.contains("private var rootPanelPadding: CGFloat"))
    }

    @Test("device selection and primary actions stack instead of squeezing at accessibility sizes")
    func deviceActionsRecomposeAtAccessibilitySizes() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: app,
            from: "private struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController"
        ))

        #expect(root.contains("private func scooterChooserHeader"))
        #expect(root.contains("private func scooterActions"))
        #expect(root.contains("if dynamicTypeSize.isAccessibilitySize"))
        #expect(root.contains("VStack(alignment: .leading, spacing: 10)"))
        #expect(root.contains("Button(tuya.selectedDeviceID == device.id ? \"Refresh metadata\" : \"Use this scooter\")"))
        #expect(root.contains("NavigationLink(\"Continue to Capture\")"))
        #expect(root.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
    }

    @Test("root accessibility composition does not mint scooter or protocol authority")
    func rootLayoutHasNoAuthoritySideEffects() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: app,
            from: "private struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController"
        ))

        #expect(root.contains("tuya.requestApproval()"))
        #expect(root.contains("tuya.checkApprovalNow()"))
        #expect(root.contains("tuya.refreshDevices()"))
        #expect(root.contains("tuya.selectDevice(device)"))
        #expect(root.contains("SecureLinkView(device: device)"))
        #expect(!root.contains("NEMBRA_SIMULATION_"))
        #expect(!root.contains("SIMCTL_CHILD_"))
        #expect(!root.contains("publishDps"))
        #expect(!root.contains("writeValue"))
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
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
