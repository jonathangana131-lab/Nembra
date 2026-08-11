import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture private field-build custody")
struct TuyaFieldPrivateBuildCustodySourceTests {
    @Test("accepted source includes the hardened private intended-device reader")
    func privateDeviceReaderExistsAndFailsClosed() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let reader = try readRepositoryFile("scripts/ci/es80_signed_field_artifact_private_runner.py")

        #expect(installer.contains("PRIVATE_DEVICE_RUNNER=\"$ROOT/scripts/ci/es80_signed_field_artifact_private_runner.py\""))
        #expect(installer.contains("read_private_identifier"))
        #expect(reader.contains("def read_private_identifier(path: Path, repository_root: Path) -> str:"))
        #expect(reader.contains("os.O_NOFOLLOW"))
        #expect(reader.contains("metadata.st_mode & 0o077"))
        #expect(reader.contains("metadata.st_nlink != 1"))
        #expect(reader.contains("metadata.st_uid != os.geteuid()"))
        #expect(reader.contains("intended-device verification file must live outside the Nembra repository"))
        #expect(reader.contains("_stable_file_identity(final_metadata) != _stable_file_identity(metadata)"))
    }

    @Test("required private and CocoaPods field inputs do not make the accepted checkout dirty")
    func generatedFieldInputsAreExplicitlyIgnored() throws {
        let ignore = try readRepositoryFile(".gitignore")
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        for path in ["LocalSecrets/", "Pods/", "Podfile.lock", "NembraCapture.xcworkspace/"] {
            #expect(ignore.split(separator: "\n").contains(Substring(path)))
        }
        #expect(installer.contains("git status --porcelain=v1 --untracked-files=all"))
        #expect(installer.contains("Private workspace bootstrap changed tracked or unignored accepted-source inputs"))
        #expect(installer.contains("shasum -a 256 \"$ROOT/Podfile.lock\""))
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
