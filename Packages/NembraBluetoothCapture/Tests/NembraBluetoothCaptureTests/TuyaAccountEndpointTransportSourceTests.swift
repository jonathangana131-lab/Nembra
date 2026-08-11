import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya account endpoint transport source contract")
struct TuyaAccountEndpointTransportSourceTests {
    @Test("server-selected account endpoint is HTTPS-only")
    func serverSelectedEndpointRequiresHTTPS() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        #expect(!bridge.contains("rawEndpoint.hasPrefix(\"http\")"))
        #expect(bridge.contains("endpointComponents.scheme?.lowercased() == \"https\""))
        #expect(bridge.contains("let endpointHost = endpointComponents.host"))
        #expect(bridge.contains("endpointComponents.user == nil"))
        #expect(bridge.contains("endpointComponents.password == nil"))
        #expect(bridge.contains("requestURL.scheme?.lowercased() == \"https\""))
        #expect(bridge.contains("delegate: HTTPSOnlyRedirectDelegate.shared"))
        #expect(bridge.contains("redirectURL.scheme?.lowercased() == \"https\""))
        #expect(bridge.contains("originalHost.caseInsensitiveCompare(redirectHost) == .orderedSame"))
        #expect(bridge.contains("responseHost.caseInsensitiveCompare(requestHost) == .orderedSame"))
    }

    @Test("private reader import suppresses Python bytecode")
    func installerPrivateReaderImportIsBytecodeFree() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        #expect(installer.contains("/usr/bin/python3 -B -I - \"$PRIVATE_DEVICE_RUNNER\""))
        #expect(!installer.contains("/usr/bin/python3 -I - \"$PRIVATE_DEVICE_RUNNER\""))
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
