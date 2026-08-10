import Foundation
import Testing

@Suite("Tuya process-lifetime BLE ownership fence")
struct TuyaProcessLifetimeOwnershipSourceTests {
    private static func captureSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("NembraApp")
                .appendingPathComponent("App")
                .appendingPathComponent("NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
    }

    @Test("official Tuya ownership permanently closes package discovery across controller instances")
    func processLifetimeOwnershipIsFailClosed() throws {
        let source = try Self.captureSource()

        #expect(source.contains("private static var officialTuyaOwnershipStarted = false"))
        #expect(!source.contains("private var officialTuyaOwnershipStarted = false"))
        #expect(source.components(separatedBy: "guard !Self.officialTuyaOwnershipStarted else {").count - 1 >= 3)
        #expect(source.contains("package_discovery_blocked_after_tuya_ownership"))
        #expect(source.contains("discovery_reset_blocked_after_tuya_ownership"))

        let latch = try #require(source.range(of: "Self.officialTuyaOwnershipStarted = true")?.lowerBound)
        let connect = try #require(source.range(of: "newDriver.connect(")?.lowerBound)
        #expect(latch < connect)
    }

    @Test("discovery reset cannot clear process-wide official Tuya ownership")
    func resetCannotClearOwnershipLatch() throws {
        let source = try Self.captureSource()
        let start = try #require(source.range(of: "private func resetDiscovery()")?.lowerBound)
        let end = try #require(
            source.range(of: "private func fail(", range: start..<source.endIndex)?.lowerBound
        )
        let reset = source[start..<end]

        #expect(reset.contains("guard !Self.officialTuyaOwnershipStarted else"))
        #expect(!reset.contains("Self.officialTuyaOwnershipStarted = false"))
        #expect(!reset.contains("officialTuyaOwnershipStarted = false"))
    }

    @Test("authenticated Capture entrypoint remains observation-only")
    func authenticatedPathHasNoCommandAuthority() throws {
        let source = try Self.captureSource()

        for forbidden in [
            ".writeValue(",
            "publishDps",
            "queryDps",
            "resetFactory",
            "removeDevice(",
            "unbindDevice("
        ] {
            #expect(!source.contains(forbidden))
        }

        #expect(source.contains("connectBLE("))
        #expect(source.contains("dpsUpdate"))
        #expect(source.contains("45 seconds"))
    }
}
