from pathlib import Path
import subprocess

run = Path('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneRun.swift')
s = run.read_text()
old = '''    struct Payload {
        let admissionIdentity: UUID
        let powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence
        let peripheralIdentifier: UUID
        let recorder: PassiveCoreBluetoothCaptureRecorder
        /// Local monotonic handoff boundary. This is callback chronology only, never RF emission time.
        let issuedAtUptimeNanoseconds: UInt64
'''
new = '''    struct Preview: Equatable, Sendable {
        let admissionIdentity: UUID
        let powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence
        let peripheralIdentifier: UUID
        /// Local monotonic handoff boundary. This is callback chronology only, never RF emission time.
        let issuedAtUptimeNanoseconds: UInt64
    }

    struct Payload {
        let admissionIdentity: UUID
        let powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence
        let peripheralIdentifier: UUID
        let recorder: PassiveCoreBluetoothCaptureRecorder
        /// Local monotonic handoff boundary. This is callback chronology only, never RF emission time.
        let issuedAtUptimeNanoseconds: UInt64
'''
if s.count(old) != 1:
    raise SystemExit('unexpected admission Payload declaration')
s = s.replace(old, new, 1)
old = '''    func consume() throws -> Payload {
        guard !hasBeenConsumed else {
            throw ConsumptionError.alreadyConsumed
        }
        hasBeenConsumed = true
        return payload
    }
'''
new = '''    /// Read-only producer-owned staging view. Reading it cannot consume the handoff.
    var preview: Preview {
        Preview(
            admissionIdentity: payload.admissionIdentity,
            powerCycleEvidence: payload.powerCycleEvidence,
            peripheralIdentifier: payload.peripheralIdentifier,
            issuedAtUptimeNanoseconds: payload.issuedAtUptimeNanoseconds
        )
    }

    func consume() throws -> Payload {
        guard !hasBeenConsumed else {
            throw ConsumptionError.alreadyConsumed
        }
        hasBeenConsumed = true
        return payload
    }
'''
if s.count(old) != 1:
    raise SystemExit('unexpected admission consume declaration')
run.write_text(s.replace(old, new, 1))

controller = Path('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift')
s = controller.read_text()
start = s.index('    func connectUsingExperimentOneAdmission(')
end = s.index('    /// Cancels the active attempt', start)
method = s[start:end]
old = '''        let payload = try admission.consume()
        guard case let .singleRepeatableCandidate(correlatedIdentifier) =
                payload.powerCycleEvidence.result.correlation.disposition,
              correlatedIdentifier == payload.peripheralIdentifier else {
            throw ControllerError.targetSessionChanged
        }
        guard let peripheral = peripheralByIdentifier[payload.peripheralIdentifier],
              let discovery = latestDiscoveryByIdentifier[payload.peripheralIdentifier] else {
            throw ControllerError.unknownPeripheral(payload.peripheralIdentifier)
        }
        if discovery.isConnectable == false {
            throw ControllerError.peripheralNotConnectable(payload.peripheralIdentifier)
        }

        do {
            try targetState.validateCanBeginAttempt(for: payload.peripheralIdentifier)
        } catch PassiveCoreBluetoothTargetState.StateError.peripheralAwaitingTerminalCallback(let identifier) {
            throw ControllerError.peripheralAwaitingTerminalCallback(identifier)
        } catch PassiveCoreBluetoothTargetState.StateError.generationExhausted {
            throw ControllerError.attemptGenerationExhausted
        } catch {
            throw ControllerError.targetNotSelected
        }

        guard let latestAdvertisement = latestAdvertisementByIdentifier[payload.peripheralIdentifier],
              latestAdvertisement.receivedAtUptimeNanoseconds >= payload.issuedAtUptimeNanoseconds else {
            // The sealed admission must be joined to a controller observation received after
            // that handoff. Replaying an older cached advertisement would splice two software
            // chronology lives and could enqueue evidence that predates this recorder.
            throw ControllerError.unknownPeripheral(payload.peripheralIdentifier)
        }
'''
new = '''        // Inspect only immutable producer-owned staging metadata first. A target that has
        // not reappeared yet is recoverable by continuing passive scan and retrying this same
        // sealed admission, so do not burn its one-shot ownership handoff here.
        let preview = admission.preview
        guard case let .singleRepeatableCandidate(correlatedIdentifier) =
                preview.powerCycleEvidence.result.correlation.disposition,
              correlatedIdentifier == preview.peripheralIdentifier else {
            throw ControllerError.targetSessionChanged
        }
        guard let peripheral = peripheralByIdentifier[preview.peripheralIdentifier],
              let discovery = latestDiscoveryByIdentifier[preview.peripheralIdentifier] else {
            throw ControllerError.unknownPeripheral(preview.peripheralIdentifier)
        }
        if discovery.isConnectable == false {
            throw ControllerError.peripheralNotConnectable(preview.peripheralIdentifier)
        }

        do {
            try targetState.validateCanBeginAttempt(for: preview.peripheralIdentifier)
        } catch PassiveCoreBluetoothTargetState.StateError.peripheralAwaitingTerminalCallback(let identifier) {
            throw ControllerError.peripheralAwaitingTerminalCallback(identifier)
        } catch PassiveCoreBluetoothTargetState.StateError.generationExhausted {
            throw ControllerError.attemptGenerationExhausted
        } catch {
            throw ControllerError.targetNotSelected
        }

        guard let latestAdvertisement = latestAdvertisementByIdentifier[preview.peripheralIdentifier],
              latestAdvertisement.receivedAtUptimeNanoseconds >= preview.issuedAtUptimeNanoseconds else {
            // The sealed admission must be joined to a controller observation received after
            // that handoff. Replaying an older cached advertisement would splice two software
            // chronology lives and could enqueue evidence that predates this recorder.
            throw ControllerError.unknownPeripheral(preview.peripheralIdentifier)
        }

        // Every recoverable controller-local staging check has passed. Consume exactly once
        // at the irreversible ownership handoff and bind the consumed payload back to the
        // same producer preview before publishing the run-owned recorder.
        let payload = try admission.consume()
        guard payload.admissionIdentity == preview.admissionIdentity,
              payload.powerCycleEvidence == preview.powerCycleEvidence,
              payload.peripheralIdentifier == preview.peripheralIdentifier,
              payload.issuedAtUptimeNanoseconds == preview.issuedAtUptimeNanoseconds else {
            throw ControllerError.targetSessionChanged
        }
'''
if method.count(old) != 1:
    raise SystemExit('unexpected Experiment One consumer staging block')
method = method.replace(old, new, 1)
s = s[:start] + method + s[end:]
controller.write_text(s)

path = 'Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/ForegroundCoreBluetoothCaptureControllerExperimentOneRecoverableRediscoveryTests.swift'
blob = subprocess.check_output(['git', 'show', f'313f9aeb52c550c350c819996c434b6076447a9d:{path}'], text=True)
Path(path).write_text(blob)

c = controller.read_text()
a = c.index('func connectUsingExperimentOneAdmission(')
b = c.index('public func cancelActiveConnection()', a)
m = c[a:b]
for token in [
    'let preview = admission.preview',
    'peripheralByIdentifier[preview.peripheralIdentifier]',
    'latestDiscoveryByIdentifier[preview.peripheralIdentifier]',
    'targetState.validateCanBeginAttempt(for: preview.peripheralIdentifier)',
    'latestAdvertisementByIdentifier[preview.peripheralIdentifier]',
    'receivedAtUptimeNanoseconds >= preview.issuedAtUptimeNanoseconds',
    'let payload = try admission.consume()',
    'payload.admissionIdentity == preview.admissionIdentity',
    'recorder = payload.recorder',
]:
    assert token in m, token
assert m.index('peripheralByIdentifier[') < m.index('admission.consume()')
assert m.index('latestDiscoveryByIdentifier[') < m.index('admission.consume()')
assert m.index('targetState.validateCanBeginAttempt(') < m.index('admission.consume()')
assert m.index('latestAdvertisementByIdentifier[') < m.index('admission.consume()')
assert m.index('receivedAtUptimeNanoseconds >=') < m.index('admission.consume()')
assert m.index('admission.consume()') < m.index('recorder = payload.recorder')
assert m.count('admission.consume()') == 1
r = run.read_text()
assert 'struct Preview: Equatable, Sendable' in r
assert 'var preview: Preview' in r
assert r.count('func consume() throws -> Payload') == 1
