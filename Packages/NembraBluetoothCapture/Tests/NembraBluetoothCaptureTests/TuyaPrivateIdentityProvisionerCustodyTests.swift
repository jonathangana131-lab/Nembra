import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Tuya private identity provisioner custody")
struct TuyaPrivateIdentityProvisionerCustodyTests {
    private let appKey = "nembra-dummy-app-key"
    private let appSecret = "nembra-dummy-app-secret"

    @Test("credentials stay under checkout LocalSecrets and out of xtrace")
    func fixedDestinationAndTraceRedaction() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root.deletingLastPathComponent()) }
        let redirected = fixture.root.deletingLastPathComponent().appendingPathComponent("caller-controlled-runtime")

        let result = try invoke(
            fixture.script,
            xtrace: true,
            environment: ["NEMBRA_TUYA_RUNTIME_DIR": redirected.path]
        )
        #expect(result.status == 0)
        #expect(!result.output.contains(appKey))
        #expect(!result.output.contains(appSecret))
        #expect(!FileManager.default.fileExists(atPath: redirected.path))

        let runtime = fixture.root.appendingPathComponent("LocalSecrets/TuyaRuntime")
        let podspec = runtime.appendingPathComponent("NembraTuyaPrivateConfig.podspec")
        let identity = runtime.appendingPathComponent("Sources/NembraTuyaPrivateConfig/NembraTuyaPrivateIdentity.swift")
        #expect(FileManager.default.fileExists(atPath: podspec.path))
        #expect(FileManager.default.fileExists(atPath: identity.path))
        #expect(try posixPermissions(fixture.root.appendingPathComponent("LocalSecrets")) == 0o700)
        #expect(try posixPermissions(runtime) == 0o700)
        #expect(try posixPermissions(podspec) == 0o600)
        #expect(try posixPermissions(identity) == 0o600)

        let generated = try String(contentsOf: podspec, encoding: .utf8)
            + String(contentsOf: identity, encoding: .utf8)
        #expect(!generated.contains(appKey))
        #expect(!generated.contains(appSecret))
        #expect(generated.contains(Data(appKey.utf8).base64EncodedString()))
        #expect(generated.contains(Data(appSecret.utf8).base64EncodedString()))
    }

    @Test("direct invocation ignores hostile Bash startup and caller PATH")
    func directInvocationClosesStartupEnvironment() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root.deletingLastPathComponent()) }
        let source = try String(contentsOf: fixture.script, encoding: .utf8)
        #expect(source.hasPrefix("#!/bin/bash -p\n"))
        #expect(source.contains("if [[ $- != *p* ]]"))

        let sandbox = fixture.root.deletingLastPathComponent()
        let sentinel = sandbox.appendingPathComponent("startup-sentinel")
        let bashEnvironment = sandbox.appendingPathComponent("hostile-bash-env")
        try Data("/bin/echo hostile-startup > \(sentinel.path)\n".utf8).write(to: bashEnvironment)
        let hostilePath = sandbox.appendingPathComponent("hostile-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: hostilePath, withIntermediateDirectories: true)

        let result = try invokeDirect(
            fixture.script,
            environment: [
                "BASH_ENV": bashEnvironment.path,
                "PATH": hostilePath.path,
            ]
        )
        #expect(result.status == 0)
        #expect(!result.output.contains(appKey))
        #expect(!result.output.contains(appSecret))
        #expect(!FileManager.default.fileExists(atPath: sentinel.path))
    }

    @Test("checkout root derivation ignores caller PATH executables")
    func checkoutRootDerivationIgnoresCallerPathExecutables() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root.deletingLastPathComponent()) }
        let source = try String(contentsOf: fixture.script, encoding: .utf8)
        let pathFence = source.range(of: "PATH=\"/usr/bin:/bin:/usr/sbin:/sbin\"")
        let trustedRoot = source.range(of: "ROOT=\"$(cd \"$(/usr/bin/dirname")
        #expect(pathFence != nil)
        #expect(trustedRoot != nil)
        if let pathFence, let trustedRoot {
            #expect(pathFence.lowerBound < trustedRoot.lowerBound)
        }

        let sandbox = fixture.root.deletingLastPathComponent()
        let hostilePath = sandbox.appendingPathComponent("hostile-root-bin", isDirectory: true)
        let attackerRoot = sandbox.appendingPathComponent("attacker-root", isDirectory: true)
        let attackerScripts = attackerRoot.appendingPathComponent("Scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: hostilePath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: attackerScripts, withIntermediateDirectories: true)
        let sentinel = sandbox.appendingPathComponent("hostile-dirname-invoked")
        let hostileDirname = hostilePath.appendingPathComponent("dirname")
        let fake = "#!/bin/sh\n/bin/echo invoked > \"\(sentinel.path)\"\n/bin/echo \"\(attackerScripts.path)\"\n"
        try Data(fake.utf8).write(to: hostileDirname)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hostileDirname.path)

        let result = try invokeDirect(fixture.script, environment: ["PATH": hostilePath.path])
        #expect(result.status == 0)
        #expect(!FileManager.default.fileExists(atPath: sentinel.path))
        #expect(!FileManager.default.fileExists(atPath: attackerRoot.appendingPathComponent("LocalSecrets/TuyaRuntime").path))
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("LocalSecrets/TuyaRuntime/NembraTuyaPrivateConfig.podspec").path))
    }

    @Test("writer bytes are digest pinned before credential input")
    func tamperedWriterNeverExecutesOnCredentialStream() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root.deletingLastPathComponent()) }
        let writer = fixture.root.appendingPathComponent("Scripts/provision_capture_tuya_identity_writer.py")
        let sentinel = fixture.root.deletingLastPathComponent().appendingPathComponent("tampered-writer-executed")
        let malicious = "import os\nopen(os.environ['NEMBRA_WRITER_SENTINEL'], 'w').write('executed')\n"
        try Data(malicious.utf8).write(to: writer)

        let result = try invoke(
            fixture.script,
            environment: ["NEMBRA_WRITER_SENTINEL": sentinel.path]
        )
        #expect(result.status != 0)
        #expect(result.output.contains("writer bytes do not match the accepted digest"))
        #expect(!FileManager.default.fileExists(atPath: sentinel.path))
    }

    @Test("symlinked LocalSecrets fails before credential publication")
    func symlinkedLocalSecretsFailsClosed() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root.deletingLastPathComponent()) }
        let escape = fixture.root.deletingLastPathComponent().appendingPathComponent("escape")
        try FileManager.default.createDirectory(at: escape, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appendingPathComponent("LocalSecrets"),
            withDestinationURL: escape
        )

        let result = try invoke(fixture.script)
        #expect(result.status != 0)
        #expect(!FileManager.default.fileExists(atPath: escape.appendingPathComponent("TuyaRuntime").path))
    }

    @Test("symlinked final identity output cannot receive credentials")
    func symlinkedOutputFailsClosed() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root.deletingLastPathComponent()) }
        let sourceDirectory = fixture.root.appendingPathComponent("LocalSecrets/TuyaRuntime/Sources/NembraTuyaPrivateConfig")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let sentinel = fixture.root.deletingLastPathComponent().appendingPathComponent("sentinel.txt")
        try Data("unchanged".utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(
            at: sourceDirectory.appendingPathComponent("NembraTuyaPrivateIdentity.swift"),
            withDestinationURL: sentinel
        )

        let result = try invoke(fixture.script)
        #expect(result.status != 0)
        #expect(try String(contentsOf: sentinel, encoding: .utf8) == "unchanged")
    }

    @Test("regular private outputs can be reprovisioned")
    func regularOutputsCanBeReprovisioned() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root.deletingLastPathComponent()) }

        let first = try invoke(fixture.script)
        #expect(first.status == 0)
        let second = try invoke(fixture.script)
        #expect(second.status == 0)

        let runtime = fixture.root.appendingPathComponent("LocalSecrets/TuyaRuntime")
        #expect(try posixPermissions(runtime.appendingPathComponent("NembraTuyaPrivateConfig.podspec")) == 0o600)
        #expect(try posixPermissions(runtime.appendingPathComponent("Sources/NembraTuyaPrivateConfig/NembraTuyaPrivateIdentity.swift")) == 0o600)
    }

    @Test("publication and writer execution are pinned before secrets")
    func descriptorBoundPublicationSourceContract() throws {
        let shell = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scripts/provision_capture_tuya_identity.sh"),
            encoding: .utf8
        )
        let writer = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scripts/provision_capture_tuya_identity_writer.py"),
            encoding: .utf8
        )

        #expect(shell.contains("WRITER_SHA256=\"b697044a4de0cf1afcd40bc68722bbf4c316e59c6258cfd4de0497d3b4145276\""))
        #expect(shell.contains("WRITER_CAPTURE=\"$({ /bin/cat -- \"$WRITER\"; builtin printf '\\001'; })\""))
        #expect(shell.contains("/usr/bin/shasum -a 256"))
        #expect(shell.contains("/usr/bin/python3 -I -c \"$WRITER_SOURCE\" \"$ROOT_FD\" \"$ROOT\""))
        #expect(!shell.contains("/usr/bin/python3 -I \"$WRITER\""))
        let digestFence = shell.range(of: "[[ \"$CAPTURED_WRITER_SHA256\" == \"$WRITER_SHA256\" ]]")
        let credentialRead = shell.range(of: "builtin read -r -s -p \"Tuya SmartLife SDK AppKey (input hidden): \" APP_KEY")
        #expect(digestFence != nil)
        #expect(credentialRead != nil)
        if let digestFence, let credentialRead {
            #expect(digestFence.lowerBound < credentialRead.lowerBound)
        }

        #expect(!shell.contains("/usr/bin/mktemp"))
        #expect(!shell.contains("/bin/mv -f"))
        #expect(writer.contains("O_NOFOLLOW"))
        #expect(writer.contains("O_DIRECTORY"))
        #expect(writer.contains("O_EXCL"))
        #expect(writer.contains("_require_descriptor_payload"))
        #expect(writer.contains("_unlink_owned_relative_inode_if_named"))
        #expect(writer.contains("hashlib.sha256"))
        #expect(writer.contains("dir_fd=checkout_fd"))
        #expect(writer.contains("src_dir_fd=checkout_fd"))
        #expect(writer.contains("dst_dir_fd=checkout_fd"))
    }

    private func makeFixture() throws -> (root: URL, script: URL) {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("nembra-tuya-provisioner-\(UUID().uuidString)", isDirectory: true)
        let root = sandbox.appendingPathComponent("repo", isDirectory: true)
        let scripts = root.appendingPathComponent("Scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)

        let sourceScript = repositoryRoot.appendingPathComponent("Scripts/provision_capture_tuya_identity.sh")
        let targetScript = scripts.appendingPathComponent("provision_capture_tuya_identity.sh")
        try FileManager.default.copyItem(at: sourceScript, to: targetScript)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: targetScript.path)

        let sourceWriter = repositoryRoot.appendingPathComponent("Scripts/provision_capture_tuya_identity_writer.py")
        let targetWriter = scripts.appendingPathComponent("provision_capture_tuya_identity_writer.py")
        try FileManager.default.copyItem(at: sourceWriter, to: targetWriter)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: targetWriter.path)
        return (root, targetScript)
    }

    private func invoke(
        _ script: URL,
        xtrace: Bool = false,
        environment additions: [String: String] = [:]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = (xtrace ? ["-px"] : ["-p"]) + [script.path]
        return try run(process, environment: additions)
    }

    private func invokeDirect(
        _ script: URL,
        environment additions: [String: String] = [:]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = script
        return try run(process, environment: additions)
    }

    private func run(
        _ process: Process,
        environment additions: [String: String]
    ) throws -> (status: Int32, output: String) {
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in additions { environment[key] = value }
        process.environment = environment

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        try process.run()
        input.fileHandleForWriting.write(Data("\(appKey)\n\(appSecret)\n".utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(decoding: outputData, as: UTF8.self))
    }

    private func posixPermissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let permissions = attributes[.posixPermissions] as? NSNumber else {
            throw TestFailure.missingPermissions
        }
        return permissions.intValue
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private enum TestFailure: Error {
        case missingPermissions
    }
}
