from pathlib import Path

APP_PATH = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TESTS = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests")
source = APP_PATH.read_text()


def replace_once(old: str, new: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one replacement match, found {count}: {old[:140]!r}")
    source = source.replace(old, new, 1)


def replace_section(start: str, end: str, replacement: str) -> None:
    global source
    start_index = source.find(start)
    if start_index < 0:
        raise SystemExit(f"missing section start: {start}")
    end_index = source.find(end, start_index + len(start))
    if end_index < 0:
        raise SystemExit(f"missing section end: {end}")
    source = source[:start_index] + replacement + source[end_index:]


replace_once(
    "        case idle, baseline, powerOn, scanning, selected, authenticating, observing, accepted, failed\n",
    "        case idle, baseline, powerOn, scanning, correlated, selected, authenticating, observing, accepted, failed\n",
)

replace_once(
    "    struct Export: Codable {\n",
    """    struct TargetCorrelationCandidateExport: Codable {
        let peripheralID: String
        let isConnectable: Bool?
    }

    struct TargetCorrelationWindowExport: Codable {
        let phase: String
        let windowSequence: UInt64
        let startedAtUptimeNanoseconds: UInt64
        let endedAtUptimeNanoseconds: UInt64
        let observedCandidateCount: Int
        let candidates: [TargetCorrelationCandidateExport]
    }

    struct TargetCorrelationExport: Codable {
        let method: String
        let observationSeriesIdentities: [String]
        let windows: [TargetCorrelationWindowExport]
        let repeatableCandidateIDs: [String]
        let disposition: String
        let correlatedPeripheralID: String?
        let operatorConfirmed: Bool
    }

    struct Export: Codable {
""",
)
replace_once(
    "        let selectedPeripheralID: String?\n        let phase: Phase\n",
    "        let selectedPeripheralID: String?\n        let targetCorrelation: TargetCorrelationExport?\n        let phase: Phase\n",
)

replace_once(
    "    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?\n",
    "    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?\n    private var correlationResult: PassiveBluetoothPowerCycleObservationResult?\n    private var correlationConfirmedByOperator = false\n",
)
replace_once(
    "    var currentAccountUID: String? { OfficialTuyaFactory.currentAccountUID }\n    var selected: Candidate? { selectedID.flatMap { byID[$0] } }\n",
    "    var currentAccountUID: String? { OfficialTuyaFactory.currentAccountUID }\n    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }\n    var selected: Candidate? { selectedID.flatMap { byID[$0] } }\n",
)

helper = r'''    private var targetCorrelationExport: TargetCorrelationExport? {
        guard let result = correlationResult,
              result.windows.count == result.observationSnapshots.count else { return nil }

        let windows = zip(result.windows, result.observationSnapshots).map { pair in
            let receipt = pair.0
            let snapshot = pair.1
            return TargetCorrelationWindowExport(
                phase: Self.correlationPhaseLabel(receipt.phase),
                windowSequence: receipt.windowSequence.rawValue,
                startedAtUptimeNanoseconds: receipt.startedAtUptimeNanoseconds,
                endedAtUptimeNanoseconds: receipt.endedAtUptimeNanoseconds,
                observedCandidateCount: receipt.observedCandidateCount,
                candidates: snapshot.candidates.map { observed in
                    TargetCorrelationCandidateExport(
                        peripheralID: observed.id.uuidString,
                        isConnectable: observed.isConnectable
                    )
                }
            )
        }

        let correlatedID: UUID?
        switch result.correlation.disposition {
        case let .singleRepeatableCandidate(id): correlatedID = id
        default: correlatedID = nil
        }

        return TargetCorrelationExport(
            method: "package-owned-fresh-manager-off1-on1-off2-on2",
            observationSeriesIdentities: result.correlation.observationSeriesIdentities.map { $0.rawValue.uuidString },
            windows: windows,
            repeatableCandidateIDs: result.correlation.repeatableCandidateIdentifiers.map(\.uuidString),
            disposition: Self.correlationDispositionText(result.correlation.disposition),
            correlatedPeripheralID: correlatedID?.uuidString,
            operatorConfirmed: correlationConfirmedByOperator
        )
    }

    private static func correlationPhaseLabel(_ phase: PassiveBluetoothPowerCycleObservationPhase) -> String {
        switch phase {
        case .firstPoweredOff: return "OFF1"
        case .firstPoweredOn: return "ON1"
        case .secondPoweredOff: return "OFF2"
        case .secondPoweredOn: return "ON2"
        }
    }

    private static func correlationDispositionText(
        _ disposition: PassiveBluetoothPowerCycleTargetCorrelationReport.Disposition
    ) -> String {
        switch disposition {
        case .invalidObservationAuthority: return "invalid-observation-authority"
        case .invalidObservationWindowOrder: return "invalid-observation-window-order"
        case .noRepeatableCandidate: return "no-repeatable-candidate"
        case .ambiguousRepeatableCandidates: return "ambiguous-repeatable-candidates"
        case .singleRepeatableCandidate: return "single-repeatable-candidate"
        }
    }

'''
replace_once("    func startBaseline() {\n", helper + "    func startBaseline() {\n")

replace_section(
    "    private func finishCorrelationSeries(_ result: PassiveBluetoothPowerCycleObservationResult) {\n",
    "    func invalidateSDKMembership() {\n",
    r'''    private func finishCorrelationSeries(_ result: PassiveBluetoothPowerCycleObservationResult) {
        correlationResult = result
        correlationConfirmedByOperator = false
        correlationSession = nil
        selectedID = nil

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
            phase = .correlated
            message = "Fresh repeated power-cycle correlation found one full CoreBluetooth target. This is current-session correlation evidence, not permanent scooter identity. Explicitly confirm this correlated Bluetooth target before Tuya's SDK may take BLE ownership."
            log("target_correlation_ready_for_confirmation", [
                "id": id.uuidString,
                "authority": "fresh-repeated-off-on-full-corebluetooth-id",
                "historicalCaptureUUIDMatch": String(historicalCaptureID),
                "windows": String(result.windows.count),
                "operatorConfirmed": "false"
            ])

        case let .ambiguousRepeatableCandidates(ids):
            failLocally("Fresh correlation remained ambiguous across \(ids.count) repeatable full UUIDs. Do not guess from name, RSSI, FD50, or Tuya hints; restart from OFF1 after reducing nearby-device ambiguity.", "target_correlation_ambiguous")

        case .noRepeatableCandidate:
            failLocally("No full UUID repeated the required OFF1→ON1→OFF2→ON2 pattern. Do not fall back to the historical capture UUID; restart the fresh correlation series.", "target_correlation_no_repeatable_candidate")

        case .invalidObservationAuthority, .invalidObservationWindowOrder:
            failLocally("The package rejected correlation provenance/chronology. Restart from OFF1; prior windows cannot be spliced into a new attempt.", "target_correlation_provenance_rejected")
        }
    }

    func confirmCorrelatedTarget() {
        guard phase == .correlated,
              let result = correlationResult,
              case let .singleRepeatableCandidate(id) = result.correlation.disposition,
              let candidate = byID[id],
              candidate.freshlyCorrelated else {
            failLocally("No unique current-session correlated Bluetooth target is available for confirmation.", "target_confirmation_unavailable")
            return
        }
        guard fieldBuildIsAuthoritative,
              sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            failLocally("Build or same-account scooter authority changed before target confirmation. Restart the fresh correlation attempt after restoring preflight authority.", "target_confirmation_authority_changed")
            return
        }

        selectedID = id
        correlationConfirmedByOperator = true
        phase = .selected
        message = "Correlated Bluetooth target explicitly confirmed for this attempt. This remains current-session correlation evidence, not permanent scooter identity. Tuya may now re-check exact same-account membership before taking BLE ownership."
        log("candidate_selected", [
            "id": id.uuidString,
            "authority": "fresh-repeated-off-on-full-corebluetooth-id",
            "operatorConfirmed": "true",
            "correlation": "OFF1-ON1-OFF2-ON2"
        ])
    }

''',
)

replace_once(
    "        if phase == .baseline || phase == .powerOn || phase == .scanning {\n            correlationSession?.abandonCurrentWindow()\n            correlationSession = nil\n        }\n",
    "        if phase == .baseline || phase == .powerOn || phase == .scanning {\n            correlationSession?.abandonCurrentWindow()\n            correlationSession = nil\n        }\n        if phase == .correlated || phase == .selected {\n            selectedID = nil\n        }\n",
)
replace_once(
    "        if [.baseline, .powerOn, .scanning, .selected].contains(phase) {\n",
    "        if [.baseline, .powerOn, .scanning, .correlated, .selected].contains(phase) {\n",
)

replace_once(
    '''                } catch {
                    await invalidateSourceAuthority(
                        token: token,
                        message: "Authenticated-session chronology rejected the SDK success callback: \(error.localizedDescription)",
                        kind: "session_auth_callback_rejected"
                    )
                }
''',
    '''                } catch {
                    await invalidateChronologyIntegrity(
                        token: token,
                        message: "Authenticated-session chronology rejected the SDK success callback: \(error.localizedDescription)",
                        kind: "session_auth_callback_rejected"
                    )
                }
''',
)
replace_once(
    '''            case .invalidClock:
                await authenticationAcquisitionFailed(
                    token: token,
                    message: "Local-BLE settlement failed closed because the monotonic clock regressed.",
                    kind: "sdk_local_ble_settlement_clock_invalid"
                )
                return
''',
    '''            case .invalidClock:
                await invalidateChronologyIntegrity(
                    token: token,
                    message: "Local-BLE settlement failed closed because the monotonic clock regressed.",
                    kind: "sdk_local_ble_settlement_clock_invalid"
                )
                return
''',
)

replace_section(
    "    private func authenticationAcquisitionFailed(\n",
    "    private func receivedApplicationUpdate(\n",
    r'''    private func authenticationAcquisitionFailed(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markAuthenticationFailed(for: token)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            await invalidateChronologyIntegrity(
                token: token,
                message: "\(message) The session clock also regressed while retiring this generation.",
                kind: "\(kind)_clock_invalid"
            )
            return
        } catch {
            localBLESettlementToken = nil
            sdkLocalBLEOnline = false
            driver = nil
            phase = .failed
            self.message = "\(message) Nembra could not prove terminal retirement of this generation; relaunch Capture before another attempt."
            log("\(kind)_terminal_retirement_failed", [
                "generation": String(token.diagnosticGeneration),
                "error": String(describing: error)
            ])
            return
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

''',
)

replace_once(
    '''        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            log("retired_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
        } catch {
            await invalidateObservationContinuity(
                token: token,
                message: "Application chronology failed closed: \(error.localizedDescription)",
                kind: "application_update_rejected"
            )
        }
''',
    '''        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            log("retired_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            await invalidateChronologyIntegrity(
                token: token,
                message: "Application chronology failed closed because the monotonic clock regressed.",
                kind: "application_update_clock_invalid"
            )
        } catch {
            await invalidateObservationContinuity(
                token: token,
                message: "Application chronology failed closed: \(error.localizedDescription)",
                kind: "application_update_rejected"
            )
        }
''',
)

replace_once(
    '''                guard now >= previousPollUptime else {
                    do {
                        try await sessionLedger.markObservationContinuityInvalidated(for: token)
                    } catch {}
                    self.currentConnectionToken = nil
                    await self.refreshLedgerSnapshot()
                    self.failLocally("Authenticated observation continuity was interrupted by a monotonic-clock regression.", "observation_clock_regressed")
                    return
                }
''',
    '''                guard now >= previousPollUptime else {
                    await self.invalidateChronologyIntegrity(
                        token: token,
                        message: "Authenticated observation continuity was interrupted by a monotonic-clock regression.",
                        kind: "observation_clock_regressed"
                    )
                    return
                }
''',
)
replace_once(
    '''                guard gap <= Self.maximumObservationPollGapNanoseconds else {
                    do {
                        try await sessionLedger.markObservationContinuityInvalidated(for: token)
                    } catch {}
                    self.currentConnectionToken = nil
                    await self.refreshLedgerSnapshot()
                    self.failLocally("Authenticated observation continuity was interrupted; the gap is not evidence that BLE disconnected.", "observation_poll_gap_exceeded")
                    return
                }
''',
    '''                guard gap <= Self.maximumObservationPollGapNanoseconds else {
                    await self.invalidateObservationContinuity(
                        token: token,
                        message: "Authenticated observation continuity was interrupted; the gap is not evidence that BLE disconnected.",
                        kind: "observation_poll_gap_exceeded"
                    )
                    return
                }
''',
)
replace_once(
    '''                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
                    self.log("sealed_watchdog_generation_retired", ["generation": String(token.diagnosticGeneration)])
                    return
                } catch {
                    await self.invalidateObservationContinuity(
                        token: token,
                        message: "Authenticated-session liveness chronology failed closed: \(error.localizedDescription)",
                        kind: "session_liveness_rejected"
                    )
                    return
                }
''',
    '''                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
                    self.log("sealed_watchdog_generation_retired", ["generation": String(token.diagnosticGeneration)])
                    return
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                    await self.invalidateChronologyIntegrity(
                        token: token,
                        message: "Authenticated-session liveness chronology failed closed because the monotonic clock regressed.",
                        kind: "session_liveness_clock_invalid"
                    )
                    return
                } catch {
                    await self.invalidateObservationContinuity(
                        token: token,
                        message: "Authenticated-session liveness chronology failed closed: \(error.localizedDescription)",
                        kind: "session_liveness_rejected"
                    )
                    return
                }
''',
)

replace_once(
    '''                    } catch {
                        await self.invalidateObservationContinuity(
                            token: token,
                            message: "Canonical readiness could not be sealed: \(error.localizedDescription)",
                            kind: "accepted_prefix_seal_failed"
                        )
                    }
                    return
''',
    '''                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                        await self.invalidateChronologyIntegrity(
                            token: token,
                            message: "Canonical readiness could not be sealed because the monotonic clock regressed.",
                            kind: "accepted_prefix_seal_clock_invalid"
                        )
                    } catch {
                        await self.invalidateObservationContinuity(
                            token: token,
                            message: "Canonical readiness could not be sealed: \(error.localizedDescription)",
                            kind: "accepted_prefix_seal_failed"
                        )
                    }
                    return
''',
)

replace_once(
    '''                if (self.canonicalObservedAgeSeconds ?? 0) > 60,
                   self.applicationUpdateCount == 0 {
                    do {
                        try await sessionLedger.markApplicationObservationTimedOut(for: token)
                    } catch {}
                    self.currentConnectionToken = nil
                    self.sdkLocalBLEOnline = false
                    self.driver = nil
                    await self.refreshLedgerSnapshot()
                    self.phase = .failed
                    self.message = "Authenticated session produced no application update before the observation deadline. Export diagnostics; do not repeat the ride capture."
                    self.log("authenticated_application_timeout", ["generation": String(token.diagnosticGeneration)])
                    return
                }
''',
    '''                if (self.canonicalObservedAgeSeconds ?? 0) > 60,
                   self.applicationUpdateCount == 0 {
                    do {
                        try await sessionLedger.markApplicationObservationTimedOut(for: token)
                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                        await self.invalidateChronologyIntegrity(
                            token: token,
                            message: "The authenticated application deadline arrived while the monotonic clock was invalid.",
                            kind: "authenticated_application_timeout_clock_invalid"
                        )
                        return
                    } catch {
                        self.localBLESettlementToken = nil
                        self.sdkLocalBLEOnline = false
                        self.driver = nil
                        self.phase = .failed
                        self.message = "Application-timeout retirement could not be proven; relaunch Capture before another attempt."
                        self.log("authenticated_application_timeout_retirement_failed", [
                            "generation": String(token.diagnosticGeneration),
                            "error": String(describing: error)
                        ])
                        return
                    }
                    self.currentConnectionToken = nil
                    self.localBLESettlementToken = nil
                    self.sdkLocalBLEOnline = false
                    self.driver = nil
                    await self.refreshLedgerSnapshot()
                    self.phase = .failed
                    self.message = "Authenticated session produced no application update before the observation deadline. Export diagnostics; do not repeat the ride capture."
                    self.log("authenticated_application_timeout", ["generation": String(token.diagnosticGeneration)])
                    return
                }
''',
)

replace_section(
    "    private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken) async {\n",
    "    private func invalidateSourceAuthority(\n",
    r'''    private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.endConnection(for: token)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            await invalidateChronologyIntegrity(
                token: token,
                message: "Tuya local BLE was observed offline, but the monotonic clock regressed before the disconnect terminal could be recorded.",
                kind: "sdk_local_ble_drop_clock_invalid"
            )
            return
        } catch {
            localBLESettlementToken = nil
            sdkLocalBLEOnline = false
            driver = nil
            phase = .failed
            message = "Tuya local BLE ended, but terminal ledger retirement could not be proven. Relaunch Capture before another attempt."
            log("sdk_local_ble_drop_retirement_failed", [
                "generation": String(token.diagnosticGeneration),
                "error": String(describing: error)
            ])
            return
        }
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        message = "Tuya's current local-BLE session ended before acceptance. Export diagnostics; do not repeat the outdoor ride capture."
        log("sdk_local_ble_dropped", ["generation": String(token.diagnosticGeneration)])
    }

    private func invalidateChronologyIntegrity(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markChronologyIntegrityInvalidated(for: token)
        } catch {
            localBLESettlementToken = nil
            sdkLocalBLEOnline = false
            driver = nil
            phase = .failed
            self.message = "\(message) Exact terminal retirement could not be proven; relaunch Capture before another attempt."
            log("\(kind)_retirement_failed", [
                "generation": String(token.diagnosticGeneration),
                "error": String(describing: error)
            ])
            return
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

''',
)

replace_section(
    "    private func invalidateSourceAuthority(\n",
    "    private func invalidateObservationContinuity(\n",
    r'''    private func invalidateSourceAuthority(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markSourceAuthorityInvalidated(for: token)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            await invalidateChronologyIntegrity(
                token: token,
                message: "\(message) The monotonic clock also regressed while retiring source authority.",
                kind: "\(kind)_clock_invalid"
            )
            return
        } catch {
            localBLESettlementToken = nil
            sdkLocalBLEOnline = false
            driver = nil
            phase = .failed
            self.message = "\(message) Source-authority retirement could not be proven; relaunch Capture before another attempt."
            log("\(kind)_retirement_failed", [
                "generation": String(token.diagnosticGeneration),
                "error": String(describing: error)
            ])
            return
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

''',
)

replace_section(
    "    private func invalidateObservationContinuity(\n",
    "    private func refreshLedgerSnapshot() async {\n",
    r'''    private func invalidateObservationContinuity(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markObservationContinuityInvalidated(for: token)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            await invalidateChronologyIntegrity(
                token: token,
                message: "\(message) The monotonic clock also regressed while retiring observation continuity.",
                kind: "\(kind)_clock_invalid"
            )
            return
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            currentConnectionToken = nil
            localBLESettlementToken = nil
            sdkLocalBLEOnline = false
            driver = nil
            await refreshLedgerSnapshot()
            phase = .failed
            self.message = message
            log(kind, ["generation": String(token.diagnosticGeneration), "ledgerAlreadyRetired": "true"])
            return
        } catch {
            localBLESettlementToken = nil
            sdkLocalBLEOnline = false
            driver = nil
            phase = .failed
            self.message = "\(message) Observation-continuity retirement could not be proven; relaunch Capture before another attempt."
            log("\(kind)_retirement_failed", [
                "generation": String(token.diagnosticGeneration),
                "error": String(describing: error)
            ])
            return
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

''',
)

replace_once("            schemaVersion: 7,\n", "            schemaVersion: 8,\n")
replace_once(
    "            selectedPeripheralID: selectedID?.uuidString,\n            phase: phase,\n",
    "            selectedPeripheralID: selectedID?.uuidString,\n            targetCorrelation: targetCorrelationExport,\n            phase: phase,\n",
)

replace_once(
    "        correlationSession?.abandonCurrentWindow()\n        correlationSession = nil\n        central.stopScan()\n",
    "        correlationSession?.abandonCurrentWindow()\n        correlationSession = nil\n        correlationResult = nil\n        correlationConfirmedByOperator = false\n        central.stopScan()\n",
)

replace_once(
    '            LabeledContent("Field build", value: test.accountIdentityLeaseIsAuthorized && test.sdkDeviceMembershipVerified ? "Authority checked" : "Not ready")\n',
    '            LabeledContent("Field build", value: test.fieldBuildIsAuthoritative ? "Exact compiled provenance" : "Not authoritative")\n',
)
replace_once(
    "            if !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {\n",
    "            if !test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {\n",
)
replace_once(
    '                Text("NO PHYSICAL BLE TEST YET: the private exact field build, current SDK account identity, and exact scooter membership must all be proven before even the OFF baseline scan can start.")\n',
    '                Text("NO PHYSICAL BLE TEST YET: exact compiled field-build provenance, the current SDK account identity, and exact scooter membership must all be proven before OFF1 correlation can start.")\n',
)
replace_once(
    '''                Button("Start OFF1 correlation") { test.startBaseline() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)
''',
    '''                Button("Start OFF1 correlation") { test.startBaseline() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)
''',
)
replace_once(
    '''            case .powerOn:
                Text("Next: \(test.correlationWindowLabel) · \(test.correlationWindowInstruction)")
                    .foregroundStyle(.secondary)
                Button("Start \(test.correlationWindowLabel) window") { test.startNextCorrelationWindow() }
                    .buttonStyle(.borderedProminent)

            default:
''',
    '''            case .powerOn:
                Text("Next: \(test.correlationWindowLabel) · \(test.correlationWindowInstruction)")
                    .foregroundStyle(.secondary)
                Button("Start \(test.correlationWindowLabel) window") { test.startNextCorrelationWindow() }
                    .buttonStyle(.borderedProminent)

            case .correlated:
                Text("One full CoreBluetooth UUID repeated the complete OFF1→ON1→OFF2→ON2 pattern. This is correlated Bluetooth evidence for this session only—not permanent ES80 identity.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Confirm correlated Bluetooth target") { test.confirmCorrelatedTarget() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!test.fieldBuildIsAuthoritative || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized)

            default:
''',
)
replace_once(
    '''                        if candidate.likely {
                            Text("FRESH CORRELATION")
''',
    '''                        if candidate.likely {
                            Text(test.phase == .correlated ? "CORRELATED · CONFIRM" : "CONFIRMED TARGET")
''',
)
replace_once(
    '            Text("Export includes exact build identity, current-session correlated target ID, SDK membership state, canonical generation/chronology, local-BLE status, terminal state, and opaque application-value projections. Account UID remains process-local and is not exported. It explicitly records rawFD50BytesCaptured=false, dpQueriesSent=false, and dpCommandsSent=false.")\n',
    '            Text("Export includes exact build identity plus the sealed four-window target-correlation receipts, full UUID/connectability catalogs, correlation disposition, and explicit operator-confirmation fact; it also includes SDK membership state, canonical authenticated chronology, local-BLE status, terminal state, and opaque application-value projections. Account UID remains process-local and is not exported. It explicitly records rawFD50BytesCaptured=false, dpQueriesSent=false, and dpCommandsSent=false.")\n',
)

fresh_path = TESTS / "TuyaFreshTargetAndAcquisitionTerminalSourceTests.swift"
fresh = fresh_path.read_text()
old = '''        #expect(timeoutBranch.contains("authenticationAcquisitionFailed"))
        #expect(invalidClockBranch.contains("authenticationAcquisitionFailed"))
        #expect(!timeoutBranch.contains("invalidateSourceAuthority"))
        #expect(!invalidClockBranch.contains("invalidateSourceAuthority"))
'''
new = '''        #expect(timeoutBranch.contains("authenticationAcquisitionFailed"))
        #expect(invalidClockBranch.contains("invalidateChronologyIntegrity"))
        #expect(!timeoutBranch.contains("invalidateSourceAuthority"))
        #expect(!invalidClockBranch.contains("invalidateSourceAuthority"))
        #expect(!invalidClockBranch.contains("authenticationAcquisitionFailed"))
'''
if fresh.count(old) != 1:
    raise SystemExit("fresh-target terminal source contract did not match exact parent")
fresh_path.write_text(fresh.replace(old, new, 1))

APP_PATH.write_text(source)

TESTS.joinpath("TuyaExplicitCorrelatedTargetConfirmationSourceTests.swift").write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture explicit correlated-target confirmation")
struct TuyaExplicitCorrelatedTargetConfirmationSourceTests {
    @Test("unique repeated correlation is offered for confirmation instead of auto-selected")
    func correlationResultCannotAutoSelectTarget() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let finish = try section(in: app, from: "private func finishCorrelationSeries", to: "func confirmCorrelatedTarget")
        #expect(finish.contains("singleRepeatableCandidate"))
        #expect(finish.contains("phase = .correlated"))
        #expect(!finish.contains("selectedID = id"))
        #expect(!finish.contains("phase = .selected"))
        #expect(!finish.contains("candidate_selected"))
    }

    @Test("operator action is the only bridge from correlated candidate to selected target")
    func explicitOperatorConfirmationOwnsSelection() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let confirmation = try section(in: app, from: "func confirmCorrelatedTarget", to: "func invalidateSDKMembership")
        #expect(confirmation.contains("selectedID = id"))
        #expect(confirmation.contains("phase = .selected"))
        #expect(confirmation.contains("candidate_selected"))
        #expect(confirmation.contains("correlation"))
        #expect(confirmation.contains("accountIdentityLeaseIsAuthorized"))
        #expect(confirmation.contains("fieldBuildIsAuthoritative"))
    }

    @Test("primary UI exposes explicit confirmation before authentication")
    func primaryUIRequiresConfirmation() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let discovery = try section(in: app, from: "private var discoveryCard: some View", to: "private func authenticationCard")
        #expect(discovery.contains("case .correlated"))
        #expect(discovery.contains("confirmCorrelatedTarget"))
        #expect(discovery.localizedCaseInsensitiveContains("confirm"))
        #expect(discovery.localizedCaseInsensitiveContains("correlat"))
    }

    @Test("authentication still requires the explicitly selected current-session candidate")
    func authenticationConsumesConfirmedSelection() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authenticate = try section(in: app, from: "func authenticate()", to: "private func beginOfficialConnection")
        #expect(authenticate.contains("selected"))
        #expect(authenticate.contains("candidate.likely"))
        #expect(authenticate.contains("verifySDKMembership"))
        #expect(authenticate.contains("accountIdentityLeaseIsAuthorized"))
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

TESTS.joinpath("TuyaFieldBuildPresentationAuthorityCurrentSourceTests.swift").write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture current field-build presentation authority")
struct TuyaFieldBuildPresentationAuthorityCurrentSourceTests {
    @Test("field-build row is backed by exact compiled provenance")
    func fieldBuildRowUsesBuildIdentityAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }"))
        let card = try section(in: app, from: "private var authorityCard: some View", to: "private var discoveryCard: some View")
        #expect(card.contains("LabeledContent(\"Field build\""))
        #expect(card.contains("test.fieldBuildIsAuthoritative"))
        #expect(card.contains("!test.fieldBuildIsAuthoritative"))
    }

    @Test("OFF1 affordance fails closed before runtime guard")
    func off1AffordanceConsumesBuildAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let card = try section(in: app, from: "private var discoveryCard: some View", to: "private func authenticationCard")
        #expect(card.contains("Button(\"Start OFF1 correlation\")"))
        #expect(card.contains("!test.fieldBuildIsAuthoritative"))
        let start = try section(in: app, from: "func startBaseline()", to: "private func beginCorrelationSeries")
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

TESTS.joinpath("TuyaChronologyIntegrityAppRoutingSourceTests.swift").write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture chronology-integrity app routing")
struct TuyaChronologyIntegrityAppRoutingSourceTests {
    @Test("clock failures use the no-clock terminal rather than source or ordinary auth failure")
    func clockFailuresUseNoClockTerminal() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("private func invalidateChronologyIntegrity"))
        let terminal = try section(in: app, from: "private func invalidateChronologyIntegrity", to: "private func invalidateSourceAuthority")
        #expect(terminal.contains("markChronologyIntegrityInvalidated"))
        #expect(!terminal.contains("markSourceAuthorityInvalidated"))
        #expect(!terminal.contains("markAuthenticationFailed"))
        let authenticated = try section(in: app, from: "private func authenticated(token:", to: "private func authenticationFailed")
        #expect(authenticated.contains("session_auth_callback_rejected"))
        #expect(authenticated.contains("invalidateChronologyIntegrity"))
        #expect(authenticated.contains("case .invalidClock:"))
    }

    @Test("watchdog and later terminal clock regressions cannot clear only controller authority")
    func laterClockRegressionRoutesAreTerminal() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss")
        #expect(watchdog.contains("observation_clock_regressed"))
        #expect(watchdog.contains("invalidateChronologyIntegrity"))
        #expect(watchdog.contains("accepted_prefix_seal_clock_invalid"))
        #expect(watchdog.contains("authenticated_application_timeout_clock_invalid"))
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

TESTS.joinpath("TuyaCorrelationExportProvenanceSourceTests.swift").write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture target-correlation export provenance")
struct TuyaCorrelationExportProvenanceSourceTests {
    @Test("diagnostic export preserves four-window producer evidence and operator confirmation")
    func exportCarriesReplayableCorrelationEvidence() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("struct TargetCorrelationExport: Codable"))
        #expect(app.contains("let targetCorrelation: TargetCorrelationExport?"))
        #expect(app.contains("result.observationSnapshots"))
        #expect(app.contains("snapshot.candidates"))
        #expect(app.contains("receipt.startedAtUptimeNanoseconds"))
        #expect(app.contains("receipt.endedAtUptimeNanoseconds"))
        #expect(app.contains("observationSeriesIdentities"))
        #expect(app.contains("repeatableCandidateIdentifiers"))
        #expect(app.contains("operatorConfirmed: correlationConfirmedByOperator"))
        let export = try section(in: app, from: "func prepareExport()", to: "private func resetDiscoverySessionOnly")
        #expect(export.contains("schemaVersion: 8"))
        #expect(export.contains("targetCorrelation: targetCorrelationExport"))
        #expect(export.contains("rawFD50BytesCaptured: false"))
        #expect(export.contains("dpQueriesSent: false"))
        #expect(export.contains("dpCommandsSent: false"))
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
