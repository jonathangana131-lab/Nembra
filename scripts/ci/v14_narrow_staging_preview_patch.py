from pathlib import Path

run = Path('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneRun.swift')
s = run.read_text()
old = '''    struct Preview: Equatable, Sendable {
        let admissionIdentity: UUID
        let powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence
        let peripheralIdentifier: UUID
        /// Local monotonic handoff boundary. This is callback chronology only, never RF emission time.
        let issuedAtUptimeNanoseconds: UInt64
    }
'''
new = '''    struct StagingPreview: Equatable, Sendable {
        let admissionIdentity: UUID
        let peripheralIdentifier: UUID
        /// Local monotonic handoff boundary. This is callback chronology only, never RF emission time.
        let issuedAtUptimeNanoseconds: UInt64

        fileprivate init(
            admissionIdentity: UUID,
            peripheralIdentifier: UUID,
            issuedAtUptimeNanoseconds: UInt64
        ) {
            self.admissionIdentity = admissionIdentity
            self.peripheralIdentifier = peripheralIdentifier
            self.issuedAtUptimeNanoseconds = issuedAtUptimeNanoseconds
        }
    }
'''
if s.count(old) != 1:
    raise SystemExit(f'unexpected Preview declaration count={s.count(old)}')
s = s.replace(old, new, 1)
old = '''    /// Read-only producer-owned staging view. Reading it cannot consume the handoff.
    var preview: Preview {
        Preview(
            admissionIdentity: payload.admissionIdentity,
            powerCycleEvidence: payload.powerCycleEvidence,
            peripheralIdentifier: payload.peripheralIdentifier,
            issuedAtUptimeNanoseconds: payload.issuedAtUptimeNanoseconds
        )
    }
'''
new = '''    /// Producer-owned read-only staging authority. It exposes no recorder or raw
    /// power-cycle evidence and cannot be read after any alias consumes the handoff.
    func stagingPreview() throws -> StagingPreview {
        guard !hasBeenConsumed else {
            throw ConsumptionError.alreadyConsumed
        }
        return StagingPreview(
            admissionIdentity: payload.admissionIdentity,
            peripheralIdentifier: payload.peripheralIdentifier,
            issuedAtUptimeNanoseconds: payload.issuedAtUptimeNanoseconds
        )
    }
'''
if s.count(old) != 1:
    raise SystemExit(f'unexpected preview accessor count={s.count(old)}')
run.write_text(s.replace(old, new, 1))

controller = Path('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift')
s = controller.read_text()
start = s.index('    func connectUsingExperimentOneAdmission(')
end = s.index('    /// Cancels the active attempt', start)
method = s[start:end]
method = method.replace('        let preview = admission.preview\n', '        let preview = try admission.stagingPreview()\n', 1)
old_guard = '''        guard case let .singleRepeatableCandidate(correlatedIdentifier) =
                preview.powerCycleEvidence.result.correlation.disposition,
              correlatedIdentifier == preview.peripheralIdentifier else {
            throw ControllerError.targetSessionChanged
        }
'''
if method.count(old_guard) != 1:
    raise SystemExit(f'unexpected preview correlation guard count={method.count(old_guard)}')
method = method.replace(old_guard, '', 1)
old_rebind = '''        guard payload.admissionIdentity == preview.admissionIdentity,
              payload.powerCycleEvidence == preview.powerCycleEvidence,
              payload.peripheralIdentifier == preview.peripheralIdentifier,
              payload.issuedAtUptimeNanoseconds == preview.issuedAtUptimeNanoseconds else {
            throw ControllerError.targetSessionChanged
        }
'''
new_rebind = '''        guard payload.admissionIdentity == preview.admissionIdentity,
              payload.peripheralIdentifier == preview.peripheralIdentifier,
              payload.issuedAtUptimeNanoseconds == preview.issuedAtUptimeNanoseconds,
              case let .singleRepeatableCandidate(correlatedIdentifier) =
                payload.powerCycleEvidence.result.correlation.disposition,
              correlatedIdentifier == payload.peripheralIdentifier else {
            throw ControllerError.targetSessionChanged
        }
'''
if method.count(old_rebind) != 1:
    raise SystemExit(f'unexpected consumed rebind count={method.count(old_rebind)}')
method = method.replace(old_rebind, new_rebind, 1)
s = s[:start] + method + s[end:]
controller.write_text(s)

test = Path('Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/ForegroundCoreBluetoothCaptureControllerExperimentOneRecoverableRediscoveryTests.swift')
t = test.read_text()
insert = '''\n    @Test("staging preview is narrow, producer-owned, and compatible with coordinator retry")\n    func stagingPreviewAuthorityIsNarrow() throws {\n        let testFile = URL(fileURLWithPath: #filePath)\n        let packageRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()\n        let runSource = try String(contentsOf: packageRoot.appendingPathComponent("Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneRun.swift"), encoding: .utf8)\n        let start = try #require(runSource.range(of: "struct StagingPreview: Equatable, Sendable"))\n        let end = try #require(runSource.range(of: "struct Payload", range: start.upperBound..<runSource.endIndex))\n        let preview = String(runSource[start.lowerBound..<end.lowerBound])\n        #expect(preview.contains("let admissionIdentity: UUID"))\n        #expect(preview.contains("let peripheralIdentifier: UUID"))\n        #expect(preview.contains("let issuedAtUptimeNanoseconds: UInt64"))\n        #expect(preview.contains("fileprivate init("))\n        #expect(!preview.contains("recorder"))\n        #expect(!preview.contains("powerCycleEvidence"))\n        #expect(runSource.contains("func stagingPreview() throws -> StagingPreview"))\n\n        let method = try Self.controllerMethodSource()\n        #expect(method.contains("let preview = try admission.stagingPreview()"))\n        #expect(!method.contains("preview.powerCycleEvidence"))\n        #expect(method.contains("payload.powerCycleEvidence.result.correlation.disposition"))\n    }\n'''
needle = '\n}\n'
pos = t.rfind(needle)
if pos < 0:
    raise SystemExit('test suite closing brace not found')
t = t[:pos] + insert + t[pos:]
test.write_text(t)

c = controller.read_text(); a = c.index('func connectUsingExperimentOneAdmission('); b = c.index('public func cancelActiveConnection()', a); m = c[a:b]
assert 'let preview = try admission.stagingPreview()' in m
assert 'preview.powerCycleEvidence' not in m
assert 'receivedAtUptimeNanoseconds > preview.issuedAtUptimeNanoseconds' in m
assert 'receivedAtUptimeNanoseconds >= preview.issuedAtUptimeNanoseconds' not in m
assert m.index('latestAdvertisementByIdentifier[') < m.index('admission.consume()') < m.index('payload.powerCycleEvidence.result.correlation.disposition') < m.index('recorder = payload.recorder')
assert m.count('admission.consume()') == 1
r = run.read_text(); ps = r.index('struct StagingPreview: Equatable, Sendable'); pe = r.index('struct Payload', ps); p = r[ps:pe]
assert 'fileprivate init(' in p and 'recorder' not in p and 'powerCycleEvidence' not in p
coord = Path('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneCoordinator.swift').read_text()
assert 'admission.stagingPreview()' in coord
