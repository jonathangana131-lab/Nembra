from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
s = path.read_text()

def once(old: str, new: str) -> None:
    global s
    n = s.count(old)
    if n != 1:
        raise SystemExit(f"expected one anchor, found {n}: {old[:140]!r}")
    s = s.replace(old, new, 1)

# Publish package-owned correlation progress into ObservableObject state. The
# copied snapshot is presentation-only and cannot mint target/receipt authority.
once(
    "    @Published private(set) var pendingCorrelatedTargetID: UUID?\n",
    "    @Published private(set) var pendingCorrelatedTargetID: UUID?\n    @Published private(set) var correlationProgress: PassiveBluetoothPowerCycleObservationProgress?\n",
)
once(
    "    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?\n",
    "    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?\n    private var correlationProgressTask: Task<Void, Never>?\n",
)
once("    var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }\n", "")
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

# Expose exact compiled field provenance independently from Tuya account state,
# and gate the OFF1 affordance with the same truth as the runtime start guard.
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

# Retire the obsolete app-owned CoreBluetooth scanner. Fresh OFF/ON correlation
# is already solely owned by PassiveBluetoothPowerCycleObservationSession.
once("@preconcurrency import CoreBluetooth\n", "")
once("let CBAdvertisementDataIsConnectableKey = CBAdvertisementDataIsConnectable\n\n", "")
once("    static let fd50 = CBUUID(string: \"FD50\")\n", "")
once("    private var central: CBCentralManager!\n", "")
once("    private var baseline = Set<UUID>()\n", "")
once("        central = CBCentralManager(delegate: self, queue: .main)\n", "")
s = s.replace("        central.stopScan()\n", "")
once("        baseline.removeAll()\n", "")
legacy_start = s.index("    private static func hasTuyaCompanyID")
ext_marker = "\nextension SecureLinkController: @preconcurrency CBCentralManagerDelegate"
legacy_end = s.index(ext_marker, legacy_start)
s = s[:legacy_start] + "}\n" + s[legacy_end:]
ext_start = s.index("extension SecureLinkController: @preconcurrency CBCentralManagerDelegate")
ext_end = s.index("\n\n@MainActor\nprivate protocol OfficialTuyaDriver", ext_start)
s = s[:ext_start] + s[ext_end + 2:]

path.write_text(s)
