import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture root product surface")
struct TuyaCaptureRootProductSurfaceSourceTests {
    @Test("public launch is guided and only complete metadata may prepare non-authorizing transport")
    func publicRootIsGuidedPreflight() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: app,
            from: "@MainActor\nprivate struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController:"
        ))

        #expect(root.contains(".navigationTitle(\"Nembra Capture\")"))
        #expect(root.contains("Text(\"Link your scooter\")"))
        #expect(root.contains("private var fieldBuildCanPrepareAuthorization: Bool { buildIdentity.hasCompleteFieldBuildMetadata }"))
        #expect(root.contains(".onAppear {\n            prepareAuthorizationTransport()\n            synchronizeSDKSession()\n        }"))
        #expect(root.contains("guard fieldBuildCanPrepareAuthorization else { return }\n        sdkAccount.bootstrap()"))
        #expect(!root.contains("guard fieldBuildIsAuthoritative else { return }\n        sdkAccount.bootstrap()"))
        #expect(root.contains("prepareAuthorizationTransferDirectoryForFieldTransport()"))
        #expect(root.contains("Label(\"Review field requirements\", systemImage: \"lock.shield\")"))
        #expect(root.contains("This public build cannot authorize Bluetooth or collect physical evidence."))
        #expect(root.contains("No scooter command, DP query, or second Bluetooth ownership path is authorized here."))
        #expect(!root.contains("TuyaAccountBridge"))
        #expect(!root.contains("Create approval QR"))
        #expect(!root.contains("Paste user code"))
        #expect(!root.contains("local_key"))
    }

    @Test("root owns one official account authorizer and injects it into Secure Link")
    func oneOfficialSDKAccountAuthorityIsSharedWithSecureLink() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try section(
            in: app,
            from: "@MainActor\nprivate struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController:"
        ))
        let secureLink = String(try section(
            in: app,
            from: "@MainActor\nprivate struct SecureLinkView: View",
            to: "private struct SecureTransfer: Transferable"
        ))

        #expect(root.occurrenceCount(of: "@StateObject private var sdkAccount = OfficialTuyaAccountAuthorizer()") == 1)
        #expect(root.contains("SignInWithAppleButton(.signIn)"))
        #expect(root.contains("DisclosureGroup(\"Use email or phone instead\""))
        #expect(root.contains("SecureLinkView(device: selected, sdkAccount: sdkAccount)"))
        #expect(secureLink.contains("@ObservedObject private var sdkAccount: OfficialTuyaAccountAuthorizer"))
        #expect(secureLink.contains("init(device: CaptureTargetDevice, sdkAccount: OfficialTuyaAccountAuthorizer)"))
        #expect(!secureLink.contains("@StateObject private var sdkAccount = OfficialTuyaAccountAuthorizer()"))
    }

    @Test("catalog completely walks every home and both owned and shared device lists")
    func catalogEnumeratesAllAccountHomesAndMembershipKinds() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let probe = String(try section(
            in: app,
            from: "private final class OfficialTuyaDeviceCatalogProbe",
            to: "@MainActor\nprivate struct CaptureP0Root: View"
        ))

        #expect(probe.contains("homeManager.getHomeList(success:"))
        #expect(probe.contains("self.homes = homes ?? []"))
        #expect(probe.contains("let model = homes[index]\n        index += 1"))
        #expect(probe.contains("ThingSmartHome(homeId: model.homeId)"))
        #expect(probe.contains("home.getDataWithSuccess"))
        #expect(probe.contains("for device in home.deviceList ?? [] { self.admit(device) }"))
        #expect(probe.contains("for device in home.sharedDeviceList ?? [] { self.admit(device) }"))
        #expect(probe.contains("self.loadedHomeCount += 1"))
        #expect(probe.contains("self.loadNextHome()"))
        #expect(probe.contains("try accumulator.finish("))
        #expect(probe.contains("expectedHomeCount: homes.count"))
        #expect(probe.contains("loadedHomeCount: loadedHomeCount"))
        #expect(probe.contains("homeLoadFailureCount: homeLoadFailureCount"))
        #expect(probe.contains("guard !didFinish else { return }"))
    }

    @Test("catalog callbacks are fenced to request and account UID and stale selection is revoked")
    func catalogFencesRequestAndAccountUID() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let catalog = String(try section(
            in: app,
            from: "private final class OfficialTuyaDeviceCatalog: ObservableObject",
            to: "#if canImport(ThingSmartHomeKit)\n@MainActor\nprivate final class OfficialTuyaDeviceCatalogProbe"
        ))
        let probe = String(try section(
            in: app,
            from: "private final class OfficialTuyaDeviceCatalogProbe",
            to: "@MainActor\nprivate struct CaptureP0Root: View"
        ))

        #expect(catalog.contains("private var requestID = UUID()"))
        #expect(catalog.contains("private var sourceAccountUID: String?"))
        #expect(catalog.contains("let request = UUID()\n        requestID = request"))
        #expect(catalog.contains("let accountUID = OfficialTuyaFactory.currentAccountUID"))
        #expect(catalog.contains("guard let self, self.requestID == request else { return }"))
        #expect(catalog.contains("OfficialTuyaFactory.currentAccountUID == accountUID"))
        #expect(catalog.contains("self.invalidate()"))
        #expect(catalog.contains("self.sourceAccountUID = accountUID"))
        #expect(catalog.contains("guard isCurrentAccountCatalog else { return nil }"))
        #expect(catalog.contains("guard isCurrentAccountCatalog,\n              device.hasCompleteLocator"))

        #expect(probe.contains("private let accountUID: String"))
        #expect(probe.contains("private var accountIsCurrent: Bool"))
        #expect(probe.contains("OfficialTuyaFactory.currentAccountUID == accountUID"))
        #expect(probe.occurrenceCount(of: "guard accountIsCurrent else") >= 2)
        #expect(probe.contains("guard self.accountIsCurrent else"))
    }

    @Test("required locators merge deterministically and any conflict or partial home walk fails closed")
    func locatorMergeAndEnumerationPolicyRemainStrict() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let policy = try readRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaSDKDeviceCatalogSelection.swift"
        )

        #expect(app.contains("typealias CaptureTargetDevice = TuyaSDKDeviceLocator"))
        #expect(app.contains("private var accumulator = TuyaSDKDeviceCatalogAccumulator()"))
        #expect(app.contains("accumulator.admit(\n            id: device.devId,\n            name: device.name,\n            productID: device.productId,\n            uuid: device.uuid"))

        #expect(policy.contains("public let id: String"))
        #expect(policy.contains("public let productID: String"))
        #expect(policy.contains("public let uuid: String"))
        #expect(policy.contains("public var hasCompleteLocator: Bool"))
        #expect(policy.contains("!id.isEmpty && !productID.isEmpty && !uuid.isEmpty"))
        #expect(policy.contains("encounteredDeviceIDs.insert(id)"))
        #expect(policy.contains("guard candidate.hasCompleteLocator else"))
        #expect(policy.contains("existing.productID == candidate.productID"))
        #expect(policy.contains("existing.uuid == candidate.uuid"))
        #expect(policy.contains("hasConflictingRequiredLocator = true"))
        #expect(policy.contains("throw TuyaSDKDeviceCatalogSelectionError.conflictingRequiredLocator"))
        #expect(policy.contains("loadedHomeCount == expectedHomeCount"))
        #expect(policy.contains("homeLoadFailureCount == 0"))
        #expect(policy.contains("throw TuyaSDKDeviceCatalogSelectionError.incompleteHomeEnumeration"))
        #expect(policy.contains("Capture will not guess from a partial scooter list."))
    }

    @Test("every account device requires an explicit operator selection")
    func catalogNeverAutoSelects() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let catalog = String(try section(
            in: app,
            from: "private final class OfficialTuyaDeviceCatalog: ObservableObject",
            to: "#if canImport(ThingSmartHomeKit)\n@MainActor\nprivate final class OfficialTuyaDeviceCatalogProbe"
        ))
        let root = String(try section(
            in: app,
            from: "@MainActor\nprivate struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController:"
        ))
        let select = String(try section(
            in: catalog,
            from: "func select(_ device: CaptureTargetDevice) {",
            to: "func invalidate() {"
        ))
        let success = String(try section(
            in: catalog,
            from: "case let .success(snapshot):",
            to: "case let .failure(error):"
        ))

        #expect(select.contains("selectedDeviceID = device.id"))
        #expect(catalog.occurrenceCount(of: "selectedDeviceID = device.id") == 1)
        #expect(!success.contains("selectedDeviceID"))
        #expect(success.contains("One account device was found. Confirm that it is the intended scooter before continuing."))
        #expect(root.contains("Button {\n                        deviceCatalog.select(device)"))
        #expect(root.contains("if let selected = deviceCatalog.selectedDevice, selected.hasCompleteLocator"))
        #expect(root.contains("SecureLinkView(device: selected, sdkAccount: sdkAccount)"))
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

private extension String {
    func occurrenceCount(of needle: String) -> Int {
        var count = 0
        var searchStart = startIndex
        while searchStart < endIndex,
              let match = range(of: needle, range: searchStart..<endIndex) {
            count += 1
            searchStart = match.upperBound
        }
        return count
    }
}