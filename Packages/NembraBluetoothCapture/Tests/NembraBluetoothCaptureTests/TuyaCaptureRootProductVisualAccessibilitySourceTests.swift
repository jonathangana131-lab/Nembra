import Foundation
import Testing

@Suite("Capture root product visual accessibility")
struct TuyaCaptureRootProductVisualAccessibilitySourceTests {
    @Test("root intentionally recomposes the first action for Accessibility Dynamic Type")
    func rootRecomposesActionDiscoveryAtAccessibilitySizes() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: app,
            from: "private struct CaptureP0Root: View",
            to: "private final class SecureLinkController"
        ))

        #expect(root.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
        #expect(root.contains("private var isAccessibilityLayout: Bool { dynamicTypeSize.isAccessibilitySize }"))
        #expect(root.contains("Text(isAccessibilityLayout ? \"Set up Capture\" : \"Prepare the scooter link\")"))
        #expect(root.contains("if !isAccessibilityLayout {\n                Text(\"NEMBRA CAPTURE\")"))

        let account = String(try section(
            in: root,
            from: "private var accountSection: some View",
            to: "private var statusText: some View"
        ))
        let field = try #require(account.range(of: "TextField(\"Tuya Smart User Code\""))
        let action = try #require(account.range(of: "Label(\"Create approval QR\", systemImage: \"qrcode\")"))
        let accessibilityStatus = try #require(
            account.range(
                of: "if isAccessibilityLayout {\n                        statusText",
                range: action.upperBound..<account.endIndex
            )
        )

        #expect(field.lowerBound < action.lowerBound)
        #expect(action.lowerBound < accessibilityStatus.lowerBound)
        #expect(account.contains(".frame(maxWidth: .infinity, minHeight: 50)"))
        #expect(account.contains(".frame(minHeight: 52)"))
        #expect(account.contains("Bluetooth remains off"))
    }

    @Test("root visual recompose stays presentation-only and flatter than the old setup-card stack")
    func rootRecomposePreservesAuthorityAndHierarchy() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: app,
            from: "private struct CaptureP0Root: View",
            to: "private final class SecureLinkController"
        ))

        #expect(root.contains("private func rootSection<Content: View>"))
        #expect(!root.contains("private func rootPanel<Content: View>"))
        #expect(root.contains("Color.white.opacity(0.14)"))
        #expect(root.contains("Color.white.opacity(0.76)"))
        #expect(root.contains("Color.white.opacity(0.74)"))
        #expect(root.contains("NavigationLink(\"Continue to Capture\") { SecureLinkView(device: device) }"))
        #expect(root.contains("tuya.requestApproval()"))
        #expect(root.contains("tuya.checkApprovalNow()"))
        #expect(root.contains("tuya.selectDevice(device)"))

        #expect(!root.contains("writeValue"))
        #expect(!root.contains("publishDps"))
        #expect(!root.contains("queryDps"))
        #expect(!root.contains("SIMCTL_CHILD"))
        #expect(!root.contains("NEMBRA_SIMULATION"))
    }
}
