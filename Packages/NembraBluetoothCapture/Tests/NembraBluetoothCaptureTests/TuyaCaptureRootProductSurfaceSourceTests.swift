import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture root product surface")
struct TuyaCaptureRootProductSurfaceSourceTests {
    @Test("public unprovisioned launch is guided fail-closed Capture preflight, not an engineering console")
    func publicRootIsGuidedPreflight() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = try section(
            in: app,
            from: "private struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController"
        )
        let body = String(root)

        #expect(body.contains(".navigationTitle(\"Nembra Capture\")"))
        #expect(!body.contains("NEMBRA CAPTURE"))
        #expect(body.contains("private let buildIdentity = NembraCaptureBuildIdentity.current"))
        #expect(body.contains("isAccessibilityLayout ? \"Capture locked\" : \"Physical capture locked\""))
        #expect(body.contains(".accessibilityLabel(fieldBuildIsAuthoritative ? \"Build provenance ready\" : \"Physical capture locked\")"))
        #expect(body.contains("This public build can prepare account metadata only. Bluetooth and physical evidence collection are locked."))
        #expect(body.contains("Account setup is available. Bluetooth scanning, connection, and physical evidence stay locked until the reviewed field build is installed."))
        #expect(body.contains("This step reads Tuya account/device metadata only. It never starts Bluetooth or changes scooter settings."))
        #expect(body.contains("Engineering details"))
        #expect(body.contains("Build provenance: ready"))
        #expect(body.contains("Continue to preflight"))
        #expect(!body.contains("Field build ready"))
        #expect(!body.contains("Field build authority: ready"))
        #expect(!body.contains("Continue to Capture"))
        #expect(!body.contains("P0 · TUYA AUTHENTICATION"))
        #expect(!body.contains("Prove the secure scooter link first."))
        #expect(!body.contains("Read-only control boundary"))
        #expect(!body.contains("local_key"))
        #expect(!body.contains("No DP query"))
        #expect(!body.contains(".card()"))
    }

    @Test("premium root preserves the real account and device authority path")
    func accountAndDeviceAuthorityRemainReachable() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = try section(
            in: app,
            from: "private struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController"
        )
        let body = String(root)

        #expect(body.contains("tuya.requestApproval()"))
        #expect(body.contains("tuya.checkApprovalNow()"))
        #expect(body.contains("tuya.refreshDevices()"))
        #expect(body.contains("tuya.selectDevice(device)"))
        #expect(body.contains("SecureLinkView(device: device)"))
        #expect(body.contains("NavigationLink(fieldBuildIsAuthoritative ? \"Continue to preflight\" : \"View locked preflight\")"))
        #expect(app.contains("No DP query or scooter command is authorized by this surface."))
    }

    @Test("Accessibility XXXL keeps the primary metadata action in the first fold")
    func accessibilityRootIsDeliberatelyCompactAndActionFirst() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: app,
            from: "private struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController"
        ))

        #expect(root.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
        #expect(root.contains("private var isAccessibilityLayout: Bool"))
        #expect(root.contains("private var rootHero: some View"))
        #expect(root.contains("if !isAccessibilityLayout"))
        #expect(root.contains("isAccessibilityLayout ? \"Capture locked\" : \"Physical capture locked\""))
        #expect(root.contains(".dynamicTypeSize(...DynamicTypeSize.accessibility1)"))
        #expect(root.contains("isAccessibilityLayout ? \"Account setup\" : \"Prepare account metadata\""))
        #expect(root.contains(".accessibilityAddTraits(.isHeader)"))
        #expect(root.contains("Text(\"Choose this scooter\")\n                .font(.title3.bold())\n                .accessibilityAddTraits(.isHeader)"))
        #expect(root.contains("TextField(isAccessibilityLayout ? \"Tuya user code\" : \"Paste user code\""))
        #expect(root.contains("Label(isAccessibilityLayout ? \"Create QR\" : \"Create approval QR\""))
        #expect(root.contains(".accessibilityLabel(\"Create approval QR\")"))
        #expect(root.contains("nembra.capture.root.account-link-action"))
        #expect(root.contains("private func rootSection"))
        #expect(!root.contains("private func rootPanel"))
        #expect(!root.contains("Account setup only in this public build."))

        let panel = String(try section(
            in: root,
            from: "private var accountSetupPanel: some View",
            to: "private var statusText: some View"
        ))
        let field = try #require(panel.range(of: "TextField(isAccessibilityLayout ? \"Tuya user code\" : \"Paste user code\""))
        let action = try #require(panel.range(of: "Label(isAccessibilityLayout ? \"Create QR\" : \"Create approval QR\""))
        let accessibilitySupport = try #require(
            panel.range(
                of: "if isAccessibilityLayout, tuya.phase != .needsUserCode",
                range: action.upperBound..<panel.endIndex
            )
        )
        #expect(field.lowerBound < action.lowerBound)
        #expect(action.lowerBound < accessibilitySupport.lowerBound)

        let authority = String(try section(
            in: root,
            from: "private var buildAuthorityStatus: some View",
            to: "private var accountSetupPanel: some View"
        ))
        #expect(authority.contains(".accessibilityLabel(fieldBuildIsAuthoritative ? \"Build provenance ready\" : \"Physical capture locked\")"))
        #expect(authority.contains("This public build can prepare account metadata only. Bluetooth and physical evidence collection are locked."))

        let secureLink = String(try section(
            in: app,
            from: "private struct SecureLinkView: View",
            to: "private struct SecureTransfer: Transferable"
        ))
        #expect(secureLink.contains("if !dynamicTypeSize.isAccessibilitySize {\n                    ZStack {"))
        #expect(secureLink.contains(".font(dynamicTypeSize.isAccessibilitySize ? .title2.bold() : .system(.largeTitle, design: .rounded, weight: .bold))"))
        #expect(secureLink.contains(".accessibilityElement(children: .combine)\n        .accessibilityAddTraits(.isHeader)"))
    }

    @Test("metadata preparation bridge remains cloud-only and command-free")
    func metadataBridgeCannotAcquireBluetoothOrScooterCommandAuthority() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")

        #expect(bridge.contains("Official Tuya Smart account-link preflight"))
        #expect(bridge.contains("read-only Device Sharing endpoints"))
        #expect(bridge.contains("signedGET(path:"))
        #expect(!bridge.contains("import CoreBluetooth"))
        #expect(!bridge.contains("ThingSmartBLEManager"))
        #expect(!bridge.contains("connectBLE"))
        #expect(!bridge.contains("disconnectBLE"))
        #expect(!bridge.contains("publishDps"))
        #expect(!bridge.contains("queryDps"))
        #expect(!bridge.contains("writeValue"))
        #expect(!bridge.contains("setDp"))
    }

    @Test("cloud status is never mislabeled as local strategy evidence")
    func metadataExportPreservesStatusTruth() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        #expect(!bridge.contains("selectedDeviceLocalStrategy"))
        #expect(!bridge.contains("\"localStrategy\""))
        #expect(!bridge.contains("/status\")"))
        #expect(bridge.contains("\"status\": Self.redactSecrets(selectedDeviceStatus ?? [:])"))
        #expect(bridge.contains("\"specifications\": Self.redactSecrets(selectedDeviceSpecifications ?? [:])"))
    }

    @Test("legacy card-based Capture root is retired from the metadata bridge")
    func legacyCardRootIsRetired() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")

        #expect(bridge.contains("final class TuyaAccountBridge: ObservableObject"))
        #expect(bridge.contains("struct TuyaQRCodeExport: Transferable"))
        #expect(bridge.contains("struct TuyaMetadataExport: Transferable"))
        #expect(!bridge.contains("struct NembraCaptureRootView: View"))
        #expect(!bridge.contains("func captureCard() -> some View"))
        #expect(!bridge.contains("ES80OneTimeBluetoothDumpView()"))
        #expect(!bridge.contains("We already proved this scooter uses Tuya FD50."))
        #expect(!bridge.contains("Continue to Bluetooth Capture"))
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
