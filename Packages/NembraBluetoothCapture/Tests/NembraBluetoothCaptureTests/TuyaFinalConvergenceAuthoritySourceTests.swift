import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture final convergence authority")
struct TuyaFinalConvergenceAuthoritySourceTests {
    @Test("fresh correlation remains non-authorizing until explicit operator confirmation")
    func correlationRequiresExplicitConfirmation() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let finish = app.range(of: "private func finishCorrelationSeries"),
              let confirm = app.range(of: "func confirmCorrelatedCandidate", range: finish.upperBound..<app.endIndex),
              let invalidate = app.range(of: "func invalidateSDKMembership", range: confirm.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate correlation/confirmation boundaries.")
            return
        }
        let finishBody = String(app[finish.lowerBound..<confirm.lowerBound])
        let confirmBody = String(app[confirm.lowerBound..<invalidate.lowerBound])

        #expect(finishBody.contains("selectedID = nil"))
        #expect(finishBody.contains("phase = .correlated"))
        #expect(finishBody.contains("candidate_correlation_ready"))
        #expect(!finishBody.contains("selectedID = id"))
        #expect(!finishBody.contains("candidate_selected"))

        #expect(confirmBody.contains("phase == .correlated"))
        #expect(confirmBody.contains("candidate.freshlyCorrelated"))
        #expect(confirmBody.contains("selectedID = candidate.id"))
        #expect(confirmBody.contains("phase = .selected"))
        #expect(confirmBody.contains("candidate_confirmed"))
        #expect(app.contains("Confirm correlated Bluetooth target"))
    }

    @Test("current transport-success generation cannot strand or duplicate local-BLE settlement")
    func transportSuccessUsesTerminalSourceAuthorityAndOneSettlementOwner() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        guard let authenticated = app.range(of: "private func authenticated(token:"),
              let next = app.range(of: "private func authenticationFailed", range: authenticated.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate transport-success handler.")
            return
        }
        let handler = String(app[authenticated.lowerBound..<next.lowerBound])

        #expect(app.contains("private var localBLESettlementToken: TuyaReadOnlyConnectionToken?"))
        #expect(handler.contains("currentConnectionToken == token"))
        #expect(handler.contains("stale_connect_success_ignored"))
        #expect(handler.contains("localBLESettlementToken != token"))
        #expect(handler.contains("duplicate_connect_success_settlement_ignored"))
        #expect(handler.contains("sdk_source_authority_lost_before_local_ble_settlement"))
        #expect(handler.contains("sdk_driver_authority_lost_before_local_ble_settlement"))
        #expect(handler.contains("session_auth_callback_rejected"))
        #expect(handler.contains("invalidateSourceAuthority"))
        #expect(!handler.contains("sdkDeviceMembershipVerified,\n              accountIdentityLeaseIsAuthorized,\n              let driver else { return }"))
    }

    @Test("field-build authority is visible before OFF1 is actionable")
    func fieldBuildPresentationMatchesRuntimeAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }"))
        #expect(app.contains("LabeledContent(\"Field build\", value: test.fieldBuildIsAuthoritative"))
        #expect(app.contains("if !test.fieldBuildIsAuthoritative || !test.privateConfig"))
        #expect(app.contains(".disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig"))
        #expect(app.contains("guard buildIdentity.isAuthoritativeFieldBuild else"))
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
