from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
E=ROOT/'NembraApp/App/NembraCaptureEntrypoint.swift'
T=ROOT/'Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests'

def exact(s,old,new,label):
    if s.count(old)!=1 or new in s: raise SystemExit(f'{label} anchor changed old={s.count(old)} new={new in s}')
    return s.replace(old,new,1)

def apply():
    s=E.read_text()
    s=exact(s,
'''        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipRequestID = UUID()
        membershipBusy = false
''',
'''        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = "Scooter membership must be verified again for this Secure Link session."
        membershipRequestID = UUID()
        membershipBusy = false
''','view-exit membership status')
    s=exact(s,
'''    func appDidLoseForeground() {
        guard !foregroundIntegrityLossHandled else { return }
        foregroundIntegrityLossHandled = true
''',
'''    func appDidLoseForeground() {
        // A sealed accepted artifact remains immutable/shareable after later app lifecycle changes.
        guard phase != .accepted else { return }
        guard !foregroundIntegrityLossHandled else { return }
        foregroundIntegrityLossHandled = true
''','accepted preservation')
    # second membership block is now the foreground block after the first replacement
    needle='''        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipRequestID = UUID()
        membershipBusy = false
'''
    repl='''        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = "Capture left the foreground. Exact scooter membership must be verified again before another attempt."
        membershipRequestID = UUID()
        membershipBusy = false
'''
    if s.count(needle)!=1: raise SystemExit(f'foreground membership block changed {s.count(needle)}')
    s=s.replace(needle,repl,1)
    s=exact(s,
'''        if processCorrelationLease != nil || correlationSession != nil {
            // Existing helper stops package transport before releasing this controller's lease.
            abandonPackageCorrelation()
            phase = .failed
''',
'''        if processCorrelationLease != nil || correlationSession != nil {
            // Reset retires package transport before its owner-token lease and erases partial target authority.
            resetDiscoverySessionOnly()
            phase = .failed
''','foreground package reset')
    s=exact(s,
'''        guard let token = currentConnectionToken else {
            if phase == .authenticating {
''',
'''        guard let token = currentConnectionToken else {
            if phase == .correlated || phase == .selected {
                resetDiscoverySessionOnly()
                phase = .failed
                message = "Capture left the foreground after target correlation. Restart from OFF1; correlated target authority cannot cross a foreground interruption."
                log("foreground_integrity_lost_after_target_correlation")
                return
            }
            if phase == .authenticating {
''','correlated authority retirement')
    recv='    private func receivedApplicationUpdate(\n'
    helper='''    private func redactVerifiedAccountUIDFromApplicationEvent(_ update: [String: String], verifiedAccountUID: String) -> [String: String] {
        let uid = verifiedAccountUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else { return [:] }
        func redact(_ value: String) -> String {
            value.replacingOccurrences(of: uid, with: "<redacted-account-uid>", options: [.caseInsensitive, .literal])
        }
        var redacted: [String: String] = [:]
        redacted.reserveCapacity(update.count)
        for (key, value) in update { redacted[redact(key)] = redact(value) }
        return redacted
    }

'''
    if s.count(recv)!=1 or 'redactVerifiedAccountUIDFromApplicationEvent' in s: raise SystemExit('UID helper anchor changed')
    s=s.replace(recv,helper+recv,1)
    s=exact(s,
'''        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
            await recordObservedTransportLoss(token: token)
            return
        }

        applicationUpdateAdmissionsInFlight += 1
''',
'''        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
            await recordObservedTransportLoss(token: token)
            return
        }
        guard let verifiedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines), !verifiedAccountUID.isEmpty else {
            await invalidateSourceAuthority(token: token, message: "Verified Tuya account identity became unavailable before application evidence custody.", kind: "sdk_account_uid_authority_missing_during_observation")
            return
        }
        let redactedUpdate = redactVerifiedAccountUIDFromApplicationEvent(update, verifiedAccountUID: verifiedAccountUID)

        applicationUpdateAdmissionsInFlight += 1
''','UID admission')
    s=exact(s,
'''            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })
''',
'''            log("tuya_application_update", redactedUpdate.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { _, trusted in trusted })
''','trusted event custody')
    E.write_text(s)
    tests={
'TuyaResidualForegroundTruthSourceTests.swift':'''import Foundation\nimport Testing\n@testable import NembraBluetoothCapture\n@Suite("Residual foreground truth") struct TuyaResidualForegroundTruthSourceTests {\n @Test func residualForegroundTruth() throws { let s=try src(); let a=String(try section(s,"func abandonCorrelationForViewExit()","var privateConfig: Bool")); let f=String(try section(s,"func appDidLoseForeground()","var privateConfig: Bool")); #expect(a.contains("membershipStatus = ")); #expect(f.contains("guard phase != .accepted else { return }")); #expect(f.contains("phase == .correlated || phase == .selected")); #expect(f.contains("resetDiscoverySessionOnly()")); #expect(f.contains("foreground_integrity_lost_after_target_correlation")) }\n private func src() throws->String { var r=URL(fileURLWithPath:#filePath); for _ in 0..<5 {r.deleteLastPathComponent()}; return try String(contentsOf:r.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"),encoding:.utf8)}\n private func section(_ s:String,_ a:String,_ b:String)throws->Substring{guard let x=s.range(of:a),let y=s.range(of:b,range:x.upperBound..<s.endIndex)else{throw E.m};return s[x.lowerBound..<y.lowerBound]} private enum E:Error{case m}\n}\n''',
'TuyaApplicationEventMetadataPrecedenceSourceTests.swift':'''import Foundation\nimport Testing\n@testable import NembraBluetoothCapture\n@Suite("Application event metadata precedence") struct TuyaApplicationEventMetadataPrecedenceSourceTests { @Test func trustedGenerationWins() throws { let s=try src(); #expect(s.contains(") { _, trusted in trusted })")); #expect(!s.contains(") { current, _ in current })")) } private func src() throws->String { var r=URL(fileURLWithPath:#filePath); for _ in 0..<5 {r.deleteLastPathComponent()}; return try String(contentsOf:r.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"),encoding:.utf8)} }\n''',
'TuyaApplicationAccountUIDExportCustodySourceTests.swift':'''import Foundation\nimport Testing\n@testable import NembraBluetoothCapture\n@Suite("Application account UID custody") struct TuyaApplicationAccountUIDExportCustodySourceTests { @Test func uidIsValueBound() throws { let s=try src(); #expect(s.contains("<redacted-account-uid>")); #expect(s.contains("redacted[redact(key)] = redact(value)")); #expect(s.contains("redactedUpdate.merging([")); #expect(!s.contains("log(\\\"tuya_application_update\\\", update.merging([")) } private func src() throws->String { var r=URL(fileURLWithPath:#filePath); for _ in 0..<5 {r.deleteLastPathComponent()}; return try String(contentsOf:r.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"),encoding:.utf8)} }\n'''}
    for n,c in tests.items():
        p=T/n
        if p.exists(): raise SystemExit(f'test exists {n}')
        p.write_text(c)

def verify():
    s=E.read_text()
    for x in ['guard phase != .accepted else { return }','foreground_integrity_lost_after_target_correlation','<redacted-account-uid>','redactedUpdate.merging([',') { _, trusted in trusted })','membershipStatus = "Scooter membership must be verified again']:
        if x not in s: raise SystemExit(f'missing {x}')
    if ') { current, _ in current })' in s: raise SystemExit('untrusted generation precedence remains')
    for n in ['TuyaResidualForegroundTruthSourceTests.swift','TuyaApplicationEventMetadataPrecedenceSourceTests.swift','TuyaApplicationAccountUIDExportCustodySourceTests.swift']:
        if not (T/n).exists(): raise SystemExit(f'missing {n}')

if __name__=='__main__':
 import argparse; p=argparse.ArgumentParser(); p.add_argument('mode',choices=['apply','verify']); a=p.parse_args(); apply() if a.mode=='apply' else verify()
