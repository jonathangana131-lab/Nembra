import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture final convergence authority")
struct TuyaFinalConvergenceAuthoritySourceTests {
    @Test("correlation cannot authorize selection without operator action")
    func explicitTargetConfirmationOwnsSelection() throws {
        let app = try source()
        let finish = try section(app, "private func finishCorrelationSeries", "func invalidateSDKMembership")
        #expect(finish.contains("selectedID = nil"))
        #expect(finish.contains("phase = .correlated"))
        #expect(!finish.contains("selectedID = id"))
        let confirm = try section(app, "func confirmCorrelatedTarget", "func verifySDKMembership")
        #expect(confirm.contains("selectedID = candidate.id"))
        #expect(confirm.contains("phase = .selected"))
        #expect(confirm.contains("candidate_selected"))
        #expect(app.contains("Confirm correlated Bluetooth target"))
    }

    @Test("field build and chronology are first-class physical preflight authority")
    func buildAndChronologyAuthorityAreVisibleAndTerminal() throws {
        let app = try source()
        #expect(app.contains("var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }"))
        #expect(app.contains("LabeledContent(\"Field build\", value: test.fieldBuildIsAuthoritative"))
        #expect(app.contains("!test.fieldBuildIsAuthoritative || !test.privateConfig"))
        #expect(app.contains("markChronologyIntegrityInvalidated"))
        #expect(app.contains("sdk_local_ble_settlement_clock_invalid"))
        #expect(app.contains("localBLESettlementToken != token"))
    }

    private func source() throws -> String { try read("NembraApp/App/NembraCaptureEntrypoint.swift") }
    private func section(_ s: String, _ a: String, _ b: String) throws -> Substring {
        guard let x=s.range(of:a), let y=s.range(of:b, range:x.upperBound..<s.endIndex) else { throw E.missing }
        return s[x.lowerBound..<y.lowerBound]
    }
    private func read(_ p: String) throws -> String {
        let r=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf:r.appendingPathComponent(p), encoding:.utf8)
    }
    private enum E: Error { case missing }
}
