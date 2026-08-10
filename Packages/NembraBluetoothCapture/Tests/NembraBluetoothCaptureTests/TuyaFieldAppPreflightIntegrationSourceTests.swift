import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field authenticated-preflight integration")
struct TuyaFieldAppPreflightIntegrationSourceTests {
    @Test("field app uses current structured application-update ledger API")
    func structuredSDKUpdateIsNotFabricatedIntoTransportBytes() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("recordApplicationUpdate(isNonEmpty:"))
        #expect(!source.contains("recordApplicationPayload("))
        #expect(!source.contains("JSONSerialization.data(withJSONObject: update"))
        #expect(source.contains("rawFD50BytesCaptured: false"))
    }

    @Test("name RSSI and accumulated score never authorize the target")
    func targetAuthorityIsDeterministic() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("var likely: Bool { knownID || (fd50 && tuyaCompany) }"))
        #expect(!source.contains("score >= 600"))
    }

    @Test("official Tuya connect failure uses documented no-error handler")
    func connectBLEFailureShapeIsCurrent() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("failure: @escaping () -> Void"))
        #expect(!source.contains("failure: @escaping (String) -> Void"))
        #expect(!source.contains("failure: { error in"))
    }

    @Test("observation gaps cannot be counted into the 45 second gate")
    func suspensionGapFailsClosedBeforeObservationAdvance() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("maximumObservationPollGapNanoseconds"))
        #expect(source.contains("observation_continuity_gap"))
        guard let gapFailure = source.range(of: "observation_continuity_gap"),
              let observationAdvance = source.range(of: "sessionLedger.observeCurrentConnection(for: token)") else {
            Issue.record("Field source must reject a long monotonic observation gap before advancing ledger liveness.")
            return
        }
        #expect(gapFailure.lowerBound < observationAdvance.lowerBound)
    }

    @Test("canonical ledger and membership gates remain app-visible")
    func canonicalAuthorityRemainsIntegrated() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("import NembraBluetoothCapture"))
        #expect(source.contains("TuyaAuthenticatedReadOnlySessionLedger()"))
        #expect(source.contains("TuyaAuthenticatedReadOnlyPreflight.verdict(for: ledgerSnapshot)"))
        #expect(source.contains("TuyaSDKAccountDeviceMembershipGate.verdict"))
        #expect(!source.contains("central.connect("))
    }

    @Test("private workspace consumes generated Tuya app identity instead of requiring launch environment")
    func privateIdentityPodIsActuallyConsumedByFieldApp() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let podfile = try readRepositoryFile("Podfile")
        let provisioner = try readRepositoryFile("Scripts/provision_capture_tuya_identity.sh")

        #expect(podfile.contains("pod 'NembraTuyaPrivateConfig'"))
        #expect(provisioner.contains("NembraTuyaPrivateIdentity"))
        #expect(
            source.contains("canImport(NembraTuyaPrivateConfig)") || source.contains("import NembraTuyaPrivateConfig"),
            "Generating and linking a local private identity pod is not enough. The signed field app must explicitly consume that module so a normal installed iPhone launch can initialize ThingSmartSDK without Xcode launch-only environment variables."
        )
        #expect(source.contains("NembraTuyaPrivateIdentity.appKey"))
        #expect(source.contains("NembraTuyaPrivateIdentity.appSecret"))
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
