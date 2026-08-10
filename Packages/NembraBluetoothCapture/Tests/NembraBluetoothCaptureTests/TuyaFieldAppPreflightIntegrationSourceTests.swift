import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field-app authenticated preflight integration")
struct TuyaFieldAppPreflightIntegrationSourceTests {
    @Test("standalone Capture target links the authoritative Bluetooth Capture package")
    func standaloneTargetLinksAuthoritativeCapturePackage() throws {
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")

        #expect(
            project.contains("XCLocalSwiftPackageReference \"Packages/NembraBluetoothCapture\"") &&
            project.contains("NembraBluetoothCapture in Frameworks") &&
            project.contains("productName = NembraBluetoothCapture"),
            "The physical field target must link the canonical NembraBluetoothCapture package product. Package-only truth cannot authorize a phone test, and direct source duplication is not an acceptable substitute for the module dependency."
        )
    }

    @Test("field Entrypoint consumes the authoritative verdict instead of a hand-rolled pass boolean")
    func fieldEntrypointConsumesAuthoritativeVerdict() throws {
        let entrypoint = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(
            entrypoint.contains("import NembraBluetoothCapture"),
            "The standalone field app must import the linked authority module before it can consume the accepted preflight contract."
        )
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

    @Test("verification-code success never outranks the SDK login source of truth")
    func verificationCodeSuccessRechecksSDKAccountAuthority() throws {
        let entrypoint = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        guard let functionStart = entrypoint.range(of: "private func finishLoginSuccess()"),
              let nextFunction = entrypoint.range(
                of: "private func finishLoginFailure",
                range: functionStart.upperBound..<entrypoint.endIndex
              ) else {
            Issue.record("Field account authorizer must expose explicit success/failure completion paths for source review.")
            return
        }

        let successBody = String(entrypoint[functionStart.lowerBound..<nextFunction.lowerBound])
        #expect(
            successBody.contains("OfficialTuyaFactory.accountReady"),
            "A Tuya login success callback is not itself account-session authority. Re-read ThingSmartUser.isLogin through OfficialTuyaFactory.accountReady before enabling the secure test."
        )
        #expect(
            !successBody.contains("authorized = true"),
            "Do not let the authorizer's local UI flag become stronger than the official SDK account-session source of truth."
        )
    }

    @Test("Bluetooth discovery is impossible until the official SDK account is authorized")
    func discoveryRequiresCurrentSDKAccountAuthorization() throws {
        let entrypoint = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let startBaseline = try sourceSection(
            in: entrypoint,
            from: "func startBaseline()",
            to: "func saveBaseline()"
        )

        #expect(
            startBaseline.contains("guard sdkAccountAuthorized"),
            "The field controller must fail closed before the scooter-OFF CoreBluetooth scan when the official Tuya SDK account session is not currently authorized. UI-only disabling is not sufficient authority for a physical NO-GO build."
        )
    }

    @Test("SDK account failures redact the entered email or phone before presentation")
    func accountIdentifierIsRedactedFromSDKFailureText() throws {
        let entrypoint = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authorizer = try sourceSection(
            in: entrypoint,
            from: "private final class OfficialTuyaAccountAuthorizer",
            to: "private struct SecureLinkView"
        )

        #expect(
            authorizer.contains("redactAccountIdentifier"),
            "The account authorizer needs one explicit redaction boundary for Tuya error text because an SDK error can echo the submitted email or phone number."
        )
        #expect(
            !authorizer.contains("Tuya could not send the verification code: \\(error?.localizedDescription"),
            "Do not interpolate the SDK error directly into verification-code UI state before removing the submitted account identifier."
        )
        #expect(
            !authorizer.contains("Tuya SDK login failed: \\(error?.localizedDescription"),
            "Do not interpolate the SDK error directly into login UI state before removing the submitted account identifier."
        )
    }

    private func sourceSection(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected field-source section markers were not found: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
