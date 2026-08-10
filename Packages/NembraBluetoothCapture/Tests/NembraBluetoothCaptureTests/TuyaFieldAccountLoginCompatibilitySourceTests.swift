import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field account login compatibility")
struct TuyaFieldAccountLoginCompatibilitySourceTests {
    @Test("field procedure fails closed when the scooter account is not reachable by an implemented SDK login method")
    func fieldProcedureRequiresReachableSameAccountAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        // Current product truth: the field authorizer implements verification-code
        // email/phone login only. A metadata QR link is not SDK account authority.
        #expect(app.contains("enum LoginMethod"))
        #expect(app.contains("case email = \"Email\""))
        #expect(app.contains("case phone = \"Phone\""))
        #expect(!app.contains("case apple"))
        #expect(!app.contains("loginByAuth2"))

        // The physical runbook must expose that compatibility boundary before OFF1
        // instead of letting a different Tuya account masquerade as the scooter account.
        #expect(runbook.contains("Current Capture field UI supports Tuya verification-code login by email or phone only."))
        #expect(runbook.contains("third-party-only"))
        #expect(runbook.contains("STOP before OFF1"))
        #expect(runbook.contains("same current SDK account UID"))
        #expect(runbook.contains("Do not create or switch to a different Tuya account to bypass this gate."))
        #expect(runbook.contains("exact expected scooter device ID"))
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
