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

    @Test("duplicate success callbacks share one settlement owner and promotion revalidates suspended authority")
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
        #expect(handler.contains("session_auth_promotion_clock_regressed"))

        guard let promotion = handler.range(of: "sessionLedger.markAuthenticated"),
              let keepWaiting = handler.range(of: "case .keepWaiting:", range: promotion.upperBound..<handler.endIndex) else {
            Issue.record("Could not isolate authentication promotion failure cleanup.")
            return
        }
        let promotionTerminal = String(handler[promotion.lowerBound..<keepWaiting.lowerBound])

        // markAuthenticated and refreshLedgerSnapshot are actor suspension points. The exact
        // connection token, account/device lease, and official driver must therefore be checked
        // again before authenticated observation is promoted. A source drift discovered there is
        // source-authority failure; only the ledger's own chronology rejection is internal-lifecycle
        // failure and must not be rewritten as source drift.
        #expect(promotionTerminal.contains("await refreshLedgerSnapshot()"))
        #expect(promotionTerminal.contains("sdk_source_authority_lost_during_auth_promotion"))
        #expect(promotionTerminal.contains("sdk_driver_authority_lost_during_auth_promotion"))
        #expect(promotionTerminal.contains("invalidateSourceAuthority"))
        #expect(promotionTerminal.contains("MutationError.monotonicClockRegressed"))
        #expect(promotionTerminal.contains("invalidateInternalLifecycle"))

        guard let sourceRecheck = promotionTerminal.range(of: "sdk_source_authority_lost_during_auth_promotion"),
              let driverRecheck = promotionTerminal.range(of: "sdk_driver_authority_lost_during_auth_promotion", range: sourceRecheck.upperBound..<promotionTerminal.endIndex),
              let chronologyCatch = promotionTerminal.range(of: "catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed", range: driverRecheck.upperBound..<promotionTerminal.endIndex),
              let genericCatch = promotionTerminal.range(of: "} catch {", range: chronologyCatch.upperBound..<promotionTerminal.endIndex) else {
            Issue.record("Could not isolate post-suspension authority rechecks from ledger chronology retirement.")
            return
        }
        #expect(sourceRecheck.lowerBound < driverRecheck.lowerBound)
        #expect(driverRecheck.lowerBound < chronologyCatch.lowerBound)

        let chronologyTerminal = promotionTerminal[chronologyCatch.lowerBound..<genericCatch.lowerBound]
        #expect(chronologyTerminal.contains("invalidateInternalLifecycle"))
        #expect(chronologyTerminal.contains("session_auth_promotion_clock_regressed"))
        #expect(!chronologyTerminal.contains("invalidateSourceAuthority"))

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
