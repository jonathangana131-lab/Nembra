#!/bin/bash
set -euo pipefail

EXPECTED_PRODUCT_PARENT="dc8f2472812b77ee609f89a228dc38195ba9edac"
BRANCH="repair/v14-capture-per-window-tuya-ownership-sol3"
ENTRYPOINT="NembraApp/App/NembraCaptureEntrypoint.swift"
TEST="Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCorrelationPerWindowBLEOwnershipSourceTests.swift"
WORKFLOW=".github/workflows/capture-per-window-ownership-materialize.yml"
SELF="scripts/ci/materialize_capture_per_window_ownership.sh"

actual_parent="$(git rev-parse HEAD^)"
[[ "$actual_parent" == "$EXPECTED_PRODUCT_PARENT" ]] || {
  echo "Refusing stale materialization: expected parent $EXPECTED_PRODUCT_PARENT, got $actual_parent" >&2
  exit 2
}
test -z "$(git status --porcelain=v1 --untracked-files=all)"

/usr/bin/python3 - <<'PY'
from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text(encoding="utf-8")
needle = '''        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
            failLocally("SDK account/device authority changed before the next correlation window.", "sdk_authority_changed_during_target_correlation")
            return
        }
        guard let session = correlationSession,
'''
replacement = '''        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
            failLocally("SDK account/device authority changed before the next correlation window.", "sdk_authority_changed_during_target_correlation")
            return
        }
        guard OfficialTuyaFactory.packageCorrelationMayStart else {
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
            failLocally(
                "Tuya BLE ownership was attempted elsewhere in this app process before the next correlation window. Relaunch Capture with the scooter OFF and restart from OFF1.",
                "process_tuya_ble_ownership_blocks_correlation_window"
            )
            return
        }
        guard !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) else {
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
            failLocally(
                "Tuya regained same-device local BLE before the next correlation window. Restart from OFF1 after that SDK session has cleared, or relaunch Capture.",
                "sdk_local_ble_ownership_blocks_correlation_window"
            )
            return
        }
        guard let session = correlationSession,
'''
if source.count(needle) != 1:
    raise SystemExit(f"expected exactly one current-window admission block, found {source.count(needle)}")
source = source.replace(needle, replacement, 1)
path.write_text(source, encoding="utf-8")
PY

cat > "$TEST" <<'SWIFT'
import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture per-window Tuya BLE ownership")
struct TuyaCorrelationPerWindowBLEOwnershipSourceTests {
    @Test("every fresh correlation window rechecks process retirement and global Tuya local-BLE ownership before package scan")
    func everyWindowRechecksGlobalOwnership() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let window = try section(
            in: app,
            from: "private func startCurrentCorrelationWindow()",
            to: "func finishCorrelationWindow()"
        )
        let body = String(window)

        guard let processFence = body.range(of: "guard OfficialTuyaFactory.packageCorrelationMayStart else"),
              let ownershipRead = body.range(of: "guard !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) else"),
              let scannerStart = body.range(of: "try session.startCurrentWindow()") else {
            Issue.record("Every OFF1/ON1/OFF2/ON2 scanner admission must recheck process retirement and same-device Tuya local-BLE ownership before scanning.")
            throw SourceContractError.sectionMissing
        }

        #expect(processFence.lowerBound < ownershipRead.lowerBound)
        #expect(ownershipRead.lowerBound < scannerStart.lowerBound)
        #expect(body[processFence.upperBound..<ownershipRead.lowerBound].contains("return"))
        #expect(body[ownershipRead.upperBound..<scannerStart.lowerBound].contains("return"))
        #expect(body.contains("process_tuya_ble_ownership_blocks_correlation_window"))
        #expect(body.contains("sdk_local_ble_ownership_blocks_correlation_window"))
    }

    @Test("the shared window-start path owns every OFF1 ON1 OFF2 ON2 scanner admission")
    func sharedWindowStartPathOwnsSeries() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let begin = try section(
            in: app,
            from: "private func beginCorrelationSeries()",
            to: "func finishCorrelationWindow()"
        )
        let body = String(begin)

        #expect(body.contains("startCurrentCorrelationWindow()"))
        #expect(body.contains("func startNextCorrelationWindow()"))
        #expect(body.contains("startCurrentCorrelationWindow()\n    }"))
    }

    @Test("per-window ownership fence remains observation-only and cannot mutate scooter state")
    func ownershipFenceIsReadOnly() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let window = try section(
            in: app,
            from: "private func startCurrentCorrelationWindow()",
            to: "func finishCorrelationWindow()"
        )
        let body = String(window)

        #expect(!body.contains("disconnectBLE"))
        #expect(!body.contains("publishDps"))
        #expect(!body.contains("queryDps"))
        #expect(!body.contains("writeValue"))
        #expect(!body.contains("sessionLedger.endConnection"))
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
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
SWIFT

/usr/bin/python3 - <<'PY'
from pathlib import Path
source = Path("NembraApp/App/NembraCaptureEntrypoint.swift").read_text(encoding="utf-8")
start = source.index("private func startCurrentCorrelationWindow()")
end = source.index("func finishCorrelationWindow()", start)
body = source[start:end]
process = body.index("guard OfficialTuyaFactory.packageCorrelationMayStart else")
local = body.index("guard !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) else")
scan = body.index("try session.startCurrentWindow()")
assert process < local < scan
for forbidden in ("disconnectBLE", "publishDps", "queryDps", "writeValue", "sessionLedger.endConnection"):
    assert forbidden not in body, forbidden
assert "process_tuya_ble_ownership_blocks_correlation_window" in body
assert "sdk_local_ble_ownership_blocks_correlation_window" in body
print("per-window BLE ownership source materialization: PASS")
PY

git diff --check
rm -f "$WORKFLOW" "$SELF"
git add "$ENTRYPOINT" "$TEST" "$WORKFLOW" "$SELF"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git commit -m "fix(capture): fence every correlation window from Tuya BLE ownership" -m "Recheck process retirement and same-device process-global Tuya local-BLE ownership before each OFF1/ON1/OFF2/ON2 package scanner start. Fail closed to fresh OFF1/relaunch with no disconnect, DP, write, or physical authority."
git push origin "HEAD:$BRANCH"
