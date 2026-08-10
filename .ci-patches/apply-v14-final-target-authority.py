from pathlib import Path
import re

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
GO = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldGoPrerequisiteSourceTests.swift")
FINAL = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldFinalAuthoritySourceTests.swift")
TRANSPORT = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaTransportSuccessAuthoritySourceTests.swift")
TEST_DIR = GO.parent


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 literal match, found {count}")
    return text.replace(old, new, 1)


def sub_once(text: str, pattern: str, replacement: str, label: str) -> str:
    rx = re.compile(pattern, re.MULTILINE | re.DOTALL)
    matches = list(rx.finditer(text))
    if len(matches) != 1:
        raise SystemExit(f"{label}: expected 1 regex match, found {len(matches)}")
    return rx.sub(lambda _: replacement, text, count=1)


app = APP.read_text()
app = replace_once(
    app,
    "The next physical run is stationary. It proves current SDK account authority, exact scooter membership, the accepted physical Bluetooth target, Tuya-owned authentication, genuine same-generation application updates, and a sealed 45-second observation prefix.",
    "The next physical run is stationary. It proves current SDK account authority, exact scooter membership, a fresh repeated OFF1→ON1→OFF2→ON2 Bluetooth correlation with explicit confirmation, Tuya-owned authentication, genuine same-generation application updates, and a sealed 45-second observation prefix.",
    "root target copy",
)

candidate = '''    struct Candidate: Identifiable, Codable, Equatable {
        let id: UUID
        var name: String?
        var rssi: Int?
        var advertisements: Int
        var newAfterPowerOn: Bool
        var fd50: Bool
        var tuyaCompany: Bool
        var historicalCaptureID: Bool
        var freshlyCorrelated: Bool
        var expectedName: Bool
        var score: Int
        var evidence: [String]

        var title: String { name?.isEmpty == false ? name! : "Correlated Bluetooth target" }
        // Only this attempt's package-owned repeated power-cycle result can make a
        // candidate eligible for explicit operator confirmation. C7D09A22 remains
        // descriptive historical evidence, never durable scooter identity.
        var likely: Bool { freshlyCorrelated }
    }

    enum Phase: String, Codable {
        case idle, baseline, powerOn, scanning, correlated, selected, authenticating, observing, accepted, failed
    }

    struct CorrelationCandidateExport: Codable {
        let id: String
        let isConnectable: Bool?
    }

    struct CorrelationSnapshotExport: Codable {
        let phase: String
        let observationSeriesIdentity: String
        let windowSequence: UInt64
        let candidates: [CorrelationCandidateExport]
    }

    struct CorrelationWindowExport: Codable {
        let phase: String
        let windowSequence: UInt64
        let startedAtUptimeNanoseconds: UInt64
        let endedAtUptimeNanoseconds: UInt64
        let observedCandidateCount: Int
    }

    struct CorrelationExport: Codable {
        let method: String
        let disposition: String
        let operatorConfirmed: Bool
        let repeatableCandidateIDs: [String]
        let observationSeriesIdentities: [String]
        let windows: [CorrelationWindowExport]
        let snapshots: [CorrelationSnapshotExport]
    }

    struct Export: Codable {'''
app = sub_once(
    app,
    r"    struct Candidate: Identifiable, Codable, Equatable \{.*?^    struct Export: Codable \{",
    candidate,
    "candidate/phase/export support model",
)
app = replace_once(
    app,
    "        let selectedPeripheralID: String?\n        let phase: Phase",
    "        let selectedPeripheralID: String?\n        let targetCorrelation: CorrelationExport?\n        let phase: Phase",
    "correlation export field",
)
app = replace_once(
    app,
    '    static let knownPeripheral = UUID(uuidString: "6815A5F5-4D1E-E004-BAE8-6DF924123907")!',
    '    static let historicalCapturePeripheral = UUID(uuidString: "6815A5F5-4D1E-E004-BAE8-6DF924123907")!',
    "historical UUID label",
)
app = replace_once(
    app,
    "    private var baseline = Set<UUID>()\n    private var driver: OfficialTuyaDriver?",
    "    private var baseline = Set<UUID>()\n    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?\n    private var correlationResult: PassiveBluetoothPowerCycleObservationResult?\n    private var pendingCorrelatedTargetID: UUID?\n    private var driver: OfficialTuyaDriver?",
    "correlation state storage",
)
app = replace_once(
    app,
    "    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }",
    '''    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }
    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }
    var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }
    var correlationWindowIsScanning: Bool { correlationProgress?.isScanning == true }
    var correlationObservedCandidateCount: Int { correlationProgress?.currentObservedCandidateCount ?? 0 }
    var correlationCompletedWindowCount: Int { correlationProgress?.completedWindowCount ?? 0 }

    var correlationWindowLabel: String {
        guard let phase = correlationProgress?.phase else { return "OFF1" }
        return Self.correlationPhaseLabel(phase)
    }

    var correlationWindowInstruction: String {
        guard let phase = correlationProgress?.phase else { return "Keep the scooter OFF and stationary." }
        return phase.operatorExpectedPowerOn
            ? "Turn the scooter ON and keep it stationary."
            : "Turn the scooter OFF and keep it stationary."
    }''',
    "presentation authority and correlation progress",
)

flow = '''    func startBaseline() {
        guard central.state == .poweredOn else {
            failLocally("Bluetooth is not ready.", "bluetooth_unavailable")
            return
        }
        guard buildIdentity.isAuthoritativeFieldBuild else {
            failLocally(buildIdentity.blocker ?? "Exact field-build provenance is unavailable.", "field_build_identity_unavailable")
            return
        }
        guard privateConfig, sdkAccountLoggedIn else {
            failLocally("Private Tuya app identity and a current SDK login are required before any scooter correlation scan.", "sdk_authority_required_before_scan")
            return
        }

        // Every physical attempt earns a fresh complete same-account exact-device membership
        // verdict before the package-owned four-window producer is allowed to scan.
        verifySDKMembership { [weak self] authorized in
            guard let self else { return }
            let leaseVerdict = TuyaSDKAccountIdentityLeaseGate.verdict(for: self.accountIdentityLeaseSnapshot)
            guard authorized,
                  self.sdkAccountLoggedIn,
                  leaseVerdict == .authorized else {
                self.failLocally("Exact scooter membership could not be proven for this same current SDK account. Bluetooth correlation remains disabled.", "sdk_device_membership_required_before_scan")
                return
            }
            self.beginBaselineScan()
        }
    }

    private func beginBaselineScan() {
        guard privateConfig,
              sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            failLocally("SDK account/device authority changed before correlation began.", "sdk_authority_changed_before_scan")
            return
        }
        guard currentConnectionToken == nil else {
            failLocally(
                "A prior authenticated generation has not been terminally retired. Relaunch Capture before starting another attempt.",
                "active_generation_blocks_discovery_reset"
            )
            return
        }

        resetDiscoverySessionOnly()
        do {
            correlationSession = try PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)
            log("target_correlation_series_created", [
                "method": "package-owned-fresh-manager-off1-on1-off2-on2",
                "minimumWindowSeconds": "10"
            ])
            startCurrentCorrelationWindow()
        } catch {
            failLocally("Could not create the bounded Bluetooth correlation series: \(error.localizedDescription)", "target_correlation_series_create_failed")
        }
    }

    func startNextCorrelationWindow() {
        guard phase == .powerOn else { return }
        startCurrentCorrelationWindow()
    }

    private func startCurrentCorrelationWindow() {
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
            failLocally("SDK account/device authority changed before the next correlation window.", "sdk_authority_changed_during_target_correlation")
            return
        }
        guard let session = correlationSession,
              let progress = session.progress else {
            failLocally("Fresh Bluetooth correlation authority is unavailable. Restart from OFF1.", "target_correlation_authority_unavailable")
            return
        }

        let label = Self.correlationPhaseLabel(progress.phase)
        do {
            try session.startCurrentWindow()
            phase = progress.phase.operatorExpectedPowerOn ? .scanning : .baseline
            message = "\(label) requested with a fresh CoreBluetooth manager. Wait for scanner liveness, then keep this state for at least 10 receipt-bounded seconds before sealing it."
            log("target_correlation_window_started", [
                "window": label,
                "operatorExpectedPowerOn": String(progress.phase.operatorExpectedPowerOn),
                "completedWindows": String(progress.completedWindowCount)
            ])
        } catch {
            session.abandonCurrentWindow()
            correlationSession = nil
            failLocally("The \(label) correlation window failed closed: \(error.localizedDescription). Restart from OFF1.", "target_correlation_window_start_failed")
        }
    }

    func finishCorrelationWindow() {
        guard phase == .baseline || phase == .scanning,
              let session = correlationSession else { return }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            session.abandonCurrentWindow()
            correlationSession = nil
            failLocally("SDK account/device authority changed during Bluetooth correlation. Restart from OFF1 after re-verifying membership.", "sdk_authority_changed_during_target_correlation")
            return
        }

        let sealedLabel = correlationWindowLabel
        do {
            let final = try session.finishCurrentWindow()
            if let final {
                finishCorrelationSeries(final)
                return
            }

            phase = .powerOn
            message = "\(sealedLabel) sealed. \(correlationWindowInstruction) When the scooter has settled, start \(correlationWindowLabel)."
            log("target_correlation_window_sealed", [
                "window": sealedLabel,
                "completedWindows": String(correlationCompletedWindowCount)
            ])
        } catch let error as PassiveBluetoothPowerCycleObservationSessionError {
            switch error {
            case .minimumWindowDurationNotReached:
                message = "Keep \(sealedLabel) unchanged a little longer. The package has not yet earned the required 10 receipt-bounded seconds."
            case .scanReadinessPending:
                message = "\(sealedLabel) is still waiting for confirmed CoreBluetooth scan liveness. Do not advance the physical state yet."
            default:
                session.abandonCurrentWindow()
                correlationSession = nil
                failLocally("\(sealedLabel) failed closed (\(String(describing: error))). Restart the complete OFF1→ON1→OFF2→ON2 series.", "target_correlation_window_failed")
            }
        } catch {
            session.abandonCurrentWindow()
            correlationSession = nil
            failLocally("\(sealedLabel) failed closed: \(error.localizedDescription). Restart the complete correlation series.", "target_correlation_window_failed")
        }
    }

    private func finishCorrelationSeries(_ result: PassiveBluetoothPowerCycleObservationResult) {
        correlationResult = result
        correlationSession = nil

        switch result.correlation.disposition {
        case let .singleRepeatableCandidate(id):
            let historicalCaptureID = id == Self.historicalCapturePeripheral
            var evidence = ["fresh OFF1→ON1→OFF2→ON2 full-UUID correlation"]
            if historicalCaptureID {
                evidence.append("matches C7D09A22 capture-local UUID descriptive")
            }
            let candidate = Candidate(
                id: id,
                name: nil,
                rssi: nil,
                advertisements: 0,
                newAfterPowerOn: true,
                fd50: false,
                tuyaCompany: false,
                historicalCaptureID: historicalCaptureID,
                freshlyCorrelated: true,
                expectedName: false,
                score: 0,
                evidence: evidence
            )
            byID = [id: candidate]
            candidates = [candidate]
            pendingCorrelatedTargetID = id
            selectedID = nil
            phase = .correlated
            message = "One full CoreBluetooth UUID repeated the complete fresh correlation series. Confirm this correlated Bluetooth target explicitly before authentication. This is current-session correlation evidence, not permanent scooter identity."
            log("target_correlation_ready_for_confirmation", [
                "id": id.uuidString,
                "authority": "fresh-repeated-off-on-full-corebluetooth-id",
                "historicalCaptureUUIDMatch": String(historicalCaptureID),
                "windows": String(result.windows.count)
            ])

        case let .ambiguousRepeatableCandidates(ids):
            pendingCorrelatedTargetID = nil
            failLocally("Fresh correlation remained ambiguous across \(ids.count) repeatable full UUIDs. Do not guess from name, RSSI, FD50, Tuya hints, or the historical capture UUID; restart from OFF1 after reducing nearby-device ambiguity.", "target_correlation_ambiguous")

        case .noRepeatableCandidate:
            pendingCorrelatedTargetID = nil
            failLocally("No full UUID repeated the required OFF1→ON1→OFF2→ON2 pattern. Do not fall back to the historical capture UUID; restart the fresh correlation series.", "target_correlation_no_repeatable_candidate")

        case .invalidObservationAuthority, .invalidObservationWindowOrder:
            pendingCorrelatedTargetID = nil
            failLocally("The package rejected correlation provenance/chronology. Restart from OFF1; prior windows cannot be spliced into a new attempt.", "target_correlation_provenance_rejected")
        }
    }

    func confirmCorrelatedTarget() {
        guard phase == .correlated,
              let id = pendingCorrelatedTargetID,
              let candidate = byID[id],
              candidate.freshlyCorrelated else {
            message = "A fresh correlated Bluetooth target must be available before confirmation."
            return
        }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            failLocally("Current Tuya account/device authority changed before correlated-target confirmation.", "sdk_authority_changed_before_target_confirmation")
            return
        }

        selectedID = id
        phase = .selected
        message = "Correlated Bluetooth target confirmed for this attempt. Correlation scanning is retired before Tuya's SDK takes BLE ownership. This does not create permanent scooter identity."
        log("candidate_selected", [
            "id": id.uuidString,
            "authority": "operator-confirmed-fresh-power-cycle-correlation",
            "correlation": "OFF1-ON1-OFF2-ON2",
            "historicalCaptureUUIDMatch": String(candidate.historicalCaptureID)
        ])
    }

    func invalidateSDKMembership() {'''
app = sub_once(
    app,
    r"    func startBaseline\(\) \{.*?^    func invalidateSDKMembership\(\) \{",
    flow,
    "fresh four-window correlation and confirmation flow",
)

app = replace_once(
    app,
    "        central.stopScan()\n        if [.baseline, .powerOn, .scanning, .selected].contains(phase) {",
    "        correlationSession?.abandonCurrentWindow()\n        correlationSession = nil\n        central.stopScan()\n        if [.baseline, .powerOn, .scanning, .correlated, .selected].contains(phase) {",
    "membership invalidates correlation",
)
app = replace_once(
    app,
    '            failLocally("The accepted prior physical scooter identity is required.", "candidate_not_authoritative")',
    '            failLocally("An explicitly confirmed fresh correlated Bluetooth target is required.", "candidate_not_authoritative")',
    "authentication target copy",
)

# Preserve #2102 one-settlement-owner/source-drift fences, but classify local acquisition
# terminals without abusing source-authority loss and consume #2108's no-clock retirement.
app = replace_once(
    app,
    '''                } catch {
                    await invalidateSourceAuthority(
                        token: token,
                        message: "Authenticated-session chronology rejected the SDK success callback: \(error.localizedDescription)",
                        kind: "session_auth_callback_rejected"
                    )
                }
                return''',
    '''                } catch {
                    await invalidateChronologyIntegrity(
                        token: token,
                        message: "Authenticated-session chronology rejected the SDK success callback: \(error.localizedDescription)",
                        kind: "session_auth_callback_rejected"
                    )
                }
                return''',
    "auth promotion chronology terminal",
)
app = replace_once(
    app,
    '''            case .timedOut:
                await invalidateSourceAuthority(
                    token: token,
                    message: "Tuya reported transport success, but current local-BLE status did not become authoritative within the bounded settlement window.",
                    kind: "sdk_local_ble_settlement_timed_out"
                )
                return

            case .invalidClock:
                await invalidateSourceAuthority(
                    token: token,
                    message: "Local-BLE settlement failed closed because the monotonic clock regressed.",
                    kind: "sdk_local_ble_settlement_clock_invalid"
                )
                return''',
    '''            case .timedOut:
                await authenticationAcquisitionFailed(
                    token: token,
                    message: "Tuya reported transport success, but current local-BLE status did not become authoritative within the bounded settlement window.",
                    kind: "sdk_local_ble_settlement_timed_out"
                )
                return

            case .invalidClock:
                await invalidateChronologyIntegrity(
                    token: token,
                    message: "Local-BLE settlement failed closed because the monotonic clock regressed.",
                    kind: "sdk_local_ble_settlement_clock_invalid"
                )
                return''',
    "local acquisition terminal classification",
)

auth_helpers = '''    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else {
            log("stale_connect_failure_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        await authenticationAcquisitionFailed(
            token: token,
            message: "Tuya SmartLife SDK did not establish the supported BLE session.",
            kind: "official_connect_failed"
        )
    }

    private func authenticationAcquisitionFailed(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markAuthenticationFailed(for: token)
        } catch {
            // A failed monotonic sample must still retire callback authority without
            // taking another clock receipt.
            try? await sessionLedger.markChronologyIntegrityInvalidated(for: token)
        }
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        self.message = message
        log(kind, ["generation": String(token.diagnosticGeneration)])
    }

    private func invalidateChronologyIntegrity(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        try? await sessionLedger.markChronologyIntegrityInvalidated(for: token)
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        self.message = message
        log(kind, ["generation": String(token.diagnosticGeneration)])
    }

    private func receivedApplicationUpdate'''
app = sub_once(
    app,
    r"    private func authenticationFailed\(token: TuyaReadOnlyConnectionToken\) async \{.*?^    private func receivedApplicationUpdate",
    auth_helpers,
    "authentication/acquisition/chronology helpers",
)

export_helpers = '''    private static func correlationPhaseLabel(_ phase: PassiveBluetoothPowerCycleObservationPhase) -> String {
        switch phase {
        case .firstPoweredOff: return "OFF1"
        case .firstPoweredOn: return "ON1"
        case .secondPoweredOff: return "OFF2"
        case .secondPoweredOn: return "ON2"
        }
    }

    private static func correlationDispositionLabel(_ disposition: PassiveBluetoothPowerCycleTargetCorrelationReport.Disposition) -> String {
        switch disposition {
        case .invalidObservationAuthority: return "invalid-observation-authority"
        case .invalidObservationWindowOrder: return "invalid-observation-window-order"
        case .noRepeatableCandidate: return "no-repeatable-candidate"
        case .ambiguousRepeatableCandidates: return "ambiguous-repeatable-candidates"
        case .singleRepeatableCandidate: return "single-repeatable-candidate"
        }
    }

    private func makeCorrelationExport() -> CorrelationExport? {
        guard let result = correlationResult else { return nil }
        let windows = result.windows.map { receipt in
            CorrelationWindowExport(
                phase: Self.correlationPhaseLabel(receipt.phase),
                windowSequence: receipt.windowSequence.rawValue,
                startedAtUptimeNanoseconds: receipt.startedAtUptimeNanoseconds,
                endedAtUptimeNanoseconds: receipt.endedAtUptimeNanoseconds,
                observedCandidateCount: receipt.observedCandidateCount
            )
        }
        let phaseLabels = ["OFF1", "ON1", "OFF2", "ON2"]
        let snapshots = result.observationSnapshots.enumerated().map { pair in
            let index = pair.offset
            let snapshot = pair.element
            return CorrelationSnapshotExport(
                phase: index < phaseLabels.count ? phaseLabels[index] : "UNKNOWN",
                observationSeriesIdentity: snapshot.observationSeriesIdentity.rawValue.uuidString,
                windowSequence: snapshot.windowSequence.rawValue,
                candidates: snapshot.candidates.map {
                    CorrelationCandidateExport(id: $0.id.uuidString, isConnectable: $0.isConnectable)
                }
            )
        }
        return CorrelationExport(
            method: "package-owned-fresh-manager-off1-on1-off2-on2",
            disposition: Self.correlationDispositionLabel(result.correlation.disposition),
            operatorConfirmed: selectedID != nil && selectedID == pendingCorrelatedTargetID,
            repeatableCandidateIDs: result.correlation.repeatableCandidateIdentifiers.map(\.uuidString),
            observationSeriesIdentities: result.correlation.observationSeriesIdentities.map { $0.rawValue.uuidString },
            windows: windows,
            snapshots: snapshots
        )
    }

    func prepareExport() {'''
app = replace_once(app, "    func prepareExport() {", export_helpers, "correlation export helper insertion")
app = replace_once(app, "            schemaVersion: 7,", "            schemaVersion: 8,", "export schema bump")
app = replace_once(
    app,
    "            selectedPeripheralID: selectedID?.uuidString,\n            phase: phase,",
    "            selectedPeripheralID: selectedID?.uuidString,\n            targetCorrelation: makeCorrelationExport(),\n            phase: phase,",
    "export correlation evidence",
)
app = replace_once(
    app,
    "    private func resetDiscoverySessionOnly() {\n        central.stopScan()",
    "    private func resetDiscoverySessionOnly() {\n        correlationSession?.abandonCurrentWindow()\n        correlationSession = nil\n        correlationResult = nil\n        pendingCorrelatedTargetID = nil\n        central.stopScan()",
    "reset correlation state",
)
app = replace_once(
    app,
    "    private func failLocally(_ text: String, _ kind: String) {\n        watchdog?.cancel()",
    "    private func failLocally(_ text: String, _ kind: String) {\n        if phase == .baseline || phase == .powerOn || phase == .scanning {\n            correlationSession?.abandonCurrentWindow()\n            correlationSession = nil\n        }\n        watchdog?.cancel()",
    "fail closed active correlation",
)
app = replace_once(app, "        let knownID = id == Self.knownPeripheral", "        let historicalCaptureID = id == Self.historicalCapturePeripheral", "historical descriptive ID")
app = replace_once(app, '        if knownID { score += 1000; evidence.append("accepted prior physical UUID") }', '        if historicalCaptureID { evidence.append("matches C7D09A22 capture-local UUID descriptive") }', "remove old identity score")
app = replace_once(
    app,
    "            knownID: knownID,\n            expectedName: expectedName,",
    "            historicalCaptureID: historicalCaptureID,\n            freshlyCorrelated: false,\n            expectedName: expectedName,",
    "legacy descriptive candidate shape",
)
app = replace_once(app, '                    Text("Authenticate. Wait. Seal.").font(.largeTitle.bold())', '                    Text("Correlate. Confirm. Authenticate. Seal.").font(.largeTitle.bold())', "headline")

ui = '''    private var authorityCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Official Tuya authority", systemImage: "checkmark.shield").font(.headline)
            LabeledContent("Field build", value: test.fieldBuildIsAuthoritative ? "Authoritative" : "Not authoritative")
            LabeledContent("Private SDK config", value: test.privateConfig ? "Present" : "Missing")
            LabeledContent("SDK account logged in", value: test.sdkAccountLoggedIn ? "Yes" : "No")
            LabeledContent("Exact scooter membership", value: test.sdkDeviceMembershipVerified && test.accountIdentityLeaseIsAuthorized ? "Verified for current account" : test.membershipBusy ? "Checking…" : "Not verified")
            Text(test.membershipStatus).font(.footnote).foregroundStyle(test.sdkDeviceMembershipVerified && test.accountIdentityLeaseIsAuthorized ? .green : .secondary)
            if test.sdkAccountLoggedIn && (!test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized) {
                Button(test.membershipBusy ? "Checking scooter membership…" : "Verify scooter in SDK account") { test.verifySDKMembership() }
                    .buttonStyle(.bordered)
                    .disabled(test.membershipBusy)
            }
            if !test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {
                Text("NO PHYSICAL BLE TEST YET: the private exact field build, current SDK account identity, and exact scooter membership must all be proven before OFF1 can start.")
                    .font(.footnote.bold())
                    .foregroundStyle(.orange)
            }
        }
        .card()
    }

    private var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Correlate this-session Bluetooth target", systemImage: "scope").font(.headline)
            Text("Authority requires one package-owned OFF1→ON1→OFF2→ON2 series and explicit confirmation. Each window uses a fresh CoreBluetooth manager. Name, RSSI, FD50, Tuya company ID, and the C7D09A22 UUID are non-authoritative hints only.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            switch test.phase {
            case .idle, .failed:
                Button("Start scooter-OFF baseline") { test.startBaseline() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)

            case .baseline, .scanning:
                Text("\(test.correlationWindowLabel) · \(test.correlationWindowInstruction)")
                    .font(.headline)
                LabeledContent("Fresh manager scan", value: test.correlationWindowIsScanning ? "Live" : "Starting…")
                LabeledContent("Completed windows", value: "\(test.correlationCompletedWindowCount) / 4")
                LabeledContent("Unique candidates this window", value: String(test.correlationObservedCandidateCount))
                Button("Seal \(test.correlationWindowLabel) window") { test.finishCorrelationWindow() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!test.correlationWindowIsScanning)

            case .powerOn:
                Text("Next: \(test.correlationWindowLabel) · \(test.correlationWindowInstruction)")
                    .foregroundStyle(.secondary)
                Button("Start \(test.correlationWindowLabel) window") { test.startNextCorrelationWindow() }
                    .buttonStyle(.borderedProminent)

            case .correlated:
                Text("Correlation found one repeatable full UUID. Confirm it only as this attempt's correlated Bluetooth target.")
                    .foregroundStyle(.secondary)
                Button("Confirm correlated Bluetooth target") { test.confirmCorrelatedTarget() }
                    .buttonStyle(.borderedProminent)

            default:
                EmptyView()
            }

            ForEach(test.candidates.prefix(8)) { candidate in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(candidate.title).bold()
                        if candidate.likely {
                            Text("FRESH CORRELATION")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green, in: Capsule())
                                .foregroundStyle(.black)
                        }
                        Spacer()
                    }
                    Text(candidate.id.uuidString)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(candidate.evidence.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    private func authenticationCard'''
app = sub_once(
    app,
    r"    private var authorityCard: some View \{.*?^    private func authenticationCard",
    ui,
    "field build and explicit correlation UI",
)
app = replace_once(
    app,
    "Export includes exact build identity, physical target ID, SDK membership state, canonical generation/chronology, local-BLE status, terminal state, and opaque application-value projections.",
    "Export includes exact build identity, current-session correlation windows/catalogs + operator-confirmation state, selected target ID, SDK membership state, canonical generation/chronology, local-BLE status, terminal state, and opaque application-value projections.",
    "export UI truth copy",
)

APP.write_text(app)

# Update prerequisite test: scanning authority now lives inside the accepted package producer.
go = GO.read_text()
go = sub_once(
    go,
    r'''        guard let baseline = app\.range\(of: "func startBaseline\(\)"\),.*?        #expect\(baselineLease\.lowerBound < baselineScan\.lowerBound\)''',
    '''        #expect(app.contains("PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)"))
        guard let baseline = app.range(of: "func startBaseline()"),
              let begin = app.range(of: "self.beginBaselineScan()", range: baseline.upperBound..<app.endIndex),
              let baselineLease = app.range(of: "TuyaSDKAccountIdentityLeaseGate.verdict", range: baseline.upperBound..<begin.lowerBound) else {
            Issue.record("OFF1 correlation must revalidate the account-bound membership lease before the package-owned producer starts.")
            return
        }
        #expect(baseline.lowerBound < baselineLease.lowerBound)
        #expect(baselineLease.lowerBound < begin.lowerBound)''',
    "same-account lease prerequisite contract",
)
GO.write_text(go)

# Refresh the older final-authority source contract to the stronger post-C7D09A22 target model.
final = FINAL.read_text()
final = sub_once(
    final,
    r'''        let begin = try section\(in: source, from: "private func beginBaselineScan\(\)", to: "func saveBaseline\(\)"\).*?        #expect\(begin\.contains\("scanForPeripherals"\)\)''',
    '''        let begin = try section(in: source, from: "private func beginBaselineScan()", to: "func startNextCorrelationWindow()")

        #expect(start.contains("guard privateConfig, sdkAccountLoggedIn"))
        #expect(start.contains("verifySDKMembership"))
        #expect(start.contains("beginBaselineScan()"))
        #expect(begin.contains("sdkAccountLoggedIn"))
        #expect(begin.contains("sdkDeviceMembershipVerified"))
        #expect(begin.contains("PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)"))
        #expect(begin.contains("startCurrentCorrelationWindow"))''',
    "final authority package scan producer contract",
)
final = sub_once(
    final,
    r'''    @Test\("only the accepted prior physical identity can authorize a local candidate"\).*?^    @Test\("login success re-reads SDK authority and account errors redact the submitted identifier"\)''',
    '''    @Test("only fresh repeated correlation plus explicit confirmation can authorize a local candidate")
    func descriptiveRadioHintsCannotAuthorizeTarget() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(source.contains("var likely: Bool { freshlyCorrelated }"))
        #expect(source.contains("historicalCapturePeripheral"))
        #expect(source.contains("matches C7D09A22 capture-local UUID descriptive"))
        #expect(source.contains("case let .singleRepeatableCandidate(id):"))
        #expect(source.contains("func confirmCorrelatedTarget"))
        #expect(source.contains("operator-confirmed-fresh-power-cycle-correlation"))
        #expect(!source.contains("var likely: Bool { knownID }"))
        #expect(!source.contains("accepted-prior-physical-corebluetooth-uuid"))
        #expect(!source.contains("fd50 && tuyaCompany"))
    }

    @Test("login success re-reads SDK authority and account errors redact the submitted identifier")''',
    "final authority target contract",
)
FINAL.write_text(final)

transport = TRANSPORT.read_text()
transport = replace_once(
    transport,
    '@Test("duplicate success callbacks share one local-BLE settlement owner and auth rejection retires authority")',
    '@Test("duplicate success callbacks share one local-BLE settlement owner and auth rejection retires chronology authority")',
    "transport test title",
)
transport = replace_once(
    transport,
    '''        guard let rejected = handler.range(of: "session_auth_callback_rejected") else {
            Issue.record("Authentication chronology rejection needs a terminal source-authority route.")
            return
        }
        let prefix = String(handler[..<rejected.lowerBound])
        #expect(prefix.contains("invalidateSourceAuthority"))
        #expect(!handler.contains("failLocally(\\"Authenticated-session chronology rejected"))''',
    '''        guard let rejected = handler.range(of: "session_auth_callback_rejected") else {
            Issue.record("Authentication chronology rejection needs a terminal chronology-integrity route.")
            return
        }
        let prefix = String(handler[..<rejected.lowerBound])
        #expect(prefix.contains("invalidateChronologyIntegrity"))
        #expect(app.contains("markChronologyIntegrityInvalidated"))
        #expect(!handler.contains("failLocally(\\"Authenticated-session chronology rejected"))''',
    "transport chronology terminal contract",
)
TRANSPORT.write_text(transport)

# Absorb the two live expected-red contracts into the product successor.
(TEST_DIR / "TuyaExplicitCorrelatedTargetConfirmationSourceTests.swift").write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture explicit correlated-target confirmation")
struct TuyaExplicitCorrelatedTargetConfirmationSourceTests {
    @Test("unique repeated correlation is offered for confirmation instead of auto-selected")
    func correlationResultCannotAutoSelectTarget() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let finish = try section(in: app, from: "private func finishCorrelationSeries", to: "func confirmCorrelatedTarget")
        #expect(finish.contains("singleRepeatableCandidate"))
        #expect(!finish.contains("selectedID = id"))
        #expect(!finish.contains("phase = .selected"))
        #expect(!finish.contains("candidate_selected"))
    }

    @Test("operator action is the only bridge from correlated candidate to selected target")
    func explicitOperatorConfirmationOwnsSelection() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let confirmation = try section(in: app, from: "func confirmCorrelatedTarget", to: "func invalidateSDKMembership")
        #expect(confirmation.contains("selectedID"))
        #expect(confirmation.contains("phase = .selected"))
        #expect(confirmation.contains("candidate_selected"))
        #expect(confirmation.contains("correlation"))
    }

    @Test("primary UI exposes explicit confirmation before authentication")
    func primaryUIRequiresConfirmation() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let card = try section(in: app, from: "private var discoveryCard: some View", to: "private func authenticationCard")
        #expect(card.contains("confirmCorrelatedTarget"))
        #expect(card.localizedCaseInsensitiveContains("confirm"))
        #expect(card.localizedCaseInsensitiveContains("correlat"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
    private enum SourceContractError: Error { case sectionMissing }
}
''')

(TEST_DIR / "TuyaFieldBuildPresentationAuthoritySourceTests.swift").write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field-build presentation authority")
struct TuyaFieldBuildPresentationAuthoritySourceTests {
    @Test("field-build row is backed by compiled build provenance, not Tuya account authority")
    func fieldBuildRowUsesBuildIdentityAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("var fieldBuildIsAuthoritative: Bool"))
        #expect(app.contains("buildIdentity.isAuthoritativeFieldBuild"))
        let card = try section(in: app, from: "private var authorityCard: some View", to: "private var discoveryCard: some View")
        #expect(card.contains("LabeledContent(\"Field build\""))
        #expect(card.contains("test.fieldBuildIsAuthoritative"))
        #expect(card.contains("!test.fieldBuildIsAuthoritative"))
    }

    @Test("OFF-baseline affordance fails closed on non-authoritative build provenance")
    func physicalAffordanceConsumesBuildAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let card = try section(in: app, from: "private var discoveryCard: some View", to: "private func authenticationCard")
        #expect(card.contains("Button(\"Start scooter-OFF baseline\")"))
        #expect(card.contains("!test.fieldBuildIsAuthoritative"))
        let start = try section(in: app, from: "func startBaseline()", to: "private func beginBaselineScan")
        #expect(start.contains("buildIdentity.isAuthoritativeFieldBuild"))
        #expect(start.contains("field_build_identity_unavailable"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }
    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
    private enum SourceContractError: Error { case sectionMissing }
}
''')

(TEST_DIR / "TuyaFreshTargetAndAcquisitionTerminalSourceTests.swift").write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture fresh target, export provenance, and terminal truth")
struct TuyaFreshTargetAndAcquisitionTerminalSourceTests {
    @Test("historical capture UUID is descriptive while fresh four-window evidence is exported")
    func freshCorrelationOwnsTargetAuthorityAndArtifactProvenance() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("var likely: Bool { freshlyCorrelated }"))
        #expect(app.contains("historicalCapturePeripheral"))
        #expect(app.contains("PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)"))
        #expect(app.contains("targetCorrelation: CorrelationExport?"))
        #expect(app.contains("observationSeriesIdentity"))
        #expect(app.contains("windowSequence"))
        #expect(app.contains("isConnectable"))
        #expect(app.contains("operatorConfirmed"))
        #expect(!app.contains("accepted-prior-physical-corebluetooth-uuid"))
    }

    @Test("local settlement timeout and invalid clock remain distinct from source authority loss")
    func acquisitionTerminalReasonsStayDistinct() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let handler = try section(in: app, from: "private func authenticated(token:", to: "private func authenticationFailed")
        let timeout = try section(in: String(handler), from: "case .timedOut:", to: "case .invalidClock:")
        #expect(timeout.contains("authenticationAcquisitionFailed"))
        #expect(!timeout.contains("invalidateSourceAuthority"))
        let invalid = String(handler[handler.range(of: "case .invalidClock:")!.lowerBound...])
        #expect(invalid.contains("invalidateChronologyIntegrity"))
        #expect(!invalid.contains("invalidateSourceAuthority"))
        #expect(app.contains("sessionLedger.markChronologyIntegrityInvalidated(for: token)"))
        #expect(app.contains("localBLESettlementToken"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }
    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
    private enum SourceContractError: Error { case sectionMissing }
}
''')

# Mechanical postconditions before committing any product bytes.
final_app = APP.read_text()
for forbidden in (
    "var likely: Bool { knownID }",
    "accepted prior physical UUID matched",
    "accepted-prior-physical-corebluetooth-uuid",
):
    if forbidden in final_app:
        raise SystemExit(f"stale target authority remains: {forbidden}")
for required in (
    "PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)",
    "func confirmCorrelatedTarget()",
    "operator-confirmed-fresh-power-cycle-correlation",
    "targetCorrelation: CorrelationExport?",
    "var fieldBuildIsAuthoritative: Bool",
    "sessionLedger.markChronologyIntegrityInvalidated(for: token)",
    "private var localBLESettlementToken: TuyaReadOnlyConnectionToken?",
):
    if required not in final_app:
        raise SystemExit(f"required final authority marker missing: {required}")

print("V14 final Capture target-authority composition applied")
