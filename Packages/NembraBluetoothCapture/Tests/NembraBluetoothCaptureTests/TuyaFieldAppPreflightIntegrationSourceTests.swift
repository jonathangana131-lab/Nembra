import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field authenticated-preflight integration")
struct TuyaFieldAppPreflightIntegrationSourceTests {
    @Test("standalone Capture target links authenticated authority package")
    func fieldTargetLinksAuthorityPackage() throws {
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")

        #expect(project.contains("XCLocalSwiftPackageReference \"Packages/NembraBluetoothCapture\""))
        #expect(project.contains("NembraBluetoothCapture in Frameworks"))
        #expect(project.contains("NembraBluetoothCapture */,"))
    }

    @Test("field controller drives sealed ledger and canonical verdict")
    func fieldControllerConsumesSealedAuthority() throws {
        let entrypoint = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(entrypoint.contains("import NembraBluetoothCapture"))
        #expect(entrypoint.contains("TuyaAuthenticatedReadOnlySessionLedger()"))
        #expect(entrypoint.contains("sessionLedger.beginConnection()"))
        #expect(entrypoint.contains("sessionLedger.markAuthenticated(for: token, method: .smartLifeAppSDK)"))
        #expect(entrypoint.contains("sessionLedger.recordApplicationPayload(representation, for: token)"))
        #expect(entrypoint.contains("TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot)"))
        #expect(entrypoint.contains("var passed: Bool { authoritativePreflightReady }"))
        #expect(!entrypoint.contains("var passed: Bool {\n        secureSessionEstablished &&"))
    }

    @Test("current connection token binds every authority-bearing SDK callback")
    func currentConnectionTokenOwnsCallbacks() throws {
        let entrypoint = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(entrypoint.contains("token == connectionToken"))
        #expect(entrypoint.contains("latestApplicationPayloadUptimeNanoseconds"))
        #expect(entrypoint.contains("maximumObservationPollGapNanoseconds"))
        #expect(entrypoint.contains("application_update_ignored_without_current_local_ble"))
        #expect(entrypoint.contains("sdk_local_ble_authenticated"))
    }

    @Test("target authorization ignores name RSSI and accumulated score")
    func targetAuthorityUsesPriorIdentityOrCorroboratedTuyaTransport() throws {
        let entrypoint = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(entrypoint.contains("var likely: Bool { knownID || (fd50 && tuyaCompany) }"))
        #expect(!entrypoint.contains("score >= 600"))
    }

    @Test("Tuya SDK is the only authenticated BLE owner")
    func noSecondCoreBluetoothConnectionAfterSDKOwnership() throws {
        let entrypoint = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(!entrypoint.contains("central.connect("))
        #expect(entrypoint.contains("ThingSmartBLEManager.sharedInstance().connectBLE"))
        #expect(entrypoint.contains("ThingSmartBLEManager.sharedInstance().deviceStatue(withUUID:"))
        #expect(entrypoint.contains("ThingSmartDeviceDelegate"))
    }

    @Test("diagnostics distinguish SDK application values from raw FD50 bytes")
    func exportDoesNotOverclaimRawTransport() throws {
        let entrypoint = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(entrypoint.contains("rawFD50BytesCaptured: false"))
        #expect(entrypoint.contains("not byte-exact or raw FD50 transport"))
        #expect(entrypoint.contains("authoritativePreflightReady"))
        #expect(entrypoint.contains("connectionGeneration"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
