import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture physical procedure target authority")
struct TuyaPhysicalProcedureTargetAuthoritySourceTests {
    @Test("canonical and supporting field docs require fresh four-window target authority")
    func fieldDocsDoNotReintroduceHistoricalHintAuthority() throws {
        let canonicalPath = "docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md"
        let preflightPath = "docs/CAPTURE_C7D09A22_TUYA_AUTHENTICATED_PREFLIGHT.md"
        let qaPath = "docs/CAPTURE_C7D09A22_AUTHENTICATED_READONLY_QA.md"

        let canonical = try readRepositoryFile(canonicalPath)
        let preflight = try readRepositoryFile(preflightPath)
        let qa = try readRepositoryFile(qaPath)

        #expect(canonical.contains("OFF1 → ON1 → OFF2 → ON2"))
        #expect(canonical.contains("historical C7D09A22 UUID"))
        #expect(canonical.contains("There is no hint-based override"))

        for supporting in [preflight, qa] {
            #expect(supporting.contains("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md"))
            #expect(supporting.contains("OFF1 → ON1 → OFF2 → ON2"))
            #expect(supporting.contains("historical") || supporting.contains("Historical"))
            #expect(supporting.contains("non-authoritative") || supporting.contains("cannot authorize"))
        }

        let combined = [canonical, preflight, qa].joined(separator: "\n")
        #expect(!combined.contains("combined FD50 + Tuya-company evidence"))
        #expect(!combined.contains("prior physical CoreBluetooth evidence only to correlate"))
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
