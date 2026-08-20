import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture runtime build identity transport")
struct CaptureRuntimeBuildIdentityTransportSourceTests {
    @Test("standalone Capture plist transports every package runtime identity input")
    func runtimeIdentityInputsUseExactBuildSettings() throws {
        let plist = try readRepositoryFile("NembraCapture-Info.plist")
        let runtimeReader = try readRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothCaptureRuntimeBuildIdentity.swift"
        )

        let mappings = [
            (
                key: "NembraCaptureBuildIdentifier",
                setting: "NEMBRA_CAPTURE_BUILD_IDENTIFIER",
                readerDeclaration: "buildIdentifierInfoDictionaryKey = \"NembraCaptureBuildIdentifier\""
            ),
            (
                key: "NembraCaptureBuildInstanceID",
                setting: "NEMBRA_CAPTURE_BUILD_INSTANCE_ID",
                readerDeclaration: "buildInstanceIDInfoDictionaryKey = \"NembraCaptureBuildInstanceID\""
            ),
            (
                key: "NembraCaptureBuildCommitSHA",
                setting: "NEMBRA_CAPTURE_BUILD_COMMIT_SHA",
                readerDeclaration: "sourceCommitSHAInfoDictionaryKey = \"NembraCaptureBuildCommitSHA\""
            ),
        ]

        for mapping in mappings {
            #expect(plist.contains("<key>\(mapping.key)</key>"))
            #expect(plist.contains("<string>$(\(mapping.setting))</string>"))
            #expect(runtimeReader.contains(mapping.readerDeclaration))
        }
    }

    @Test("legacy app provenance key stays compatible while package authority uses the stronger tuple")
    func legacySourceCommitCompatibilityIsPreserved() throws {
        let plist = try readRepositoryFile("NembraCapture-Info.plist")
        let appIdentity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")

        #expect(plist.contains("<key>NembraCaptureSourceCommitSHA</key>"))
        #expect(plist.contains("<string>$(NEMBRA_CAPTURE_BUILD_COMMIT_SHA)</string>"))
        #expect(appIdentity.contains("sourceCommitSHAInfoKey = \"NembraCaptureSourceCommitSHA\""))
        #expect(project.contains("INFOPLIST_EXPAND_BUILD_SETTINGS = YES;"))
    }

    @Test("build instance is an externally supplied rendezvous value, never a repository default")
    func buildInstanceHasNoRepositoryDefault() throws {
        let plist = try readRepositoryFile("NembraCapture-Info.plist")
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")

        #expect(
            plist.contains(
                "<key>NembraCaptureBuildInstanceID</key>\n\t<string>$(NEMBRA_CAPTURE_BUILD_INSTANCE_ID)</string>"
            )
        )
        #expect(!project.contains("NEMBRA_CAPTURE_BUILD_INSTANCE_ID ="))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
