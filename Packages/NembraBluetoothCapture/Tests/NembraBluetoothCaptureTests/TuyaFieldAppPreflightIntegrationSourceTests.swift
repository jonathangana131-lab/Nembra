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

    @Test("only fresh repeated correlation authorizes the current Bluetooth target")
    func targetAuthorityIsFreshAndDeterministic() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("var likely: Bool { freshlyCorrelated }"))
        #expect(!source.contains("var likely: Bool { knownID"))
        #expect(!source.contains("knownID || (fd50 && tuyaCompany)"))
        #expect(!source.contains("fd50 && tuyaCompany ?"))
        #expect(!source.contains("score >= 600"))
        #expect(source.contains("matches C7D09A22 capture-local UUID descriptive"))
        #expect(source.contains("Do not fall back to the historical capture UUID"))
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
        #expect(source.contains("observation_poll_gap_exceeded"))
        guard let watchdog = source.range(of: "private func startWatchdog(token:"),
              let gapFailure = source.range(of: "observation_poll_gap_exceeded", range: watchdog.upperBound..<source.endIndex),
              let observationAdvance = source.range(of: "sessionLedger.observeCurrentConnection(for: token)", range: watchdog.upperBound..<source.endIndex) else {
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

    @Test("physical gate docs cannot weaken the canonical authenticated preflight")
    func physicalGateDocsTrackCanonicalThresholds() throws {
        let physicalTruth = try readRepositoryFile("docs/ES80_PHYSICAL_TRUTH_C7D09A22.md")
        let stationaryGate = try readRepositoryFile("docs/ES80_AUTHENTICATED_STATIONARY_GATE_V14.md")

        let payloadCount = TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount
        let payloadSurvivalSeconds = TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds / 1_000_000_000
        let continuitySeconds = TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds / 1_000_000_000

        #expect(physicalTruth.contains("at least **\(payloadCount)** real, non-empty application notification payloads"))
        #expect(physicalTruth.contains("at least **\(payloadSurvivalSeconds).0 seconds after authentication**"))
        #expect(physicalTruth.contains("at least **\(continuitySeconds).0 seconds after authentication**"))

        #expect(stationaryGate.contains("at least **\(payloadCount)** admitted genuine non-empty application payloads"))
        #expect(stationaryGate.contains("at least **\(continuitySeconds) seconds after authentication**"))
        #expect(stationaryGate.contains("at least **\(payloadSurvivalSeconds) seconds after authentication**"))

        #expect(!physicalTruth.contains("acceptance boundary is strictly `>30.0 s` plus real notify payload evidence"))
        #expect(!stationaryGate.contains("at least **one genuine non-empty application notification payload**"))
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
