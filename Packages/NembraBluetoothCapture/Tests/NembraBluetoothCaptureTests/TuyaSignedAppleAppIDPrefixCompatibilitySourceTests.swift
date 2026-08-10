import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya signed Apple App ID prefix compatibility")
struct TuyaSignedAppleAppIDPrefixCompatibilitySourceTests {
    @Test("field installer accepts a legitimate distinct App ID prefix without weakening team custody")
    func appIDPrefixIsNotInventedFromTeamID() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        // Apple application-identifier is <App ID prefix>.<bundle ID>. The App ID
        // prefix is not guaranteed to equal the Team ID for legacy/distinct App IDs.
        #expect(!installer.contains("EXPECTED_APPLICATION_IDENTIFIER=\"${TEAM_ID}.${BUNDLE_ID}\""))
        #expect(!installer.contains("[[ \"$BUILT_APPLICATION_IDENTIFIER\" == \"$EXPECTED_APPLICATION_IDENTIFIER\" ]]"))
        #expect(!installer.contains("[[ \"$PROFILE_APPLICATION_IDENTIFIER\" == \"$EXPECTED_APPLICATION_IDENTIFIER\" ]]"))

        // Prove the signed app is for this exact bundle while preserving the real
        // prefix chosen by signing, then require the embedded profile to match it.
        #expect(installer.contains("[[ \"$BUILT_APPLICATION_IDENTIFIER\" == *\".$BUNDLE_ID\" ]]"))
        #expect(installer.contains("[[ \"$PROFILE_APPLICATION_IDENTIFIER\" == \"$BUILT_APPLICATION_IDENTIFIER\" ]]"))

        // Team custody remains exact and independent of the App ID prefix.
        #expect(installer.contains("[[ \"$BUILT_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]"))
        #expect(installer.contains("[[ \"$PROFILE_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]"))
        #expect(installer.contains("TeamIdentifier"))

        let installMarker = try #require(installer.range(of: "say \"Installing SDK-integrated Capture on the intended iPhone\""))
        for check in [
            "[[ \"$BUILT_APPLICATION_IDENTIFIER\" == *\".$BUNDLE_ID\" ]]",
            "[[ \"$PROFILE_APPLICATION_IDENTIFIER\" == \"$BUILT_APPLICATION_IDENTIFIER\" ]]",
            "[[ \"$BUILT_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]",
            "[[ \"$PROFILE_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]"
        ] {
            let range = try #require(installer.range(of: check))
            #expect(range.lowerBound < installMarker.lowerBound, "signed Apple identity must be proven before installation: \(check)")
        }
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
