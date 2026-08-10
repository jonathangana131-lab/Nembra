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

    @Test("duplicate success callbacks share one local-BLE settlement owner and auth rejection retires authority")
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

        guard let rejected = handler.range(of: "session_auth_callback_rejected") else {
            Issue.record("Authentication chronology rejection needs a terminal source-authority route.")
            return
        }
        let prefix = String(handler[..<rejected.lowerBound])
        #expect(prefix.contains("invalidateSourceAuthority"))
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
