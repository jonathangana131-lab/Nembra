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
            "The field app must obtain the verdict snapshot through the accepted session-provider boundary so authentication provenance and connection generation stay attached to payload chronology."
        )
        #expect(
            !entrypoint.contains("var passed: Bool { secure") && !entrypoint.contains("var passed: Bool { secureSessionEstablished"),
            "Do not duplicate physical acceptance authority with a local secure/payload/timer boolean."
        )
    }

    @Test("Tuya SDK remains the sole BLE owner after authentication begins")
    func secureObservationDoesNotOpenSecondCoreBluetoothConnection() throws {
        let entrypoint = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let runbook = try readRepositoryFile("docs/CAPTURE_NEXT_TUYA_SECURE_LINK_TEST.md")

        #expect(
            !entrypoint.contains("central.connect("),
            "Once the official Tuya SDK owns the authenticated BLE link, the field app must not open a second Nembra-owned CoreBluetooth connection to manufacture post-auth evidence."
        )
        #expect(
            entrypoint.contains("ThingSmartDeviceDelegate"),
            "Authenticated application evidence must come from the SDK-owned device/session boundary."
        )
        #expect(
            runbook.contains("SDK exclusively own the authenticated BLE connection"),
            "The executable source contract must stay aligned with the locked one-owner physical runbook."
        )
    }

    @Test("SDK initialization precedes the first account-session authority read")
    func sdkInitializationPrecedesAccountAuthorityRead() throws {
        let entrypoint = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        guard let start = entrypoint.range(of: "start(withAppKey:"),
              let isLogin = entrypoint.range(of: "isLogin") else {
            Issue.record("Field source must explicitly initialize ThingSmartSDK and inspect the official ThingSmartUser login state.")
            return
        }

        #expect(
            start.lowerBound < isLogin.lowerBound,
            "A fresh install must initialize ThingSmartSDK with the private app identity before ThingSmartUser.isLogin is allowed to gate the secure-link flow."
        )
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // NembraBluetoothCaptureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // NembraBluetoothCapture
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repository root

        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
