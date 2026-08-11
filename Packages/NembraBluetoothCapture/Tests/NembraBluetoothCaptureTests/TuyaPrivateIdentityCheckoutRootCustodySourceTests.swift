import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture private Tuya checkout-root custody")
struct TuyaPrivateIdentityCheckoutRootCustodySourceTests {
    @Test("checkout root is admitted before credentials and inherited by the pinned writer")
    func rootDescriptorPrecedesCredentialInput() throws {
        let shell = try readRepositoryFile("Scripts/provision_capture_tuya_identity.sh")
        let writer = try readRepositoryFile("Scripts/provision_capture_tuya_identity_writer.py")

        #expect(shell.contains("ROOT_FD=9"))
        #expect(shell.contains("exec 9<\"$ROOT\""))
        #expect(shell.contains("/usr/bin/python3 -I -c \"$WRITER_SOURCE\" \"$ROOT_FD\" \"$ROOT\""))
        #expect(!shell.contains("/usr/bin/python3 -I -c \"$WRITER_SOURCE\" \"$ROOT\""))

        let admission = shell.range(of: "exec 9<\"$ROOT\"")
        let digestFence = shell.range(of: "[[ \"$CAPTURED_WRITER_SHA256\" == \"$WRITER_SHA256\" ]]")
        let credentialRead = shell.range(of: "builtin read -r -s -p \"Tuya SmartLife SDK AppKey (input hidden): \" APP_KEY")
        #expect(admission != nil)
        #expect(digestFence != nil)
        #expect(credentialRead != nil)
        if let admission, let credentialRead {
            #expect(admission.lowerBound < credentialRead.lowerBound)
        }
        if let digestFence, let credentialRead {
            #expect(digestFence.lowerBound < credentialRead.lowerBound)
        }

        #expect(writer.contains("def _duplicate_inherited_checkout("))
        #expect(writer.contains("def _require_checkout_path_identity("))
        #expect(writer.contains("checkout_fd = _duplicate_inherited_checkout(sys.argv[1])"))
        #expect(writer.contains("podspec_sha256, identity_sha256 = provision("))
        #expect(writer.contains("checkout_fd, Path(sys.argv[2]), app_key_b64, app_secret_b64"))
        #expect(!writer.contains("checkout_fd = _open_absolute_directory(Path(sys.argv[2]))"))
        #expect(writer.contains("admitted.st_dev != current.st_dev"))
        #expect(writer.contains("admitted.st_ino != current.st_ino"))
        #expect(writer.contains("_ensure_private_directory(checkout_fd, \"LocalSecrets\")"))
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
