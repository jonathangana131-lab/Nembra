import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture physical procedure target authority")
struct TuyaPhysicalProcedureTargetAuthoritySourceTests {
    @Test("the sole canonical field procedure requires fresh four-window target authority")
    func canonicalFieldProcedureDoesNotReintroduceHistoricalHintAuthority() throws {
        let canonicalPath = "docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md"
        let canonical = try readRepositoryFile(canonicalPath)

        #expect(canonical.contains("OFF1 → ON1 → OFF2 → ON2"))
        #expect(canonical.contains("historical C7D09A22 UUID"))
        #expect(canonical.contains("There is no hint-based override"))
        #expect(canonical.contains("Historical UUID/name/RSSI/FD50/Tuya hints remain non-authoritative."))
        #expect(canonical.contains("explicit operator confirmation"))
        #expect(!canonical.contains("combined FD50 + Tuya-company evidence"))
        #expect(!canonical.contains("prior physical CoreBluetooth evidence only to correlate"))
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
