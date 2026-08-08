from pathlib import Path
import subprocess

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
    raise SystemExit(f'unexpected weak Preview declaration count={s.count(old)}')
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
    func previewForControllerStaging() throws -> StagingPreview {
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
    raise SystemExit(f'unexpected weak preview accessor count={s.count(old)}')
run.write_text(s.replace(old, new, 1))

controller = Path('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift')
s = controller.read_text()
start = s.index('    func connectUsingExperimentOneAdmission(')
end = s.index('    /// Cancels the active attempt', start)
method = s[start:end]
old = '''        // Inspect only immutable producer-owned staging metadata first. A target that has
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
new = '''        // Missing/not-yet-fresh rediscovery is recoverable. Inspect only the sealed
        // producer's read-only staging authority until every controller-local precondition
        // succeeds; do not burn the one-shot recorder handoff merely because scanning needs time.
        let preview = try admission.previewForControllerStaging()
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
              latestAdvertisement.receivedAtUptimeNanoseconds > preview.issuedAtUptimeNanoseconds else {
            // Equality does not prove this callback receipt happened after handoff. Keep the
            // admission intact and require a strictly later current-controller observation.
            throw ControllerError.unknownPeripheral(preview.peripheralIdentifier)
        }

        let payload = try admission.consume()
        guard payload.admissionIdentity == preview.admissionIdentity,
              payload.peripheralIdentifier == preview.peripheralIdentifier,
              payload.issuedAtUptimeNanoseconds == preview.issuedAtUptimeNanoseconds,
              case let .singleRepeatableCandidate(correlatedIdentifier) =
                payload.powerCycleEvidence.result.correlation.disposition,
              correlatedIdentifier == payload.peripheralIdentifier else {
            throw ControllerError.targetSessionChanged
        }
'''
if method.count(old) != 1:
    raise SystemExit(f'unexpected weak Experiment One block count={method.count(old)}')
method = method.replace(old, new, 1)
s = s[:start] + method + s[end:]
controller.write_text(s)

path = 'Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/ForegroundCoreBluetoothCaptureControllerExperimentOneRecoverableRediscoveryTests.swift'
blob = subprocess.check_output(['git', 'show', f'ab4c41fec39d42b52c5009f98e3cfc25ab37d243:{path}'], text=True)
Path(path).write_text(blob)

c = controller.read_text(); a = c.index('func connectUsingExperimentOneAdmission('); b = c.index('public func cancelActiveConnection()', a); m = c[a:b]
assert 'previewForControllerStaging()' in m
assert 'receivedAtUptimeNanoseconds > preview.issuedAtUptimeNanoseconds' in m
assert 'receivedAtUptimeNanoseconds >= preview.issuedAtUptimeNanoseconds' not in m
assert m.index('peripheralByIdentifier[') < m.index('admission.consume()')
assert m.index('latestDiscoveryByIdentifier[') < m.index('admission.consume()')
assert m.index('targetState.validateCanBeginAttempt(') < m.index('admission.consume()')
assert m.index('latestAdvertisementByIdentifier[') < m.index('admission.consume()')
assert m.index('admission.consume()') < m.index('recorder = payload.recorder')
assert m.count('admission.consume()') == 1
r = run.read_text(); ps = r.index('struct StagingPreview: Equatable, Sendable'); pe = r.index('struct Payload', ps); p = r[ps:pe]
assert 'fileprivate init(' in p and 'recorder' not in p and 'powerCycleEvidence' not in p
# Preserve newly merged terminal didFailToConnect recovery outside this method.
assert 'completeTerminalFreshTargetSessionIfReady' in c
assert 'didFailToConnect' in c
