from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text()


def replace_once(old: str, new: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one occurrence, found {count}: {old[:80]!r}")
    source = source.replace(old, new, 1)


def replace_between(start: str, end: str, replacement: str) -> None:
    global source
    start_index = source.find(start)
    if start_index < 0:
        raise SystemExit(f"start marker not found: {start}")
    end_index = source.find(end, start_index)
    if end_index < 0:
        raise SystemExit(f"end marker not found: {end}")
    source = source[:start_index] + replacement + source[end_index:]


replace_once(
'''        var knownID: Bool
        var expectedName: Bool
        var score: Int
        var evidence: [String]

        var title: String { name?.isEmpty == false ? name! : "Unnamed peripheral" }
        // C7D09A22 physically established this iPhone/CoreBluetooth peripheral UUID.
        // Other hints can rank display order but cannot mint target authority.
        var likely: Bool { knownID }
''',
'''        var correlated: Bool
        var expectedName: Bool
        var score: Int
        var evidence: [String]

        var title: String { name?.isEmpty == false ? name! : "Unnamed peripheral" }
        // Authority is earned only by the repeated OFF1→ON1→OFF2→ON2 contract.
        // Descriptive hints never mint target authority.
        var likely: Bool { correlated }
'''
)

replace_once(
'''    enum Phase: String, Codable {
        case idle, baseline, powerOn, scanning, selected, authenticating, observing, accepted, failed
    }
''',
'''    enum Phase: String, Codable {
        case idle, baseline, powerOn, scanning, correlated, selected, authenticating, observing, accepted, failed
    }

    private enum CorrelationLeg {
        case off1, on1, off2, on2
    }
'''
)

replace_once(
'''    static let knownPeripheral = UUID(uuidString: "6815A5F5-4D1E-E004-BAE8-6DF924123907")!
    static let fd50 = CBUUID(string: "FD50")
''',
'''    static let fd50 = CBUUID(string: "FD50")
'''
)

replace_once(
'''    private var central: CBCentralManager!
    private var byID: [UUID: Candidate] = [:]
    private var baseline = Set<UUID>()
    private var driver: OfficialTuyaDriver?
''',
'''    private var central: CBCentralManager!
    private var byID: [UUID: Candidate] = [:]
    private var off1 = Set<UUID>()
    private var on1 = Set<UUID>()
    private var off2 = Set<UUID>()
    private var on2 = Set<UUID>()
    private var currentScanIDs = Set<UUID>()
    private var correlationLeg: CorrelationLeg = .off1
    private var driver: OfficialTuyaDriver?
'''
)

replace_once(
'''    var selected: Candidate? { selectedID.flatMap { byID[$0] } }
    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }
''',
'''    var selected: Candidate? { selectedID.flatMap { byID[$0] } }
    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }
    var waitingForSecondOffScan: Bool { phase == .powerOn && correlationLeg == .off2 }
    var isSecondCorrelationPass: Bool { correlationLeg == .off2 || correlationLeg == .on2 }
'''
)

replace_between(
'    private func beginBaselineScan() {',
'    func invalidateSDKMembership() {',
'''    private func beginBaselineScan() {
        guard central.state == .poweredOn,
              privateConfig,
              sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            failLocally("SDK account/device authority changed before discovery began.", "sdk_authority_changed_before_scan")
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
        correlationLeg = .off1
        currentScanIDs.removeAll()
        phase = .baseline
        message = "Pass 1 of 2: keep the scooter OFF for a few seconds. This records only capture-local CoreBluetooth presence."
        log("correlation_off1_started_after_membership")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func saveBaseline() {
        guard phase == .baseline else { return }
        guard sdkAccountLoggedIn, sdkDeviceMembershipVerified, accountIdentityLeaseIsAuthorized else {
            failLocally("SDK account/device authority changed during the OFF baseline.", "sdk_authority_changed_during_baseline")
            return
        }
        central.stopScan()

        switch correlationLeg {
        case .off1:
            off1 = currentScanIDs
            currentScanIDs.removeAll()
            correlationLeg = .on1
            phase = .powerOn
            message = "OFF pass 1 saved. Turn the scooter ON, keep it stationary, then scan ON pass 1."
            log("correlation_off1_saved", ["count": String(off1.count)])
        case .off2:
            off2 = currentScanIDs
            currentScanIDs.removeAll()
            correlationLeg = .on2
            phase = .powerOn
            message = "OFF pass 2 saved. Turn the scooter ON again, keep it stationary, then scan ON pass 2."
            log("correlation_off2_saved", ["count": String(off2.count)])
        default:
            failLocally("OFF-baseline chronology was invalid. Restart the correlation sequence.", "correlation_off_chronology_invalid")
        }
    }

    func scanSecondOff() {
        guard phase == .powerOn, correlationLeg == .off2 else { return }
        guard central.state == .poweredOn,
              sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            failLocally("Authority changed before OFF pass 2.", "sdk_authority_changed_before_off2")
            return
        }
        currentScanIDs.removeAll()
        phase = .baseline
        message = "Pass 2 of 2: keep the scooter OFF for a few seconds, then save the second OFF baseline."
        log("correlation_off2_started")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func scanAfterPowerOn() {
        guard central.state == .poweredOn else {
            failLocally("Bluetooth is not ready.", "bluetooth_unavailable")
            return
        }
        guard sdkAccountLoggedIn, sdkDeviceMembershipVerified, accountIdentityLeaseIsAuthorized else {
            failLocally("SDK account/device authority changed before the power-on scan.", "sdk_authority_changed_before_power_on_scan")
            return
        }
        guard phase == .powerOn, correlationLeg == .on1 || correlationLeg == .on2 else {
            failLocally("ON-scan chronology was invalid. Restart the correlation sequence.", "correlation_on_chronology_invalid")
            return
        }
        currentScanIDs.removeAll()
        phase = .scanning
        let pass = correlationLeg == .on2 ? 2 : 1
        message = "Scanning ON pass \(pass). Full CoreBluetooth UUID transitions are authority; FD50, Tuya company ID, name, and RSSI remain descriptive only."
        log("correlation_on_scan_started", ["pass": String(pass)])
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopScan() {
        guard phase == .scanning else { return }
        central.stopScan()

        switch correlationLeg {
        case .on1:
            on1 = currentScanIDs
            currentScanIDs.removeAll()
            switch PeripheralPowerCycleCorrelation.resolveTransition(off: off1, on: on1) {
            case .missing:
                failLocally("Pass 1 found no unique peripheral that appeared only after power-on. Restart; do not guess from descriptive hints.", "correlation_pass1_missing")
            case .ambiguous:
                failLocally("Pass 1 found multiple newly appearing peripherals. Restart in a quieter Bluetooth environment; do not break the tie with name, RSSI, or services.", "correlation_pass1_ambiguous")
            case let .unique(id):
                guard byID[id] != nil else {
                    failLocally("Pass 1 correlation referenced a peripheral no longer present in the capture ledger.", "correlation_pass1_candidate_missing")
                    return
                }
                correlationLeg = .off2
                phase = .powerOn
                message = "Pass 1 isolated one capture-local candidate. Turn the scooter OFF again, wait for it to disappear, then start OFF pass 2."
                log("correlation_pass1_unique", ["captureLocalPeripheralID": id.uuidString])
            }

        case .on2:
            on2 = currentScanIDs
            currentScanIDs.removeAll()
            switch PeripheralPowerCycleCorrelation.resolveRepeated(
                off1: off1,
                on1: on1,
                off2: off2,
                on2: on2
            ) {
            case .missingFirst:
                failLocally("Pass 1 no longer resolves to one unique OFF→ON appearance. Restart the correlation sequence.", "correlation_repeat_missing_first")
            case .ambiguousFirst:
                failLocally("Pass 1 is ambiguous. Restart; descriptive hints cannot break the tie.", "correlation_repeat_ambiguous_first")
            case .missingSecond:
                failLocally("Pass 2 found no unique peripheral that appeared only after power-on. Restart the correlation sequence.", "correlation_repeat_missing_second")
            case .ambiguousSecond:
                failLocally("Pass 2 found multiple newly appearing peripherals. Restart in a quieter Bluetooth environment.", "correlation_repeat_ambiguous_second")
            case .mismatch:
                failLocally("The two power cycles isolated different CoreBluetooth UUIDs. Correlation failed closed; do not choose either candidate.", "correlation_repeat_mismatch")
            case let .correlated(id):
                guard var candidate = byID[id] else {
                    failLocally("The repeated correlation resolved an unavailable candidate. Restart the sequence.", "correlated_candidate_missing")
                    return
                }
                candidate.correlated = true
                candidate.score += 1000
                if !candidate.evidence.contains("repeatable OFF→ON correlation") {
                    candidate.evidence.insert("repeatable OFF→ON correlation", at: 0)
                }
                byID[id] = candidate
                candidates = byID.values.sorted {
                    $0.score == $1.score ? (($0.rssi ?? -999) > ($1.rssi ?? -999)) : $0.score > $1.score
                }
                phase = .correlated
                message = "Correlated Bluetooth target found across both power cycles. This UUID is capture-local evidence only; explicitly confirm the highlighted target before Tuya takes BLE ownership."
                log("repeatable_target_correlated", [
                    "captureLocalPeripheralID": id.uuidString,
                    "authority": "repeatable-off1-on1-off2-on2-correlation"
                ])
            }

        default:
            failLocally("Power-cycle chronology was invalid. Restart the correlation sequence.", "correlation_stop_chronology_invalid")
        }
    }

    func confirmTarget(_ candidate: Candidate) {
        guard accountIdentityLeaseIsAuthorized else {
            failLocally("Current Tuya account/device authority changed before target confirmation.", "sdk_authority_changed_before_target_selection")
            return
        }
        guard phase == .correlated, candidate.correlated else {
            message = "Only the target that repeated uniquely across both OFF→ON cycles can be confirmed. Descriptive hints cannot authorize another peripheral."
            return
        }
        central.stopScan()
        selectedID = candidate.id
        phase = .selected
        message = "Capture-local correlated Bluetooth target confirmed. CoreBluetooth discovery is stopped before Tuya's SDK takes BLE ownership."
        log("candidate_confirmed", [
            "id": candidate.id.uuidString,
            "authority": "repeatable-capture-local-corebluetooth-correlation",
            "evidence": candidate.evidence.joined(separator: ",")
        ])
    }

'''
)

replace_once(
'''        guard let candidate = selected, candidate.likely else {
            failLocally("The accepted prior physical scooter identity is required.", "candidate_not_authoritative")
            return
        }
''',
'''        guard let candidate = selected, candidate.likely else {
            failLocally("A repeatably correlated and explicitly confirmed capture-local Bluetooth target is required.", "candidate_not_authoritative")
            return
        }
'''
)

replace_once(
'''        byID.removeAll()
        candidates.removeAll()
        baseline.removeAll()
        selectedID = nil
''',
'''        byID.removeAll()
        candidates.removeAll()
        off1.removeAll()
        on1.removeAll()
        off2.removeAll()
        on2.removeAll()
        currentScanIDs.removeAll()
        correlationLeg = .off1
        selectedID = nil
'''
)

replace_between(
'    private func updateCandidate(_ peripheral: CBPeripheral, advertisement: [String: Any], rssi number: NSNumber) {',
'}\n\nextension SecureLinkController: @preconcurrency CBCentralManagerDelegate {',
'''    private func updateCandidate(_ peripheral: CBPeripheral, advertisement: [String: Any], rssi number: NSNumber) {
        let id = peripheral.identifier
        currentScanIDs.insert(id)
        let old = byID[id]
        let name = (advertisement[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? old?.name
        let rssi = number.intValue == 127 ? old?.rssi : number.intValue
        let serviceUUIDs = ((advertisement[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? [])
            + ((advertisement[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]) ?? [])
            + ((advertisement[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID]) ?? [])
        let serviceData = advertisement[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        let fd50 = serviceUUIDs.contains(Self.fd50)
            || serviceData?.keys.contains(Self.fd50) == true
            || old?.fd50 == true
        let tuyaCompany = Self.hasTuyaCompanyID(advertisement[CBAdvertisementDataManufacturerDataKey] as? Data)
            || old?.tuyaCompany == true
        let correlated = old?.correlated == true
        let currentOff = correlationLeg == .on2 ? off2 : off1
        let newAfterPowerOn = (phase == .scanning && !currentOff.contains(id)) || old?.newAfterPowerOn == true
        let expectedName = name?.localizedCaseInsensitiveContains("demo") == true
            || name?.localizedCaseInsensitiveContains("tuya") == true
            || old?.expectedName == true

        var score = 0
        var evidence: [String] = []
        if correlated { score += 1000; evidence.append("repeatable OFF→ON correlation") }
        if fd50 { score += 500; evidence.append("FD50 descriptive") }
        if tuyaCompany { score += 350; evidence.append("Tuya company 0x07D0 descriptive") }
        if newAfterPowerOn { score += 180; evidence.append("appeared after power-on descriptive") }
        if expectedName { score += 100; evidence.append("name hint descriptive") }
        if let rssi {
            if rssi >= -50 { score += 80; evidence.append("very close RSSI descriptive") }
            else if rssi >= -65 { score += 50; evidence.append("nearby RSSI descriptive") }
            else if rssi >= -80 { score += 20 }
        }

        byID[id] = Candidate(
            id: id,
            name: name,
            rssi: rssi,
            advertisements: (old?.advertisements ?? 0) + 1,
            newAfterPowerOn: newAfterPowerOn,
            fd50: fd50,
            tuyaCompany: tuyaCompany,
            correlated: correlated,
            expectedName: expectedName,
            score: score,
            evidence: evidence
        )
        candidates = byID.values.sorted {
            $0.score == $1.score ? (($0.rssi ?? -999) > ($1.rssi ?? -999)) : $0.score > $1.score
        }
    }
}\n\nextension SecureLinkController: @preconcurrency CBCentralManagerDelegate {'''
)

replace_once(
'''                    Text("The next physical run is stationary. It proves current SDK account authority, exact scooter membership, the accepted physical Bluetooth target, Tuya-owned authentication, genuine same-generation application updates, and a sealed 45-second observation prefix.")
''',
'''                    Text("The next physical run is stationary. It proves current SDK account authority, exact scooter membership, a repeatably correlated capture-local Bluetooth target, Tuya-owned authentication, genuine same-generation application updates, and a sealed 45-second observation prefix.")
'''
)

replace_between(
'    private var discoveryCard: some View {',
'    private func authenticationCard(_ candidate: SecureLinkController.Candidate) -> some View {',
'''    private var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Correlate the Bluetooth target", systemImage: "scope").font(.headline)
            Text("Two OFF→ON power cycles must isolate the same full CoreBluetooth UUID. Name, RSSI, FD50 and Tuya manufacturer hints stay descriptive only.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            switch test.phase {
            case .idle, .failed:
                Button("Start OFF scan · pass 1 of 2") { test.startBaseline() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)
            case .baseline:
                Button(test.isSecondCorrelationPass ? "Save OFF baseline · pass 2 of 2" : "Save OFF baseline · pass 1 of 2") { test.saveBaseline() }
                    .buttonStyle(.borderedProminent)
            case .powerOn:
                if test.waitingForSecondOffScan {
                    Text("Turn the scooter OFF again and wait for it to disappear.").foregroundStyle(.secondary)
                    Button("Start OFF scan · pass 2 of 2") { test.scanSecondOff() }.buttonStyle(.borderedProminent)
                } else {
                    Text(test.isSecondCorrelationPass ? "Turn the scooter ON again and keep it still." : "Turn the scooter ON and keep it still.")
                        .foregroundStyle(.secondary)
                    Button(test.isSecondCorrelationPass ? "Scan ON · pass 2 of 2" : "Scan ON · pass 1 of 2") { test.scanAfterPowerOn() }
                        .buttonStyle(.borderedProminent)
                }
            case .scanning:
                Button(test.isSecondCorrelationPass ? "Stop ON scan · resolve repeat" : "Stop ON scan · resolve pass 1") { test.stopScan() }
                    .buttonStyle(.bordered)
            case .correlated:
                Text("One capture-local target repeated uniquely. Confirm only the highlighted target to continue.")
                    .font(.footnote.bold())
                    .foregroundStyle(.green)
            default:
                EmptyView()
            }
            ForEach(test.candidates.prefix(8)) { candidate in
                Button { test.confirmTarget(candidate) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(candidate.title).bold()
                            if candidate.likely {
                                Text("CORRELATED TARGET")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.green, in: Capsule())
                                    .foregroundStyle(.black)
                            }
                            Spacer()
                            Text("\(candidate.score)").monospacedDigit()
                        }
                        Text("\(candidate.rssi.map { String($0) + " dBm" } ?? "RSSI ?") · \(candidate.id.uuidString)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(candidate.evidence.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!candidate.likely || test.phase != .correlated)
            }
        }
        .card()
    }

'''
)

replace_once(
'''            Text("Export includes exact build identity, physical target ID, SDK membership state, canonical generation/chronology, local-BLE status, terminal state, and opaque application-value projections. Account UID remains process-local and is not exported. It explicitly records rawFD50BytesCaptured=false, dpQueriesSent=false, and dpCommandsSent=false.")
''',
'''            Text("Export includes exact build identity, the capture-local correlated target ID, SDK membership state, canonical generation/chronology, local-BLE status, terminal state, and opaque application-value projections. Account UID remains process-local and is not exported. It explicitly records rawFD50BytesCaptured=false, dpQueriesSent=false, and dpCommandsSent=false.")
'''
)

path.write_text(source)
print("updated", path)
