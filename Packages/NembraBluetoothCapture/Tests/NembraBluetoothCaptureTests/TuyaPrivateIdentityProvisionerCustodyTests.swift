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

        let result = try runProvisioner(destination: runtimeLink)
        #expect(result.status != 0)
        #expect(!fileManager.fileExists(atPath: outside.appendingPathComponent("NembraTuyaPrivateConfig.podspec").path))
        #expect(!fileManager.fileExists(atPath: outside.appendingPathComponent("Sources/NembraTuyaPrivateConfig/NembraTuyaPrivateIdentity.swift").path))
    }

    @Test("provisioner writes a fresh private runtime once and refuses overwrite")
    func freshRuntimeIsModeRestrictedAndCannotBeReused() throws {
        let fileManager = FileManager.default
        let fixtureRoot = fileManager.temporaryDirectory
            .appendingPathComponent("nembra-tuya-provisioner-\(UUID().uuidString)", isDirectory: true)
        let destination = fixtureRoot.appendingPathComponent("runtime", isDirectory: true)
        defer { try? fileManager.removeItem(at: fixtureRoot) }
        try fileManager.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)

        let first = try runProvisioner(destination: destination)
        #expect(first.status == 0)

        let podspec = destination.appendingPathComponent("NembraTuyaPrivateConfig.podspec")
        let identity = destination.appendingPathComponent("Sources/NembraTuyaPrivateConfig/NembraTuyaPrivateIdentity.swift")
        #expect(fileManager.fileExists(atPath: podspec.path))
        #expect(fileManager.fileExists(atPath: identity.path))

        let podspecMode = try fileManager.attributesOfItem(atPath: podspec.path)[.posixPermissions] as? NSNumber
        let identityMode = try fileManager.attributesOfItem(atPath: identity.path)[.posixPermissions] as? NSNumber
        #expect(podspecMode?.intValue == 0o600)
        #expect(identityMode?.intValue == 0o600)

        let identityText = try String(contentsOf: identity, encoding: .utf8)
        #expect(!identityText.contains("dummy-app-secret"))

        let second = try runProvisioner(destination: destination)
        #expect(second.status != 0)
    }

    @Test("provisioner delegates writes to descriptor-bound no-follow helper")
    func sourceContractUsesDescriptorBoundWriter() throws {
        let provisioner = try String(
            contentsOf: repositoryURL("Scripts/provision_capture_tuya_identity.sh"),
            encoding: .utf8
        )
        let writer = try String(
            contentsOf: repositoryURL("Scripts/provision_capture_tuya_identity_writer.py"),
            encoding: .utf8
        )

        #expect(provisioner.contains("provision_capture_tuya_identity_writer.py"))
        #expect(provisioner.contains("/usr/bin/python3 -I \"$WRITER\" \"$DEST\""))
        #expect(!provisioner.contains("cat > \"$DEST/NembraTuyaPrivateConfig.podspec\""))
        #expect(!provisioner.contains("mkdir -p \"$SOURCE_DIR\""))
        #expect(writer.contains("O_NOFOLLOW"))
        #expect(writer.contains("O_DIRECTORY"))
        #expect(writer.contains("dir_fd=parent_fd"))
        #expect(writer.contains("O_EXCL"))
        #expect(writer.contains("Refusing to reuse or follow an existing Tuya runtime destination"))
    }

    private func runProvisioner(destination: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [repositoryURL("Scripts/provision_capture_tuya_identity.sh").path]
        var environment = ProcessInfo.processInfo.environment
        environment["NEMBRA_TUYA_RUNTIME_DIR"] = destination.path
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
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(decoding: outputData, as: UTF8.self))
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
