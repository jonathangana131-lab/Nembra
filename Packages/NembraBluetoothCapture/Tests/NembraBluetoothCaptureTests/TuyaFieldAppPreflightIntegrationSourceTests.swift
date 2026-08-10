import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field-app authenticated preflight integration")
struct TuyaFieldAppPreflightIntegrationSourceTests {
    @Test("standalone Capture target compiles the authoritative Tuya preflight")
    func standaloneTargetCompilesAuthoritativePreflight() throws {
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")
        #expect(
            project.contains("TuyaAuthenticatedReadOnlyPreflight.swift"),
            "The physical field target must compile the same authenticated preflight that package tests accept. Package-only truth cannot authorize a phone test."
        )
    }

    @Test("field Entrypoint consumes the authoritative verdict instead of a hand-rolled pass boolean")
    func fieldEntrypointConsumesAuthoritativeVerdict() throws {
        let entrypoint = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(
            entrypoint.contains("TuyaAuthenticatedReadOnlyPreflight.verdict"),
            "The standalone field app must make its pass/blocked decision through TuyaAuthenticatedReadOnlyPreflight.verdict(for:)."
        )
        #expect(
            entrypoint.contains("TuyaReadOnlyAuthenticationSessionProvider"),
            "The field app must obtain the verdict snapshot through the accepted session-provider boundary."
        )
        #expect(
            !entrypoint.contains("var passed: Bool"),
            "Do not duplicate physical acceptance authority with a local pass boolean."
        )
    }

    @Test("Tuya SDK remains the sole BLE owner after authentication begins")
    func secureObservationDoesNotOpenSecondCoreBluetoothConnection() throws {
        let entrypoint = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let runbook = try readRepositoryFile("docs/CAPTURE_NEXT_TUYA_SECURE_LINK_TEST.md")
        #expect(
            !entrypoint.contains("central.connect("),
            "Once the official Tuya SDK owns the authenticated BLE link, the field app must not open a second Nembra-owned CoreBluetooth connection."
        )
        #expect(entrypoint.contains("ThingSmartDeviceDelegate"))
        #expect(runbook.contains("SDK exclusively own the authenticated BLE connection"))
    }

    @Test("SDK initialization precedes the first account-session authority read")
    func sdkInitializationPrecedesAccountAuthorityRead() throws {
        let entrypoint = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        guard let start = entrypoint.range(of: "start(withAppKey:"),
              let isLogin = entrypoint.range(of: "isLogin") else {
            Issue.record("Field source must explicitly initialize ThingSmartSDK and inspect the official ThingSmartUser login state.")
            return
        }
        #expect(start.lowerBound < isLogin.lowerBound)
    }

    @Test("SDK account authorization uses one-time email code and never a reusable password")
    func accountAuthorizationAvoidsReusablePassword() throws {
        let entrypoint = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(entrypoint.contains("sendVerifyCode(withUserName:"))
        #expect(entrypoint.contains("login(withEmail:"))
        #expect(entrypoint.contains("type: 2"))
        #expect(!entrypoint.contains("SecureField("))
        #expect(!entrypoint.contains("login(byEmail:"))
        #expect(!entrypoint.contains("login(byPhone:"))
    }

    @Test("connect callback cannot mint authenticated chronology")
    func connectCallbackDoesNotStartAuthenticatedClock() throws {
        let entrypoint = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        guard let callback = entrypoint.range(of: "private func officialConnectReturnedSuccess()"),
              let refresh = entrypoint.range(of: "private func refreshSDKConnectionState()") else {
            Issue.record("Expected explicit official connect callback and local BLE refresh boundary.")
            return
        }
        let callbackBody = String(entrypoint[callback.lowerBound..<refresh.lowerBound])
        #expect(!callbackBody.contains("authenticatedAtUptime ="))
        #expect(callbackBody.contains("refreshSDKConnectionState()"))
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
