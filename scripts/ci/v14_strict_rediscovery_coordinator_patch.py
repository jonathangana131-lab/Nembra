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
        let preview = try admission.stagingPreview()
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
    raise SystemExit(f'unexpected Experiment One staging block count={method.count(old)}')
method = method.replace(old, new, 1)
s = s[:start] + method + s[end:]
controller.write_text(s)

test = Path('Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/ForegroundCoreBluetoothCaptureControllerExperimentOneRecoverableRediscoveryTests.swift')
test.write_text(r'''import Foundation
import Testing

@Suite("Experiment One recoverable rediscovery admission")
struct ForegroundCoreBluetoothCaptureControllerExperimentOneRecoverableRediscoveryTests {
    private static func controllerMethodSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: packageRoot.appendingPathComponent("Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift"), encoding: .utf8)
        let start = try #require(source.range(of: "func connectUsingExperimentOneAdmission("))
        let end = try #require(source.range(of: "public func cancelActiveConnection()", range: start.lowerBound..<source.endIndex))
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private static func runSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent("Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneRun.swift"), encoding: .utf8)
    }

    @Test("recoverable staging precedes one-shot consumption with strict post-handoff chronology")
    func rediscoveryMissDoesNotBurnAdmission() throws {
        let method = try Self.controllerMethodSource()
        let preview = try #require(method.range(of: "stagingPreview()"))
        let catalog = try #require(method.range(of: "peripheralByIdentifier[preview.peripheralIdentifier]"))
        let discovery = try #require(method.range(of: "latestDiscoveryByIdentifier[preview.peripheralIdentifier]"))
        let attempt = try #require(method.range(of: "targetState.validateCanBeginAttempt(for: preview.peripheralIdentifier)"))
        let advertisement = try #require(method.range(of: "latestAdvertisementByIdentifier[preview.peripheralIdentifier]"))
        let freshness = try #require(method.range(of: "receivedAtUptimeNanoseconds > preview.issuedAtUptimeNanoseconds"))
        let consume = try #require(method.range(of: "admission.consume()"))
        let rebind = try #require(method.range(of: "payload.admissionIdentity == preview.admissionIdentity"))
        let publication = try #require(method.range(of: "recorder = payload.recorder"))
        #expect(preview.lowerBound < catalog.lowerBound)
        #expect(catalog.lowerBound < consume.lowerBound)
        #expect(discovery.lowerBound < consume.lowerBound)
        #expect(attempt.lowerBound < consume.lowerBound)
        #expect(advertisement.lowerBound < consume.lowerBound)
        #expect(freshness.lowerBound < consume.lowerBound)
        #expect(consume.lowerBound < rebind.lowerBound)
        #expect(rebind.lowerBound < publication.lowerBound)
        #expect(method.components(separatedBy: "admission.consume()").count - 1 == 1)
        #expect(!method.contains("receivedAtUptimeNanoseconds >= preview.issuedAtUptimeNanoseconds"))
    }

    @Test("staging preview carries no recorder or raw evidence and is producer constructed")
    func previewSurfaceIsNarrow() throws {
        let source = try Self.runSource()
        let start = try #require(source.range(of: "struct StagingPreview: Equatable, Sendable"))
        let end = try #require(source.range(of: "struct Payload", range: start.upperBound..<source.endIndex))
        let preview = String(source[start.lowerBound..<end.lowerBound])
        #expect(preview.contains("let admissionIdentity: UUID"))
        #expect(preview.contains("let peripheralIdentifier: UUID"))
        #expect(preview.contains("let issuedAtUptimeNanoseconds: UInt64"))
        #expect(preview.contains("fileprivate init("))
        #expect(!preview.contains("recorder"))
        #expect(!preview.contains("powerCycleEvidence"))
        #expect(source.contains("func stagingPreview() throws -> StagingPreview"))
    }
}
''')

c = controller.read_text(); a = c.index('func connectUsingExperimentOneAdmission('); b = c.index('public func cancelActiveConnection()', a); m = c[a:b]
assert 'stagingPreview()' in m
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
coord = Path('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneCoordinator.swift').read_text()
assert 'admission.stagingPreview()' in coord
assert 'completeTerminalFreshTargetSessionIfReady' in c
