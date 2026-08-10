import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field-app canonical Tuya preflight")
struct TuyaFieldAppCanonicalPreflightSourceTests {
    @Test("standalone field app consumes accepted membership and session authorities")
    func consumesAcceptedAuthorities() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("import NembraBluetoothCapture"))
        #expect(source.contains("TuyaSDKAccountDeviceMembershipGate.verdict"))
        #expect(source.contains("TuyaAuthenticatedReadOnlySessionLedger()"))
        #expect(source.contains("TuyaAuthenticatedReadOnlyPreflight.verdict(for:"))
        #expect(source.contains("recordApplicationPayload"))
        #expect(source.contains("observeCurrentConnection"))
        #expect(source.contains("markAuthenticated"))
        #expect(source.contains("method: .smartLifeAppSDK"))
    }

    @Test("field app has one BLE connection owner and no parallel pass authority")
    func oneBLEOwnerNoParallelPass() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(!source.contains("central.connect("))
        #expect(!source.contains("var passed: Bool"))
        #expect(!source.contains("writeValue("))
        #expect(source.contains("ThingSmartBLEManager.sharedInstance().connectBLE"))
        #expect(source.contains("deviceStatue(withUUID:"))
    }

    @Test("candidate authorization excludes score name RSSI and power-cycle hints")
    func targetAuthorizationIsDeterministic() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let candidateStart = source.range(of: "struct Candidate:"),
              let phaseStart = source.range(of: "enum Phase:", range: candidateStart.upperBound..<source.endIndex) else {
            Issue.record("Expected Candidate and Phase declarations in the field entrypoint.")
            return
        }
        let candidate = String(source[candidateStart.lowerBound..<phaseStart.lowerBound])
        #expect(candidate.contains("knownID || (fd50 && tuyaCompany)"))
        #expect(!candidate.contains("score >="))
        #expect(!candidate.contains("expectedName ||"))
        #expect(!candidate.contains("newAfterPowerOn ||"))
    }

    @Test("official connect callback cannot mint authenticated chronology")
    func transportSuccessCannotMintAuthentication() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let callbackStart = source.range(of: "private func officialConnectReturnedSuccess"),
              let samplerStart = source.range(of: "private func sampleCurrentLocalBLE", range: callbackStart.upperBound..<source.endIndex) else {
            Issue.record("Expected explicit connect callback and current-local-BLE sampler.")
            return
        }
        let callback = String(source[callbackStart.lowerBound..<samplerStart.lowerBound])
        #expect(!callback.contains("markAuthenticated"))
        #expect(!callback.contains("authenticationRecorded = true"))
        #expect(callback.contains("sampleCurrentLocalBLE"))
    }

    @Test("exact SDK account device membership is fail-closed and read-only")
    func exactDeviceMembershipGateIsWired() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("ThingSmartHomeManager()"))
        #expect(source.contains("getHomeList(success:"))
        #expect(source.contains("getDataWithSuccess"))
        #expect(source.contains("home.deviceList"))
        #expect(source.contains("home.sharedDeviceList"))
        #expect(source.contains("expectedDeviceID: expectedDeviceID"))
        #expect(source.contains("guard case .authorized = membershipVerdict"))
        #expect(!source.contains("activeBLE("))
        #expect(!source.contains("dismissHome("))
    }

    @Test("SDK application callbacks are not mislabeled as raw FD50 transport bytes")
    func applicationEvidenceTruthBoundary() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("rawFD50BytesCaptured: false"))
        #expect(source.contains("Not byte-exact and not raw FD50 transport"))
        #expect(source.contains("ThingSmartDeviceDelegate dpsUpdate values"))
    }

    @Test("standalone Capture target links the package that owns canonical preflight")
    func standaloneTargetLinksPackage() throws {
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")

        #expect(project.contains("NembraBluetoothCapture"))
        #expect(project.contains("XCLocalSwiftPackageReference"))
        #expect(project.contains("XCSwiftPackageProductDependency"))
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
