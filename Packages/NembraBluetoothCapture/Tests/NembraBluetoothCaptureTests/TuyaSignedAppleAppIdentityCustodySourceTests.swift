import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya signed Apple application identity custody source contract")
struct TuyaSignedAppleAppIdentityCustodySourceTests {
    @Test("field installer proves the exact signed App ID and team before installation")
    func exactSignedApplicationIdentityIsProvenBeforeInstall() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        let required = [
            "BUILT_APPLICATION_IDENTIFIER",
            "BUILT_TEAM_IDENTIFIER",
            "PROFILE_APPLICATION_IDENTIFIER",
            "PROFILE_TEAM_IDENTIFIER",
            "PROFILE_ROOT_TEAM_IDENTIFIER",
            "application-identifier",
            "com.apple.developer.team-identifier",
            "TeamIdentifier",
            "[[ \"$BUILT_APPLICATION_IDENTIFIER\" == *\".$BUNDLE_ID\" ]]",
            "[[ \"$PROFILE_APPLICATION_IDENTIFIER\" == \"$BUILT_APPLICATION_IDENTIFIER\" ]]",
            "[[ \"$BUILT_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]",
            "[[ \"$PROFILE_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]",
            "[[ \"$PROFILE_ROOT_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]"
        ]
        for needle in required {
            #expect(installer.contains(needle), "missing signed Apple application-identity custody contract: \(needle)")
        }

        let installMarker = try #require(installer.range(of: "say \"Installing SDK-integrated Capture on the intended iPhone\""))
        for check in [
            "[[ \"$BUILT_APPLICATION_IDENTIFIER\" == *\".$BUNDLE_ID\" ]]",
            "[[ \"$PROFILE_APPLICATION_IDENTIFIER\" == \"$BUILT_APPLICATION_IDENTIFIER\" ]]",
            "[[ \"$BUILT_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]",
            "[[ \"$PROFILE_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]",
            "[[ \"$PROFILE_ROOT_TEAM_IDENTIFIER\" == \"$TEAM_ID\" ]]"
        ] {
            let range = try #require(installer.range(of: check))
            #expect(range.lowerBound < installMarker.lowerBound, "signed Apple identity must be proven before installation: \(check)")
        }

        // App ID prefixes are not guaranteed to equal the Team ID. Exact app/profile
        // agreement plus separate team checks is the authority rendezvous.
        #expect(!installer.contains("EXPECTED_APPLICATION_IDENTIFIER=\"${TEAM_ID}.${BUNDLE_ID}\""))
    }

    @Test("identity proof remains signing custody only")
    func identityProofCannotMintScooterAuthority() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let start = try #require(installer.range(of: "BUILT_APPLICATION_IDENTIFIER"))
        let end = try #require(installer.range(of: "say \"Installing SDK-integrated Capture on the intended iPhone\"", range: start.upperBound..<installer.endIndex))
        let custody = installer[start.lowerBound..<end.lowerBound]

        for forbidden in [
            "connectBLE",
            "publishDps",
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
