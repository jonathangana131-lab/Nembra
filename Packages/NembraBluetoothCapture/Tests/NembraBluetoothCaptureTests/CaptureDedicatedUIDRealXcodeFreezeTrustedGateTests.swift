import Foundation
import Testing

@Suite("Capture dedicated-UID real-Xcode validation bridge")
struct CaptureDedicatedUIDRealXcodeFreezeTrustedGateTests {
    @Test("trusted Xcode exact-head gate executes dedicated-UID APFS freeze oracle")
    func trustedGateExecutesDedicatedUIDFreezeOracle() throws {
        let environment = ProcessInfo.processInfo.environment

        // This is deliberately dormant in ordinary package/unit-test runs.
        // The repository's main-branch trusted /capture-xcode27 workflow is the
        // only existing exact-head macOS execution surface allowed to activate
        // this validation-only architecture probe.
        guard environment["GITHUB_ACTIONS"] == "true",
              environment["GITHUB_WORKFLOW"] == "Capture Trusted Xcode 27 Exact-Head QA",
              environment["RUNNER_OS"] == "macOS" else {
            return
        }

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let oracle = repositoryRoot
            .appendingPathComponent("scripts/ci/tests/test_capture_signed_app_real_xcode_dedicated_uid_freeze.py")

        #expect(
            FileManager.default.fileExists(atPath: oracle.path),
            "The exact-head trusted gate must carry the dedicated-UID validation oracle."
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-B", "-I", oracle.path]
        process.currentDirectoryURL = repositoryRoot
        var childEnvironment = environment
        childEnvironment["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = childEnvironment

        let combined = Pipe()
        process.standardOutput = combined
        process.standardError = combined

        try process.run()
        let retainedOutput = combined.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(decoding: retainedOutput, as: UTF8.self)
        print("NEMBRA_DEDICATED_UID_TRUSTED_GATE_OUTPUT_BEGIN")
        print(output)
        print("NEMBRA_DEDICATED_UID_TRUSTED_GATE_OUTPUT_END")

        if process.terminationStatus != 0 {
            Issue.record(
                "Dedicated-UID real-Xcode freeze oracle returned \(process.terminationStatus). Retained oracle output:\n\(output)"
            )
        }
        #expect(process.terminationStatus == 0)
        #expect(
            output.contains("NEMBRA_REAL_XCODE_DEDICATED_UID_JSON="),
            "A green trusted-gate run must retain the structured dedicated-UID success record."
        )
        #expect(
            !output.contains("NEMBRA_REAL_XCODE_DEDICATED_UID_ERROR="),
            "A green trusted-gate run must not carry a retained dedicated-UID red record."
        )
    }
}
