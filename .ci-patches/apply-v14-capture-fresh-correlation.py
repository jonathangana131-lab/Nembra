from pathlib import Path
import re

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldGoPrerequisiteSourceTests.swift")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one literal match, found {count}")
    return text.replace(old, new, 1)


def sub_once(text: str, pattern: str, replacement: str, label: str) -> str:
    compiled = re.compile(pattern, re.MULTILINE | re.DOTALL)
    matches = list(compiled.finditer(text))
    if len(matches) != 1:
        raise SystemExit(f"{label}: expected exactly one regex match, found {len(matches)}")
    return compiled.sub(lambda _: replacement, text, count=1)


app = APP.read_text()

app = replace_once(
    app,
    "The next physical run is stationary. It proves current SDK account authority, exact scooter membership, the accepted physical Bluetooth target, Tuya-owned authentication, genuine same-generation application updates, and a sealed 45-second observation prefix.",
    "The next physical run is stationary. It proves current SDK account authority, exact scooter membership, a fresh repeated OFF1→ON1→OFF2→ON2 Bluetooth correlation, Tuya-owned authentication, genuine same-generation application updates, and a sealed 45-second observation prefix.",
    "root physical-target copy",
)

candidate_block = '''    struct Candidate: Identifiable, Codable, Equatable {
        let id: UUID
        var name: String?
        var rssi: Int?
        var advertisements: Int?
        var newAfterPowerOn: Bool
        var fd50: Bool
        var tuyaCompany: Bool
        var historicalCaptureID: Bool
        var freshlyCorrelated: Bool
        var expectedName: Bool
        var score: Int
        var evidence: [String]

        var title: String { name?.isEmpty == false ? name! : "Correlated Bluetooth target" }
        // Current target authority is earned only by the package-owned repeated
        // OFF1→ON1→OFF2→ON2 correlation series. A historical capture UUID may
        // remain descriptive evidence but never mints current-session authority.
        var likely: Bool { freshlyCorrelated }
    }

    enum Phase'''
app = sub_once(
    app,
    r"    struct Candidate: Identifiable, Codable, Equatable \{.*?^    \}\n\n    enum Phase",
    candidate_block,
    "Candidate authority model",
)

app = replace_once(
    app,
    '    static let knownPeripheral = UUID(uuidString: "6815A5F5-4D1E-E004-BAE8-6DF924123907")!',
    '    static let historicalCapturePeripheral = UUID(uuidString: "6815A5F5-4D1E-E004-BAE8-6DF924123907")!',
    "historical capture UUID label",
)

app = replace_once(
    app,
    "    private var baseline = Set<UUID>()\n    private var driver: OfficialTuyaDriver?",
    "    private var baseline = Set<UUID>()\n    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?\n    private var driver: OfficialTuyaDriver?",
    "correlation session storage",
)

computed = '''    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }
    var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }
    var correlationWindowIsScanning: Bool { correlationProgress?.isScanning == true }
    var correlationObservedCandidateCount: Int { correlationProgress?.currentObservedCandidateCount ?? 0 }
    var correlationCompletedWindowCount: Int { correlationProgress?.completedWindowCount ?? 0 }

    var correlationWindowLabel: String {
        guard let phase = correlationProgress?.phase else { return "OFF1" }
        switch phase {
        case .firstPoweredOff: return "OFF1"
        case .firstPoweredOn: return "ON1"
        case .secondPoweredOff: return "OFF2"
        case .secondPoweredOn: return "ON2"
        }
    }

    var correlationWindowInstruction: String {
        guard let phase = correlationProgress?.phase else { return "Keep the scooter OFF and stationary." }
        return phase.operatorExpectedPowerOn
            ? "Turn the scooter ON and keep it stationary."
            : "Turn the scooter OFF and keep it stationary."
    }'''
app = replace_once(
    app,
    "    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }",
    computed,
    "correlation UI projections",
)

correlation_methods = '''    func startBaseline() {
        guard buildIdentity.isAuthoritativeFieldBuild else {
            failLocally(buildIdentity.blocker ?? "Exact field-build provenance is unavailable.", "field_build_identity_unavailable")
            return
        }
        guard privateConfig, sdkAccountLoggedIn else {
            failLocally("Private Tuya app identity and a current SDK login are required before any scooter correlation scan.", "sdk_authority_required_before_scan")
            return
        }

        // Every physical attempt receives a fresh complete current-account membership verdict
        // before the package-owned four-window Bluetooth correlation series may start.
        verifySDKMembership { [weak self] authorized in
            guard let self else { return }
            let leaseVerdict = TuyaSDKAccountIdentityLeaseGate.verdict(for: self.accountIdentityLeaseSnapshot)
            guard authorized,
                  self.sdkAccountLoggedIn,
                  leaseVerdict == .authorized else {
                self.failLocally("Exact scooter membership could not be proven for this same current SDK account. Bluetooth correlation remains disabled.", "sdk_device_membership_required_before_scan")
                return
            }
            self.beginCorrelationSeries()
        }
    }

    private func beginCorrelationSeries() {
        guard privateConfig,
              sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            failLocally("SDK account/device authority changed before Bluetooth correlation began.", "sdk_authority_changed_before_scan")
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

        let label = correlationWindowLabel
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
                advertisements: nil,
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
            selectedID = id
            correlationSession = nil
            phase = .selected
            message = "Fresh repeated power-cycle correlation found one full CoreBluetooth target. This is current-session correlation evidence, not permanent scooter identity. Discovery is retired before Tuya's SDK takes BLE ownership."
            log("candidate_selected", [
                "id": id.uuidString,
                "authority": "fresh-repeated-off-on-full-corebluetooth-id",
                "historicalCaptureUUIDMatch": String(historicalCaptureID),
                "windows": String(result.windows.count)
            ])

        case let .ambiguousRepeatableCandidates(ids):
            correlationSession = nil
            failLocally("Fresh correlation remained ambiguous across \(ids.count) repeatable full UUIDs. Do not guess from name, RSSI, FD50, or Tuya hints; restart from OFF1 after reducing nearby-device ambiguity.", "target_correlation_ambiguous")

        case .noRepeatableCandidate:
            correlationSession = nil
            failLocally("No full UUID repeated the required OFF1→ON1→OFF2→ON2 pattern. Do not fall back to the historical capture UUID; restart the fresh correlation series.", "target_correlation_no_repeatable_candidate")

        case .invalidObservationAuthority, .invalidObservationWindowOrder:
            correlationSession = nil
            failLocally("The package rejected correlation provenance/chronology. Restart from OFF1; prior windows cannot be spliced into a new attempt.", "target_correlation_provenance_rejected")
        }
    }

    func invalidateSDKMembership() {'''
app = sub_once(
    app,
    r"    func startBaseline\(\) \{.*?^    func invalidateSDKMembership\(\) \{",
    correlation_methods,
    "replace stale one-cycle/fixed-UUID discovery flow",
)

app = replace_once(
    app,
    "        membershipDeviceID = nil\n        membershipStatus = \"Official SDK login changed. Exact scooter membership must be verified again.\"",
    "        membershipDeviceID = nil\n        if phase == .baseline || phase == .powerOn || phase == .scanning {\n            correlationSession?.abandonCurrentWindow()\n            correlationSession = nil\n        }\n        membershipStatus = \"Official SDK login changed. Exact scooter membership must be verified again.\"",
    "invalidate active correlation on account loss",
)

app = replace_once(
    app,
    '            failLocally("The accepted prior physical scooter identity is required.", "candidate_not_authoritative")',
    '            failLocally("A fresh repeated OFF1→ON1→OFF2→ON2 Bluetooth correlation is required before Tuya BLE ownership.", "candidate_not_authoritative")',
    "authentication target blocker copy",
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
                await authenticationAcquisitionFailed(
                    token: token,
                    message: "Local-BLE settlement failed closed because the monotonic clock regressed.",
                    kind: "sdk_local_ble_settlement_clock_invalid"
                )
                return''',
    "separate local acquisition failure from source-authority terminal",
)

auth_failure_block = '''    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async {
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
        try? await sessionLedger.markAuthenticationFailed(for: token)
        currentConnectionToken = nil
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
    auth_failure_block,
    "authentication acquisition terminal helper",
)

app = replace_once(
    app,
    "    private func resetDiscoverySessionOnly() {\n        central.stopScan()",
    "    private func resetDiscoverySessionOnly() {\n        correlationSession?.abandonCurrentWindow()\n        correlationSession = nil\n        central.stopScan()",
    "reset correlation authority",
)

app = replace_once(
    app,
    "    private func failLocally(_ text: String, _ kind: String) {\n        watchdog?.cancel()",
    "    private func failLocally(_ text: String, _ kind: String) {\n        if phase == .baseline || phase == .powerOn || phase == .scanning {\n            correlationSession?.abandonCurrentWindow()\n            correlationSession = nil\n        }\n        watchdog?.cancel()",
    "fail-closed correlation abandonment",
)

app = replace_once(
    app,
    "        let knownID = id == Self.knownPeripheral",
    "        let historicalCaptureID = id == Self.historicalCapturePeripheral",
    "descriptive historical ID calculation",
)
app = replace_once(
    app,
    '        if knownID { score += 1000; evidence.append("accepted prior physical UUID") }',
    '        if historicalCaptureID { evidence.append("matches C7D09A22 capture-local UUID descriptive") }',
    "remove historical UUID authority score",
)
app = replace_once(
    app,
    "            knownID: knownID,\n            expectedName: expectedName,",
    "            historicalCaptureID: historicalCaptureID,\n            freshlyCorrelated: false,\n            expectedName: expectedName,",
    "descriptive candidate cannot mint correlation",
)

app = replace_once(
    app,
    '                    Text("Authenticate. Wait. Seal.").font(.largeTitle.bold())',
    '                    Text("Correlate. Authenticate. Seal.").font(.largeTitle.bold())',
    "secure-link headline",
)

discovery_view = '''    private var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Correlate this-session Bluetooth target", systemImage: "scope").font(.headline)
            Text("Authority requires one package-owned OFF1→ON1→OFF2→ON2 series. Each window uses a fresh CoreBluetooth manager. Name, RSSI, FD50, Tuya company ID, and the C7D09A22 UUID are non-authoritative hints only.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            switch test.phase {
            case .idle, .failed:
                Button("Start OFF1 correlation") { test.startBaseline() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)

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
    r"    private var discoveryCard: some View \{.*?^    private func authenticationCard",
    discovery_view,
    "fresh correlation product flow",
)

app = replace_once(
    app,
    "Export includes exact build identity, physical target ID, SDK membership state, canonical generation/chronology, local-BLE status, terminal state, and opaque application-value projections.",
    "Export includes exact build identity, current-session correlated target ID, SDK membership state, canonical generation/chronology, local-BLE status, terminal state, and opaque application-value projections.",
    "export target wording",
)

APP.write_text(app)

source_test = TEST.read_text()
replacement_test = '''    @Test("membership proof is leased to the same current Tuya account UID")
    func accountIdentityLeaseIsRevalidated() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("TuyaSDKAccountIdentityLeaseGate.verdict"))
        #expect(app.contains("currentAccountUID"))
        #expect(app.contains("membershipAccountUID"))
        #expect(app.contains("membershipDeviceID"))
        #expect(app.contains("ThingSmartUser.sharedInstance()?.uid"))
        #expect(app.contains("PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)"))

        guard let baseline = app.range(of: "func startBaseline()"),
              let correlationStart = app.range(of: "self.beginCorrelationSeries()", range: baseline.upperBound..<app.endIndex),
              let baselineLease = app.range(of: "TuyaSDKAccountIdentityLeaseGate.verdict", range: baseline.upperBound..<correlationStart.lowerBound) else {
            Issue.record("OFF1 correlation must revalidate the account-bound membership lease before the package-owned correlation series starts.")
            return
        }
        #expect(baseline.lowerBound < baselineLease.lowerBound)
        #expect(baselineLease.lowerBound < correlationStart.lowerBound)
    }

    @Test("account authority loss has a dedicated terminal instead of masquerading as continuity or disconnect")'''
source_test = sub_once(
    source_test,
    r'''    @Test\("membership proof is leased to the same current Tuya account UID"\).*?^    @Test\("account authority loss has a dedicated terminal instead of masquerading as continuity or disconnect"\)''',
    replacement_test,
    "update same-account source contract for package-owned correlation",
)
TEST.write_text(source_test)

# Mechanical postconditions: fail rather than leave an authority regression hidden in a green patch job.
final_app = APP.read_text()
for forbidden in (
    "var likely: Bool { knownID }",
    "accepted prior physical UUID matched",
    "accepted-prior-physical-corebluetooth-uuid",
):
    if forbidden in final_app:
        raise SystemExit(f"forbidden stale authority text remains: {forbidden}")

for required in (
    "PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)",
    "fresh-repeated-off-on-full-corebluetooth-id",
    "authenticationAcquisitionFailed(",
    "FRESH CORRELATION",
):
    if required not in final_app:
        raise SystemExit(f"required repaired authority marker missing: {required}")

print("V14 Capture fresh-correlation repair applied deterministically")
