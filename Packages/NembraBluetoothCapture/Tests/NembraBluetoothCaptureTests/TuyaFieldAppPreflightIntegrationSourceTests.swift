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

    @Test("package discovery cannot restart after official Tuya takes BLE ownership")
    func officialTuyaOwnershipIsProcessLifetimeLatched() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("officialTuyaOwnershipStarted"))
        #expect(source.contains("package_discovery_blocked_after_tuya_ownership"))

        guard let ownershipLatch = source.range(of: "officialTuyaOwnershipStarted = true"),
              let connectRequest = source.range(of: "newDriver.connect(") else {
            Issue.record("Official Tuya ownership must be latched before the supported SDK connection starts.")
            return
        }
        #expect(ownershipLatch.lowerBound < connectRequest.lowerBound)

        guard let startBaseline = source.range(of: "func startBaseline()"),
              let saveBaseline = source.range(of: "func saveBaseline()"),
              let powerOnScan = source.range(of: "func scanAfterPowerOn()"),
              let stopScan = source.range(of: "func stopScan()") else {
            Issue.record("Expected guided discovery entrypoints are missing.")
            return
        }

        let baselineBody = String(source[startBaseline.lowerBound..<saveBaseline.lowerBound])
        let powerOnBody = String(source[powerOnScan.lowerBound..<stopScan.lowerBound])
        #expect(baselineBody.contains("guard !officialTuyaOwnershipStarted"))
        #expect(powerOnBody.contains("guard !officialTuyaOwnershipStarted"))

        guard let resetDiscovery = source.range(of: "private func resetDiscovery()"),
              let fail = source.range(of: "private func fail(", range: resetDiscovery.upperBound..<source.endIndex) else {
            Issue.record("Expected discovery reset boundary is missing.")
            return
        }
        let resetBody = String(source[resetDiscovery.lowerBound..<fail.lowerBound])
        #expect(!resetBody.contains("officialTuyaOwnershipStarted = false"))
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
