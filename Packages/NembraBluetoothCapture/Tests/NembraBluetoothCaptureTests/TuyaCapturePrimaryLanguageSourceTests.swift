import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture primary rider language")
struct TuyaCapturePrimaryLanguageSourceTests {
    @Test("primary Capture flow stays rider-first while Engineering Details retains exact protocol truth")
    func primaryLanguageBoundary() throws {
        let app = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        let primaryStart = try #require(app.range(of: "private var preflightPanel"))
        let detailsStart = try #require(
            app.range(
                of: "private var engineeringDisclosure",
                range: primaryStart.upperBound..<app.endIndex
            )
        )
        let primary = String(app[primaryStart.lowerBound..<detailsStart.lowerBound])
        let details = String(app[detailsStart.lowerBound...])

        for forbidden in [
            "Historical UUID",
            "RSSI",
            "FD50",
            "DP query",
            "package-owned scan window",
            "passive Bluetooth correlation",
            "accepted observation horizon",
            "required field authority",
            "prior session generation",
        ] {
            #expect(!primary.contains(forbidden))
        }

        for required in [
            "OFF → ON → OFF → ON signal pattern",
            "read-only signal check",
            "cannot send scooter commands",
            "Read-only observation",
            "This stopped attempt will not be reused",
        ] {
            #expect(primary.contains(required))
        }

        #expect(details.contains("raw FD50 bytes"))
        #expect(details.contains("No DP query or scooter command"))
    }

    @Test("rider copy does not weaken correlation or relaunch authority")
    func languagePolishPreservesTruthGuards() throws {
        let app = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("test.phase == .correlated ? 4 : min(test.correlationCompletedWindowCount + 1, 4)"))
        #expect(app.contains("test.canRestartFromFreshOFF1 && (!sdkAccount.loggedIn || !test.sdkAccountLoggedIn)"))
        #expect(app.contains("test.canRestartFromFreshOFF1 && test.sdkAccountLoggedIn && (!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized)"))
        #expect(app.contains("No DP query or scooter command"))
    }

    private func read(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
