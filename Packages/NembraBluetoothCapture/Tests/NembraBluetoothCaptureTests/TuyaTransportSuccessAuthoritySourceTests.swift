import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Tuya transport-success authority")
struct TuyaTransportSuccessAuthoritySourceTests {
    @Test("transport success cannot silently strand a current generation after source authority drifts")
    func transportSuccessRetiresDriftedSourceAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let authenticated = app.range(of: "private func authenticated(token:"),
              let nextFunction = app.range(of: "private func authenticationFailed", range: authenticated.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate the Tuya transport-success handler.")
            return
        }
        let handler = String(app[authenticated.lowerBound..<nextFunction.lowerBound])

        #expect(handler.contains("currentConnectionToken == token"))
        #expect(handler.contains("invalidateSourceAuthority"))
        #expect(handler.contains("sdk_source_authority_lost_before_local_ble_settlement"))
        #expect(handler.contains("sdk_driver_authority_lost_before_local_ble_settlement"))
        #expect(!handler.contains("sdkDeviceMembershipVerified,\n              accountIdentityLeaseIsAuthorized,\n              let driver else { return }"))

        guard let sourceTerminal = handler.range(of: "sdk_source_authority_lost_before_local_ble_settlement"),
              let settlement = handler.range(of: "TuyaLocalBLEAcquisitionWindow.verdict") else {
            Issue.record("Source authority must be terminally checked before local-BLE settlement begins.")
            return
        }
        #expect(sourceTerminal.lowerBound < settlement.lowerBound)
    }

    @Test("duplicate success callbacks share one settlement owner and auth mutation failure retires internally")
    func duplicateSuccessCannotStartParallelSettlement() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let authenticated = app.range(of: "private func authenticated(token:"),
              let nextFunction = app.range(of: "private func authenticationFailed", range: authenticated.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate the Tuya transport-success handler.")
            return
        }
        let handler = String(app[authenticated.lowerBound..<nextFunction.lowerBound])

        #expect(app.contains("private var localBLESettlementToken: TuyaReadOnlyConnectionToken?"))
        #expect(handler.contains("localBLESettlementToken != token"))
        #expect(handler.contains("duplicate_connect_success_settlement_ignored"))
        #expect(handler.contains("localBLESettlementToken = token"))
        #expect(handler.contains("defer"))
        #expect(handler.contains("sessionLedger.markAuthenticated"))
        #expect(handler.contains("session_auth_callback_rejected"))

        guard let promotion = handler.range(of: "sessionLedger.markAuthenticated"),
              let keepWaiting = handler.range(of: "case .keepWaiting:", range: promotion.upperBound..<handler.endIndex) else {
            Issue.record("Could not isolate authentication promotion failure cleanup.")
            return
        }
        let promotionTerminal = String(handler[promotion.lowerBound..<keepWaiting.lowerBound])

        // Current Tuya account/device source authority has already been checked before promotion.
        // If the owner-bound ledger mutation itself rejects chronology/invariants, cleanup must use
        // the package's exact-token no-resample internal-lifecycle terminal, not invent source drift.
        #expect(promotionTerminal.contains("MutationError.monotonicClockRegressed"))
        #expect(promotionTerminal.contains("invalidateInternalLifecycle"))
        #expect(!promotionTerminal.contains("invalidateSourceAuthority"))
        #expect(!promotionTerminal.contains("authenticationAcquisitionFailed"))
        #expect(!promotionTerminal.contains("markAuthenticationFailed"))
        #expect(!handler.contains("failLocally(\"Authenticated-session chronology rejected"))
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
}
