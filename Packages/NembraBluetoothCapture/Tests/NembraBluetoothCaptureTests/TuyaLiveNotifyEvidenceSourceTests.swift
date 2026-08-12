import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya live notify evidence authority")
struct TuyaLiveNotifyEvidenceSourceTests {
    @Test("only the official device delegate callback can mint application evidence")
    func onlyDeviceDelegateCallbackMintsApplicationEvidence() throws {
        let entrypoint = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let accountBridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")

        let callbackMarker = "func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?)"
        let admissionMarker = "sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)"

        guard let callback = entrypoint.range(of: callbackMarker) else {
            Issue.record("The field app must receive application evidence from ThingSmartDeviceDelegate.dpsUpdate.")
            return
        }
        guard let admission = entrypoint.range(of: admissionMarker) else {
            Issue.record("The field app must pass a non-empty live SDK update into the authenticated session ledger.")
            return
        }

        #expect(callback.lowerBound < admission.lowerBound)
        #expect(entrypoint.occurrenceCount(of: admissionMarker) == 1)

        // Cloud metadata/status is useful for account/device authority, but it is not a live BLE
        // notification and must never satisfy the physical application-evidence gate.
        #expect(!accountBridge.contains("recordApplicationUpdate(isNonEmpty:"))

        // Tuya documents publishDps as its DP command/query transport. The P0 field app is strictly
        // passive after authenticated session establishment: neither controls nor DP queries are
        // allowed to enter either live authority source while physical semantics remain unknown.
        #expect(!entrypoint.contains("publishDps("))
        #expect(!accountBridge.contains("publishDps("))

        // Keep the evidence claim intentionally narrow: structured SDK application updates are
        // accepted as live notify evidence, but they are not represented as raw FD50 bytes.
        #expect(entrypoint.contains("ThingSmartDeviceDelegate dpsUpdate values projected with String(describing:)"))
        #expect(entrypoint.contains("rawFD50BytesCaptured: false"))
        #expect(entrypoint.contains("dpQueriesSent: false"))
        #expect(entrypoint.contains("dpCommandsSent: false"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}

private extension String {
    func occurrenceCount(of needle: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = startIndex..<endIndex
        while let match = range(of: needle, range: searchRange) {
            count += 1
            searchRange = match.upperBound..<endIndex
        }
        return count
    }
}
