from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
STATUS_TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSecureLinkViewMembershipStatusRevocationSourceTests.swift"
PRECEDENCE_TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationEventMetadataPrecedenceSourceTests.swift"

STATUS_OLD = '''        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipRequestID = UUID()
'''
STATUS_NEW = '''        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = "Scooter membership must be verified again for this Secure Link session."
        membershipRequestID = UUID()
'''
MERGE_OLD = ''') { current, _ in current })'''
MERGE_NEW = ''') { _, trusted in trusted })'''

STATUS_TEST_CONTENT = r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Secure Link view-exit membership status revocation")
struct TuyaSecureLinkViewMembershipStatusRevocationSourceTests {
    @Test("view exit cannot retain verified membership copy after revoking the membership proof")
    func exitRevokesMembershipStatusWithProof() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let cleanup = String(try section(
            in: controller,
            from: "func abandonCorrelationForViewExit()",
            to: "var privateConfig: Bool"
        ))

        let clearVerified = try requiredOffset(containing: "sdkDeviceMembershipVerified = false", in: cleanup)
        let statusReset = try requiredOffset(containing: "membershipStatus =", in: cleanup)
        let revokeMembershipRequest = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)

        #expect(clearVerified < statusReset)
        #expect(statusReset < revokeMembershipRequest)
        #expect(!cleanup.contains("membershipStatus = \"Exact scooter membership verified and leased to this current SDK account.\""))
    }

    @Test("the recovery panel cannot pair revoked authority with stale verified copy")
    func revokedMembershipRendersReverificationCopy() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let cleanup = String(try section(
            in: controller,
            from: "func abandonCorrelationForViewExit()",
            to: "var privateConfig: Bool"
        ))

        #expect(cleanup.contains("membershipStatus ="))
        #expect(cleanup.lowercased().contains("verif"))
        #expect(!cleanup.lowercased().contains("membership verified and leased"))
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw SourceContractError.sectionMissing
        }
        return range.lowerBound
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
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

    private enum SourceContractError: Error { case sectionMissing }
}
'''

PRECEDENCE_TEST_CONTENT = r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application event metadata precedence")
struct TuyaApplicationEventMetadataPrecedenceSourceTests {
    @Test("SDK application keys cannot overwrite Nembra generation provenance")
    func trustedGenerationWinsReservedKeyCollision() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        #expect(receiver.contains("log(\"tuya_application_update\""))
        #expect(receiver.contains("\"generation\": String(token.diagnosticGeneration)"))
        #expect(!receiver.contains(") { current, _ in current })"))
        #expect(receiver.contains(") { _, trusted in trusted })"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
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

    private enum SourceContractError: Error { case sectionMissing }
}
'''


def apply() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    if source.count(STATUS_OLD) != 1 or STATUS_NEW in source:
        raise SystemExit("membership-status revocation anchor changed or already repaired")
    receiver_start = source.index("private func receivedApplicationUpdate(")
    receiver_end = source.index("private func startWatchdog", receiver_start)
    receiver = source[receiver_start:receiver_end]
    if receiver.count(MERGE_OLD) != 1 or MERGE_NEW in receiver:
        raise SystemExit("application-event precedence anchor changed or already repaired")

    source = source.replace(STATUS_OLD, STATUS_NEW, 1)
    before = source[:receiver_start]
    receiver = source[receiver_start:receiver_end].replace(MERGE_OLD, MERGE_NEW, 1)
    after = source[receiver_end:]
    ENTRYPOINT.write_text(before + receiver + after, encoding="utf-8")

    for path, content in ((STATUS_TEST, STATUS_TEST_CONTENT), (PRECEDENCE_TEST, PRECEDENCE_TEST_CONTENT)):
        if path.exists():
            raise SystemExit(f"regression already exists on current product: {path}")
        path.write_text(content, encoding="utf-8")


def verify() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    cleanup_start = source.index("func abandonCorrelationForViewExit()")
    cleanup_end = source.index("var privateConfig: Bool", cleanup_start)
    cleanup = source[cleanup_start:cleanup_end]
    order = [cleanup.index(x) for x in (
        "sdkDeviceMembershipVerified = false",
        'membershipStatus = "Scooter membership must be verified again for this Secure Link session."',
        "membershipRequestID = UUID()",
    )]
    if order != sorted(order):
        raise SystemExit("membership proof/status/request revocation ordering is wrong")

    receiver_start = source.index("private func receivedApplicationUpdate(")
    receiver_end = source.index("private func startWatchdog", receiver_start)
    receiver = source[receiver_start:receiver_end]
    if MERGE_NEW not in receiver or MERGE_OLD in receiver:
        raise SystemExit("Nembra generation does not have collision precedence")
    for path in (STATUS_TEST, PRECEDENCE_TEST):
        if not path.exists():
            raise SystemExit(f"missing regression {path}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
