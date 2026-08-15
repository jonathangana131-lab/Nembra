import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya signed Apple application identity custody source contract")
struct TuyaSignedAppleAppIdentityCustodySourceTests {
    @Test("field installer preserves App ID prefix while proving exact bundle and selected team")
    func prefixSafeSignedApplicationIdentityIsProvenBeforeInstall() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(!installer.contains("EXPECTED_APPLICATION_IDENTIFIER=\"${TEAM_ID}.${BUNDLE_ID}\""))
        #expect(installer.contains("APP_ID_SUFFIX=\".${BUNDLE_ID}\""))
        #expect(installer.contains("[[ \"$BUILT_APPLICATION_IDENTIFIER\" == *\"$APP_ID_SUFFIX\" ]]"))
        #expect(installer.contains("[[ \"$BUILT_APPLICATION_IDENTIFIER\" != *\"*\"* ]]"))
        #expect(installer.contains("BUILT_APP_ID_PREFIX=\"${BUILT_APPLICATION_IDENTIFIER%$APP_ID_SUFFIX}\""))
        #expect(installer.contains("[[ -n \"$BUILT_APP_ID_PREFIX\" && \"$BUILT_APP_ID_PREFIX\" != \"$BUILT_APPLICATION_IDENTIFIER\" ]]"))
        #expect(installer.contains("[[ \"$BUILT_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]"))
        #expect(installer.contains("[[ \"$PROFILE_APPLICATION_IDENTIFIER\" == \"$BUILT_APPLICATION_IDENTIFIER\" ]]"))
        #expect(installer.contains("[[ \"$PROFILE_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]"))
        #expect(installer.contains("[[ \"$PROFILE_ROOT_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]"))
        #expect(installer.contains("application-identifier"))
        #expect(installer.contains("com.apple.developer.team-identifier"))
        #expect(installer.contains("TeamIdentifier"))

        let installMarker = try #require(installer.range(of: "say \"Installing SDK-integrated Capture on the intended iPhone through frozen selected-Xcode devicectl\""))
        for check in [
            "[[ \"$BUILT_APPLICATION_IDENTIFIER\" == *\"$APP_ID_SUFFIX\" ]]",
            "[[ \"$BUILT_APPLICATION_IDENTIFIER\" != *\"*\"* ]]",
            "[[ \"$BUILT_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]",
            "[[ \"$PROFILE_APPLICATION_IDENTIFIER\" == \"$BUILT_APPLICATION_IDENTIFIER\" ]]",
            "[[ \"$PROFILE_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]",
            "[[ \"$PROFILE_ROOT_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]"
        ] {
            let range = try #require(installer.range(of: check))
            #expect(range.lowerBound < installMarker.lowerBound, "signed Apple identity must be proven before installation: \(check)")
        }
        #expect(installer.contains("run_frozen_xcode_tool \"$SELECTED_DEVICECTL\" device install app"))
        #expect(!installer.contains("xcrun devicectl"))
    }

    @Test("profile identity is matched to signed app rather than synthesized from Team ID")
    func profileMatchesExactSignedApplicationIdentifier() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        #expect(installer.contains("sys.stdout.write(application + \"\\t\" + entitlement_team + \"\\t\" + team_identifiers[0])"))
        #expect(installer.contains("PROFILE_ROOT_TEAM_IDENTIFIER"))
        #expect(installer.contains("$PROFILE_APPLICATION_IDENTIFIER\" == \"$BUILT_APPLICATION_IDENTIFIER"))
        #expect(!installer.contains("$PROFILE_APPLICATION_IDENTIFIER\" == \"$TEAM_ID.$BUNDLE_ID"))
    }

    @Test("identity proof remains signing custody only")
    func identityProofCannotMintScooterAuthority() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let start = try #require(installer.range(of: "APP_ID_SUFFIX=\".${BUNDLE_ID}\""))
        let end = try #require(installer.range(of: "say \"Installing SDK-integrated Capture on the intended iPhone through frozen selected-Xcode devicectl\"", range: start.upperBound..<installer.endIndex))
        let custody = installer[start.lowerBound..<end.lowerBound]

        for forbidden in [
            "connectBLE",
            "publishDps",
            "queryDps",
            "writeValue",
            "scanForPeripherals",
            "NEMBRA_SIMULATION_"
        ] {
            #expect(!custody.contains(forbidden), "signed Apple identity custody must not introduce BLE/protocol/physical authority: \(forbidden)")
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