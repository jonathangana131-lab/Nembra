import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture accepted export envelope immutability")
struct TuyaAcceptedExportEnvelopeSealSourceTests {
    @Test("current-attempt event cut also freezes the full accepted envelope")
    func fullEnvelopeUsesCurrentAttemptCut() throws {
        let app = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(app, "private func startWatchdog", "private func recordObservedTransportLoss")
        let body = String(watchdog)
        guard let cut = body.range(of: "let acceptedEventPrefixAtCut = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))"),
              let snapshot = body.range(of: "let acceptedExportSnapshotAtCut = self.makeExportSnapshot(", range: cut.upperBound..<body.endIndex),
              let seal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)", range: snapshot.upperBound..<body.endIndex),
              let recheck = body.range(of: "guard self.acceptanceSourceAuthorityIsStillAuthorized", range: seal.upperBound..<body.endIndex),
              let publish = body.range(of: "self.sealedAcceptedExportSnapshot = acceptedExportSnapshotAtCut", range: recheck.upperBound..<body.endIndex) else {
            throw ContractError.missing
        }
        #expect(cut.lowerBound < snapshot.lowerBound)
        #expect(snapshot.lowerBound < seal.lowerBound)
        #expect(seal.lowerBound < recheck.lowerBound)
        #expect(recheck.lowerBound < publish.lowerBound)
    }

    @Test("accepted export uses the sealed snapshot and changes only share time")
    func acceptedExportUsesSnapshot() throws {
        let app = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        let export = try section(app, "func prepareExport()", "private func resetDiscoverySessionOnly()")
        #expect(app.contains("private var sealedAcceptedExportSnapshot: Export?"))
        #expect(export.contains("guard var acceptedSnapshot = self.sealedAcceptedExportSnapshot"))
        #expect(export.contains("acceptedSnapshot.exportedAt = Date()"))
        #expect(export.contains("envelope = acceptedSnapshot"))
    }

    @Test("source authority is rechecked after the package-seal suspension")
    func packageSealCannotPromoteChangedSDKAuthority() throws {
        let app = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("private var acceptanceSourceAuthorityIsStillAuthorized: Bool"))
        #expect(app.contains("buildIdentity.isAuthoritativeFieldBuild"))
        #expect(app.contains("sdkDeviceMembershipVerified"))
        #expect(app.contains("accountIdentityLeaseIsAuthorized"))
        #expect(app.contains("source_authority_changed_during_acceptance_seal"))
    }

    @Test("fresh attempt clears both accepted artifact snapshots")
    func resetClearsBothSnapshots() throws {
        let app = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        let reset = try section(app, "private func resetDiscoverySessionOnly()", "private func failLocally")
        #expect(reset.contains("sealedAcceptedEventPrefix = nil"))
        #expect(reset.contains("sealedAcceptedExportSnapshot = nil"))
    }

    @Test("only export time is mutable in the sealed value")
    func snapshotMutabilityIsNarrow() throws {
        let app = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        let exportType = try section(app, "struct Export: Codable", "struct Event: Codable")
        #expect(exportType.contains("var exportedAt: Date"))
        #expect(!exportType.contains("var sdkAccountLoggedIn:"))
        #expect(!exportType.contains("var sdkDeviceMembershipVerified:"))
        #expect(!exportType.contains("var events:"))
    }

    private func section(_ source: String, _ start: String, _ end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw ContractError.missing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func read(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum ContractError: Error { case missing }
}
