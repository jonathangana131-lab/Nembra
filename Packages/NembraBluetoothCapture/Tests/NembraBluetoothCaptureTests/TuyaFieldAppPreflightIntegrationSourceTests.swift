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
            "The field app must obtain the verdict snapshot through the accepted session-provider boundary so authentication provenance and connection generation stay attached to the payload chronology."
        )
        #expect(
            !entrypoint.contains("var passed: Bool { secure && packetCount > 0"),
            "Do not duplicate the physical acceptance authority with a local secure/payload/timer boolean."
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
