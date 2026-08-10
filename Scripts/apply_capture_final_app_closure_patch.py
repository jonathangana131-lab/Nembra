from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
s = path.read_text()


def once(old: str, new: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"expected one anchor, found {count}: {old[:140]!r}")
    s = s.replace(old, new, 1)

# Single discovery owner: package correlation session is authoritative; retire
# the obsolete app-owned CBCentralManager / advertisement-hint scanner.
once("@preconcurrency import CoreBluetooth\n", "")
once("let CBAdvertisementDataIsConnectableKey = CBAdvertisementDataIsConnectable\n\n", "")
once("    static let fd50 = CBUUID(string: \"FD50\")\n", "")
once("    private var central: CBCentralManager!\n", "")
once("    private var baseline = Set<UUID>()\n", "")
once("        central = CBCentralManager(delegate: self, queue: .main)\n", "")
s = s.replace("        central.stopScan()\n", "")
once("        baseline.removeAll()\n", "")
legacy_start = s.index("    private static func hasTuyaCompanyID")
legacy_end = s.index("\n}\n\nextension SecureLinkController:", legacy_start)
s = s[:legacy_start] + s[legacy_end + 1:]
ext_start = s.index("extension SecureLinkController:")
ext_end = s.index("\n\n@MainActor\nprivate protocol OfficialTuyaDriver", ext_start)
s = s[:ext_start] + s[ext_end + 2:]

# Explicit operator confirmation is a separate authority rung after a unique
# current-session package correlation result.
once(
    "case idle, baseline, powerOn, scanning, selected, authenticating, observing, accepted, failed",
    "case idle, baseline, powerOn, scanning, correlated, selected, authenticating, observing, accepted, failed",
)
once(
    "@Published private(set) var selectedID: UUID?\n",
    "@Published private(set) var selectedID: UUID?\n    @Published private(set) var pendingCorrelatedTargetID: UUID?\n",
)
finish_anchor = "    private func finishCorrelationSeries(_ result: PassiveBluetoothPowerCycleObservationResult) {"
confirmation = '''    func confirmCorrelatedTarget() {
        guard phase == .correlated,
              let id = pendingCorrelatedTargetID,
              let candidate = byID[id],
              candidate.likely else {
            failLocally("A current-session correlated Bluetooth target is not awaiting confirmation.", "correlated_target_confirmation_unavailable")
            return
        }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            pendingCorrelatedTargetID = nil
            failLocally("Tuya account/device authority changed before correlated-target confirmation. Restart correlation after re-verifying membership.", "sdk_authority_changed_before_target_confirmation")
            return
        }
        guard currentConnectionToken == nil else {
            pendingCorrelatedTargetID = nil
            failLocally("An authenticated generation already owns session authority. Relaunch Capture before confirming another target.", "active_generation_blocks_target_confirmation")
            return
        }

        selectedID = id
        pendingCorrelatedTargetID = nil
        targetCorrelationOperatorConfirmed = true
        phase = .selected
        message = "Correlated Bluetooth target confirmed for this attempt. This is current-session correlation evidence, not permanent scooter identity. Tuya SDK membership remains the separate authentication authority."
        log("candidate_selected", [
            "id": candidate.id.uuidString,
            "authority": "explicit-operator-confirmation-of-current-session-correlation",
            "historicalCaptureUUIDMatch": String(candidate.historicalCaptureID)
        ])
    }

'''
once(finish_anchor, confirmation + finish_anchor)
once(
'''            byID = [id: candidate]
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
''',
'''            byID = [id: candidate]
            candidates = [candidate]
            pendingCorrelatedTargetID = id
            correlationSession = nil
            phase = .correlated
            message = "Fresh repeated power-cycle correlation found one full CoreBluetooth target. Confirm that correlated target before Tuya authentication. Correlation evidence is current-session only and is not permanent scooter identity."
            log("candidate_correlated", [
                "id": id.uuidString,
                "authority": "fresh-repeated-off-on-full-corebluetooth-id-awaiting-operator-confirmation",
                "historicalCaptureUUIDMatch": String(historicalCaptureID),
                "windows": String(result.windows.count)
            ])
''')
once(
    'if phase == .baseline || phase == .powerOn || phase == .scanning {\n            correlationSession?.abandonCurrentWindow()\n            correlationSession = nil\n        }\n        membershipStatus = "Official SDK login changed.',
    'if phase == .baseline || phase == .powerOn || phase == .scanning {\n            correlationSession?.abandonCurrentWindow()\n            correlationSession = nil\n        }\n        pendingCorrelatedTargetID = nil\n        membershipStatus = "Official SDK login changed.',
)
once(
    "if [.baseline, .powerOn, .scanning, .selected].contains(phase) {",
    "if [.baseline, .powerOn, .scanning, .correlated, .selected].contains(phase) {",
)
once(
    "        selectedID = nil\n        sdkLocalBLEOnline = false\n",
    "        selectedID = nil\n        pendingCorrelatedTargetID = nil\n        sdkLocalBLEOnline = false\n",
)

# Publish package-owned scan readiness/progress into SwiftUI. This task copies
# presentation state only; it never creates correlation receipts or authority.
once(
    "    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?\n",
    "    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?\n    private var correlationProgressTask: Task<Void, Never>?\n",
)
once(
    "    @Published private(set) var selectedID: UUID?\n    @Published private(set) var pendingCorrelatedTargetID: UUID?\n",
    "    @Published private(set) var selectedID: UUID?\n    @Published private(set) var pendingCorrelatedTargetID: UUID?\n    @Published private(set) var correlationProgress: PassiveBluetoothPowerCycleObservationProgress?\n",
)
once(
    "    var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }\n",
    "",
)
once(
'''            try session.startCurrentWindow()
            phase = progress.phase.operatorExpectedPowerOn ? .scanning : .baseline
''',
'''            try session.startCurrentWindow()
            startCorrelationProgressObservation(session: session)
            phase = progress.phase.operatorExpectedPowerOn ? .scanning : .baseline
''')
observer = '''    private func startCorrelationProgressObservation(session: PassiveBluetoothPowerCycleObservationSession) {
        stopCorrelationProgressObservation()
        correlationProgress = session.progress
        correlationProgressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.correlationSession != nil else { return }
                if let progress = session.progress {
                    self.correlationProgress = progress
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func stopCorrelationProgressObservation() {
        correlationProgressTask?.cancel()
        correlationProgressTask = nil
    }

'''
once("    func finishCorrelationWindow() {", observer + "    func finishCorrelationWindow() {")
once(
'''            let final = try session.finishCurrentWindow()
            if let final {
''',
'''            let final = try session.finishCurrentWindow()
            stopCorrelationProgressObservation()
            correlationProgress = session.progress
            if let final {
''')
once(
'''            default:
                session.abandonCurrentWindow()
                correlationSession = nil
''',
'''            default:
                stopCorrelationProgressObservation()
                session.abandonCurrentWindow()
                correlationSession = nil
''')
once(
'''        } catch {
            session.abandonCurrentWindow()
            correlationSession = nil
            failLocally("\\(sealedLabel) failed closed: \\(error.localizedDescription). Restart the complete correlation series.", "target_correlation_window_failed")
''',
'''        } catch {
            stopCorrelationProgressObservation()
            session.abandonCurrentWindow()
            correlationSession = nil
            failLocally("\\(sealedLabel) failed closed: \\(error.localizedDescription). Restart the complete correlation series.", "target_correlation_window_failed")
''')
once(
'''    private func resetDiscoverySessionOnly() {
        correlationSession?.abandonCurrentWindow()
        correlationSession = nil
''',
'''    private func resetDiscoverySessionOnly() {
        stopCorrelationProgressObservation()
        correlationSession?.abandonCurrentWindow()
        correlationSession = nil
        correlationProgress = nil
''')

# Field-build provenance must be app-visible and must gate the OFF1 affordance,
# matching the existing runtime build guard.
once(
'''    var accountIdentityLeaseIsAuthorized: Bool {
        TuyaSDKAccountIdentityLeaseGate.verdict(for: accountIdentityLeaseSnapshot) == .authorized
    }
''',
'''    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }

    var accountIdentityLeaseIsAuthorized: Bool {
        TuyaSDKAccountIdentityLeaseGate.verdict(for: accountIdentityLeaseSnapshot) == .authorized
    }
''')
once(
    '            LabeledContent("Field build", value: test.accountIdentityLeaseIsAuthorized && test.sdkDeviceMembershipVerified ? "Authority checked" : "Not ready")',
    '            LabeledContent("Field build", value: test.fieldBuildIsAuthoritative ? "Exact provenance" : "Not authoritative")',
)
once(
'''            if !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {
                Text("NO PHYSICAL BLE TEST YET: the private exact field build, current SDK account identity, and exact scooter membership must all be proven before even the OFF baseline scan can start.")
''',
'''            if !test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {
                Text("NO PHYSICAL BLE TEST YET: exact compiled field-build provenance, private SDK configuration, current SDK account identity, and exact scooter membership must all be proven before OFF1 correlation can start.")
''')
once(
'''                    .disabled(!test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)
''',
'''                    .disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)
''')

# Correlated is an app-visible confirmation state.
once(
'''            case .powerOn:
                Text("Next: \\(test.correlationWindowLabel) · \\(test.correlationWindowInstruction)")
                    .foregroundStyle(.secondary)
                Button("Start \\(test.correlationWindowLabel) window") { test.startNextCorrelationWindow() }
                    .buttonStyle(.borderedProminent)

            default:
''',
'''            case .powerOn:
                Text("Next: \\(test.correlationWindowLabel) · \\(test.correlationWindowInstruction)")
                    .foregroundStyle(.secondary)
                Button("Start \\(test.correlationWindowLabel) window") { test.startNextCorrelationWindow() }
                    .buttonStyle(.borderedProminent)

            case .correlated:
                Text("One full CoreBluetooth target repeated across the required OFF1→ON1→OFF2→ON2 series. Confirm it for this attempt before Tuya authentication.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Confirm correlated Bluetooth target") { test.confirmCorrelatedTarget() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)

            default:
''')

path.write_text(s)
