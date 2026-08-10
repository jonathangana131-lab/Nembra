import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Tuya field-launch secret custody")
struct TuyaFieldLaunchSecretCustodySourceTests {
    @Test("private Tuya app credentials never enter devicectl argv")
    func launchDoesNotSerializePrivateCredentialsIntoArguments() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(
            !installer.contains("LAUNCH_ENV_JSON"),
            "Do not serialize AppKey/AppSecret into a command-line JSON value. Shell cleanup after launch cannot erase an argv exposure that already occurred."
        )
        #expect(
            !installer.contains("--environment-variables \"$LAUNCH_ENV_JSON\""),
            "The private Tuya app identity must not be passed as a literal devicectl argument. Use a private build/runtime provisioning boundary whose command line contains no secret value."
        )
    }

    @Test("installer cannot describe argv-injected build as an authenticated candidate")
    func fieldCandidateRequiresNonArgvPrivateProvisioning() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let leaksViaLaunchArguments = installer.contains("LAUNCH_ENV_JSON") ||
            installer.contains("--environment-variables \"$LAUNCH_ENV_JSON\"")

        if leaksViaLaunchArguments {
            #expect(
                !installer.contains("AUTHENTICATED CAPTURE CANDIDATE LAUNCHED"),
                "A launch that exposes AppKey/AppSecret through host process arguments is not an accepted private field candidate."
            )
        }
    }

    @Test("current installer stays fail closed until non-argv private provisioning exists")
    func repairedInstallerDoesNotOverclaimFieldReadiness() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("PHYSICAL NO-GO"))
        #expect(installer.contains("did NOT launch it with Tuya AppKey/AppSecret"))
        #expect(!installer.contains("AUTHENTICATED CAPTURE CANDIDATE LAUNCHED"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // NembraBluetoothCaptureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // NembraBluetoothCapture
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repository root

        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
