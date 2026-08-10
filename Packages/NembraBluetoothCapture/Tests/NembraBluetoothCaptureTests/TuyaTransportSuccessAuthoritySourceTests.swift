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
        #expect(handler.contains("session_auth_promotion_clock_regressed"))
        #expect(handler.contains("session_auth_promotion_rejected"))

        guard let promotion = handler.range(of: "sessionLedger.markAuthenticated"),
              let resumedSourceTerminal = handler.range(
                of: "sdk_source_authority_lost_during_auth_promotion",
                range: promotion.upperBound..<handler.endIndex
              ),
              let resumedDriverTerminal = handler.range(
                of: "sdk_driver_authority_lost_during_auth_promotion",
                range: resumedSourceTerminal.upperBound..<handler.endIndex
              ),
              let observing = handler.range(
                of: "phase = .observing",
                range: resumedDriverTerminal.upperBound..<handler.endIndex
              ),
              let clockCatch = handler.range(
                of: "} catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {",
                range: observing.upperBound..<handler.endIndex
              ),
              let genericCatch = handler.range(
                of: "} catch {",
                range: clockCatch.upperBound..<handler.endIndex
              ),
              let keepWaiting = handler.range(
                of: "case .keepWaiting:",
                range: genericCatch.upperBound..<handler.endIndex
              ) else {
            Issue.record("Could not isolate authentication-promotion revalidation and ledger-failure cleanup.")
            return
        }

        // Ledger actor hops can interleave foreground/account teardown. Revalidate source/driver
        // authority after the mutation and before repainting the generation as observing.
        #expect(promotion.lowerBound < resumedSourceTerminal.lowerBound)
        #expect(resumedSourceTerminal.lowerBound < resumedDriverTerminal.lowerBound)
        #expect(resumedDriverTerminal.lowerBound < observing.lowerBound)

        // A ledger-owned chronology/invariant failure is a different terminal class: it must use
        // the exact-token internal lifecycle retirement rather than pretending source drift or
        // transport acquisition failure. Source-authority revalidation above remains legitimate.
        let clockTerminal = String(handler[clockCatch.lowerBound..<genericCatch.lowerBound])
        #expect(clockTerminal.contains("invalidateInternalLifecycle"))
        #expect(clockTerminal.contains("session_auth_promotion_clock_regressed"))
        #expect(!clockTerminal.contains("invalidateSourceAuthority"))
        #expect(!clockTerminal.contains("authenticationAcquisitionFailed"))
        #expect(!clockTerminal.contains("markAuthenticationFailed"))

        let genericTerminal = String(handler[genericCatch.lowerBound..<keepWaiting.lowerBound])
        #expect(genericTerminal.contains("invalidateInternalLifecycle"))
        #expect(genericTerminal.contains("session_auth_promotion_rejected"))
        #expect(!genericTerminal.contains("invalidateSourceAuthority"))
        #expect(!genericTerminal.contains("authenticationAcquisitionFailed"))
        #expect(!genericTerminal.contains("markAuthenticationFailed"))
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
