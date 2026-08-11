import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture private Tuya identity provisioner custody")
struct TuyaPrivateIdentityProvisionerCustodyTests {
    @Test("provisioner rejects a symlinked runtime destination before writing credential material")
    func symlinkedRuntimeDestinationFailsClosed() throws {
        let fileManager = FileManager.default
        let fixtureRoot = fileManager.temporaryDirectory
            .appendingPathComponent("nembra-tuya-provisioner-\(UUID().uuidString)", isDirectory: true)
        let outside = fixtureRoot.appendingPathComponent("outside", isDirectory: true)
        let runtimeLink = fixtureRoot.appendingPathComponent("runtime", isDirectory: true)
        defer { try? fileManager.removeItem(at: fixtureRoot) }

        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: runtimeLink, withDestinationURL: outside)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [repositoryURL("Scripts/provision_capture_tuya_identity.sh").path]
        var environment = ProcessInfo.processInfo.environment
        environment["NEMBRA_TUYA_RUNTIME_DIR"] = runtimeLink.path
        process.environment = environment

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        try process.run()
        input.fileHandleForWriting.write(Data("dummy-app-key\ndummy-app-secret\n".utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        #expect(process.terminationStatus != 0)
        #expect(!fileManager.fileExists(atPath: outside.appendingPathComponent("NembraTuyaPrivateConfig.podspec").path))
        #expect(!fileManager.fileExists(atPath: outside.appendingPathComponent("Sources/NembraTuyaPrivateConfig/NembraTuyaPrivateIdentity.swift").path))
    }

    @Test("provisioner source admits only a fresh non-symlink runtime directory")
    func sourceContractRejectsDestinationReuseAndSymlinkComponents() throws {
        let provisioner = try String(
            contentsOf: repositoryURL("Scripts/provision_capture_tuya_identity.sh"),
            encoding: .utf8
        )

        #expect(provisioner.contains("assert_no_symlink_components"))
        #expect(provisioner.contains("Refusing to reuse or follow an existing Tuya runtime destination"))
        #expect(provisioner.contains("mkdir \"$DEST\""))
        #expect(!provisioner.contains("mkdir -p \"$SOURCE_DIR\""))
    }

    private func repositoryURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
    }
}
