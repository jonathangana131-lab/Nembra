from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one anchor, found {count}")
    source = source.replace(old, new, 1)


def replace_section(start_marker: str, end_marker: str, replacement: str, label: str) -> None:
    global source
    if source.count(start_marker) != 1 or source.count(end_marker) != 1:
        raise SystemExit(f"{label}: section anchors are not unique")
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    source = source[:start] + replacement + source[end:]


if "private var authenticationAttemptID: UUID?" in source or "func handleForegroundIntegrityLoss()" in source:
    raise SystemExit("foreground/pre-connect repair anchors already exist; refresh instead of replaying")

replace_once(
    "    private var targetCorrelationOperatorConfirmed = false\n    private var driver: OfficialTuyaDriver?\n    private var events: [Event] = []\n",
    "    private var targetCorrelationOperatorConfirmed = false\n    private var driver: OfficialTuyaDriver?\n    private var authenticationAttemptID: UUID?\n    private var authenticationConnectRequestIssued = false\n    private var authenticationCleanupPending = false\n    private var events: [Event] = []\n",
    "authentication attempt state",
)

replace_once(
    "    var correlationCompletedWindowCount: Int { correlationProgress?.completedWindowCount ?? 0 }\n\n    func consumeCorrelationAsyncInvalidation() {\n",
    "    var correlationCompletedWindowCount: Int { correlationProgress?.completedWindowCount ?? 0 }\n    var authenticationCleanupIsPending: Bool { authenticationCleanupPending }\n\n    func consumeCorrelationAsyncInvalidation() {\n",
    "cleanup visibility",
)

replace_once(
    "    func startBaseline() {\n        guard buildIdentity.isAuthoritativeFieldBuild else {\n",
    "    func startBaseline() {\n        guard !authenticationCleanupPending else {\n            message = \"The cancelled authentication generation is still being retired. Do not begin a new OFF1 series until retirement completes or Capture is relaunched.\"\n            log(\"authentication_cleanup_pending_blocks_restart\")\n            return\n        }\n        guard buildIdentity.isAuthoritativeFieldBuild else {\n",
    "restart cleanup fence",
)

membership = '''    func invalidateSDKMembership() {
        let token = currentConnectionToken
        let connectRequestWasIssued = authenticationConnectRequestIssued
        membershipRequestID = UUID()
        membershipBusy = false
        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        pendingCorrelatedTargetID = nil
        authenticationAttemptID = nil
        authenticationConnectRequestIssued = false
        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
        }
        membershipStatus = "Official SDK login changed. Exact scooter membership must be verified again."
#if canImport(ThingSmartHomeKit)
        membershipProbe = nil
#endif
        if [.baseline, .powerOn, .scanning, .correlated, .selected].contains(phase) {
            phase = .failed
            message = "SDK account authority changed. Discovery stopped before any authenticated BLE attempt."
        }
        if phase == .authenticating {
            if connectRequestWasIssued, let token {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.invalidateSourceAuthority(
                        token: token,
                        message: "SDK account authority changed during the authenticated attempt.",
                        kind: "sdk_source_authority_lost"
                    )
                }
            } else {
                authenticationCleanupPending = true
                driver = nil
                phase = .failed
                message = "SDK account authority changed before the Tuya connection request was durably authorized. The pending package generation must retire before another OFF1 attempt."
                log("sdk_source_authority_lost_during_preconnect")
            }
        } else if phase == .observing, let token {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.invalidateSourceAuthority(
                    token: token,
                    message: "SDK account authority changed during the authenticated attempt.",
                    kind: "sdk_source_authority_lost"
                )
            }
        }
        log("sdk_membership_invalidated")
    }

'''
replace_section("    func invalidateSDKMembership() {\n", "    func verifySDKMembership(", membership, "membership invalidation")

begin = '''    private func beginOfficialConnection(candidate: Candidate) {
        guard phase == .selected else { return }
        guard !authenticationCleanupPending, currentConnectionToken == nil else {
            failLocally("A prior authentication generation has not been terminally retired. Relaunch Capture if cleanup does not complete; do not issue another Tuya connection request.", "authentication_generation_not_quiescent")
            return
        }
        guard targetCorrelationOperatorConfirmed,
              selectedID == candidate.id,
              candidate.likely,
              buildIdentity.isAuthoritativeFieldBuild,
              sdkDeviceMembershipVerified,
              sdkAccountLoggedIn,
              accountIdentityLeaseIsAuthorized else {
            failLocally("Confirmed build or Tuya account/device authority changed before connection start.", "sdk_authority_changed")
            return
        }
        guard let newDriver = OfficialTuyaFactory.make() else {
            failLocally("Official Tuya provider is unavailable.", "sdk_provider_unavailable")
            return
        }

        let attemptID = UUID()
        authenticationAttemptID = attemptID
        authenticationConnectRequestIssued = false
        authenticationCleanupPending = false
        driver = newDriver
        watchdog?.cancel()
        watchdog = nil
        sdkLocalBLEOnline = false
        localBLESettlementToken = nil
        phase = .authenticating
        message = "Tuya's SDK is establishing the supported secure BLE session. Nembra sends no DP query or command."

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let token = try await self.sessionLedger.beginConnection()
                guard self.authenticationAttemptStillAuthorized(attemptID, candidate: candidate) else {
                    await self.retireCancelledPreconnectGeneration(
                        token: token,
                        attemptID: attemptID,
                        message: "Authentication authority changed while the package generation was being created. The generation was retired before any Tuya connection request.",
                        kind: "preconnect_generation_cancelled_before_ownership"
                    )
                    return
                }

                // Own the package generation before any later mutation can fail. Otherwise an
                // auth-start clock regression could strand callback authority in the ledger.
                self.currentConnectionToken = token
                do {
                    try await self.sessionLedger.markAuthenticationStarted(for: token)
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                    do {
                        try await self.sessionLedger.markInternalLifecycleFailure(for: token)
                    } catch {
                        self.authenticationAttemptID = nil
                        self.authenticationConnectRequestIssued = false
                        self.authenticationCleanupPending = true
                        self.phase = .failed
                        self.message = "Authentication chronology failed and the exact generation could not be retired. Relaunch Capture before another attempt."
                        self.log("auth_start_terminal_retirement_failed", [
                            "generation": String(token.diagnosticGeneration),
                            "error": error.localizedDescription
                        ])
                        return
                    }
                    self.authenticationAttemptID = nil
                    self.authenticationConnectRequestIssued = false
                    self.authenticationCleanupPending = false
                    self.currentConnectionToken = nil
                    self.localBLESettlementToken = nil
                    self.sdkLocalBLEOnline = false
                    self.driver = nil
                    await self.refreshLedgerSnapshot()
                    self.phase = .failed
                    self.message = "Authentication chronology failed closed before the Tuya connection request. The exact generation was retired without sampling the broken clock again."
                    self.log("auth_start_clock_regressed", ["generation": String(token.diagnosticGeneration)])
                    return
                } catch {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Authentication-start lifecycle mutation failed closed before the Tuya connection request: \\(error.localizedDescription)",
                        kind: "auth_start_lifecycle_rejected"
                    )
                    self.authenticationAttemptID = nil
                    self.authenticationConnectRequestIssued = false
                    self.authenticationCleanupPending = self.currentConnectionToken == token
                    return
                }

                guard self.authenticationAttemptStillAuthorized(attemptID, candidate: candidate) else {
                    await self.retireCancelledPreconnectGeneration(
                        token: token,
                        attemptID: attemptID,
                        message: "Authentication authority changed while authentication-start chronology was being recorded. The generation was retired before any Tuya connection request.",
                        kind: "preconnect_generation_cancelled_after_auth_start"
                    )
                    return
                }

                await self.refreshLedgerSnapshot()
                guard self.authenticationAttemptStillAuthorized(attemptID, candidate: candidate) else {
                    await self.retireCancelledPreconnectGeneration(
                        token: token,
                        attemptID: attemptID,
                        message: "Authentication authority changed before the final pre-connect source check. The generation was retired without issuing a Tuya connection request.",
                        kind: "preconnect_generation_cancelled_before_connect"
                    )
                    return
                }

                // There is no suspension point between this final authority check and connect().
                // A later lifecycle/source change sees requestIssued=true and owns the exact token
                // terminal instead of racing this pre-connect continuation.
                self.authenticationConnectRequestIssued = true
                self.authenticationAttemptID = nil
                self.authenticationCleanupPending = false
                self.log("official_connect_requested", [
                    "generation": String(token.diagnosticGeneration),
                    "coreBluetoothID": candidate.id.uuidString,
                    "tuyaDeviceID": self.deviceID,
                    "tuyaUUID": self.tuyaUUID,
                    "productID": self.productID
                ])
                newDriver.connect(
                    deviceID: self.deviceID,
                    uuid: self.tuyaUUID,
                    productID: self.productID,
                    onApplicationUpdate: { [weak self] update in
                        Task { @MainActor in
                            await self?.receivedApplicationUpdate(update, token: token)
                        }
                    },
                    success: { [weak self] in
                        Task { @MainActor in await self?.authenticated(token: token) }
                    },
                    failure: { [weak self] in
                        Task { @MainActor in await self?.authenticationFailed(token: token) }
                    }
                )
            } catch {
                let wasCurrentAttempt = self.authenticationAttemptID == attemptID
                let wasCancelledAttempt = self.authenticationCleanupPending
                if self.authenticationAttemptID == attemptID {
                    self.authenticationAttemptID = nil
                }
                self.authenticationConnectRequestIssued = false
                self.driver = nil
                self.authenticationCleanupPending = false
                if wasCancelledAttempt {
                    self.log("cancelled_preconnect_generation_create_failed", ["error": error.localizedDescription])
                } else if wasCurrentAttempt {
                    self.failLocally("Could not create a fresh authenticated-session generation: \\(error.localizedDescription)", "session_generation_failed")
                }
            }
        }
    }

    private func authenticationAttemptStillAuthorized(_ attemptID: UUID, candidate: Candidate) -> Bool {
        authenticationAttemptID == attemptID
            && !authenticationCleanupPending
            && !authenticationConnectRequestIssued
            && phase == .authenticating
            && targetCorrelationOperatorConfirmed
            && selectedID == candidate.id
            && candidate.likely
            && buildIdentity.isAuthoritativeFieldBuild
            && sdkDeviceMembershipVerified
            && sdkAccountLoggedIn
            && accountIdentityLeaseIsAuthorized
            && driver != nil
    }

    private func retireCancelledPreconnectGeneration(
        token: TuyaReadOnlyConnectionToken,
        attemptID: UUID,
        message: String,
        kind: String
    ) async {
        do {
            try await sessionLedger.markInternalLifecycleFailure(for: token)
        } catch {
            if authenticationAttemptID == attemptID { authenticationAttemptID = nil }
            authenticationConnectRequestIssued = false
            authenticationCleanupPending = true
            driver = nil
            phase = .failed
            self.message = "A cancelled pre-connect generation could not be terminally retired. Relaunch Capture before another attempt."
            log("cancelled_preconnect_terminal_retirement_failed", [
                "generation": String(token.diagnosticGeneration),
                "requestedKind": kind,
                "error": error.localizedDescription
            ])
            return
        }

        if currentConnectionToken == token { currentConnectionToken = nil }
        if authenticationAttemptID == attemptID { authenticationAttemptID = nil }
        authenticationConnectRequestIssued = false
        authenticationCleanupPending = false
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        self.message = message
        log(kind, ["generation": String(token.diagnosticGeneration)])
    }

'''
replace_section("    private func beginOfficialConnection(candidate: Candidate) {\n", "    private func authenticated(token:", begin, "pre-connect authentication")

replace_once(
    "            case .observedOnline:\n                sdkLocalBLEOnline = true\n                do {\n",
    "            case .observedOnline:\n                sdkLocalBLEOnline = true\n                authenticationConnectRequestIssued = false\n                do {\n",
    "authenticated transition clears connect stage",
)

foreground = '''    func handleForegroundIntegrityLoss() {
        // `acceptanceCutIsClosed` is the app-side evidence horizon established while the
        // scene was active, before the package seal await. Later scene transitions must not
        // rewrite that already-frozen subject; package seal success/failure owns the result.
        guard !acceptanceCutIsClosed else { return }
        guard ![.idle, .failed, .accepted].contains(phase) else { return }

        let token = currentConnectionToken
        let connectRequestWasIssued = authenticationConnectRequestIssued
        authenticationAttemptID = nil
        authenticationConnectRequestIssued = false

        switch phase {
        case .baseline, .powerOn, .scanning, .correlated, .selected:
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
            driver = nil
            failLocally(
                "Capture left the foreground before the evidence horizon was sealed. Restart from OFF1 with Capture continuously foregrounded.",
                "foreground_integrity_lost"
            )

        case .authenticating:
            if connectRequestWasIssued, let token {
                Task { @MainActor [weak self] in
                    await self?.invalidateInternalLifecycle(
                        token: token,
                        message: "Capture left the foreground during authentication. The generation was retired without claiming a BLE disconnect; restart from OFF1.",
                        kind: "foreground_integrity_lost"
                    )
                }
            } else {
                authenticationCleanupPending = true
                driver = nil
                phase = .failed
                message = "Capture left the foreground while pre-connect package work was suspended. No Tuya connection request is authorized; retirement must finish before another OFF1 attempt."
                log("foreground_integrity_lost")
            }

        case .observing:
            if let token {
                Task { @MainActor [weak self] in
                    await self?.invalidateObservationContinuity(
                        token: token,
                        message: "Capture left the foreground before the evidence horizon was sealed. Observation continuity was invalidated without claiming BLE disconnect; restart from OFF1.",
                        kind: "foreground_integrity_lost"
                    )
                }
            } else {
                driver = nil
                phase = .failed
                message = "Foreground integrity was lost while observation had no current package generation. Relaunch Capture before another attempt."
                log("foreground_integrity_lost_without_generation")
            }

        case .idle, .failed, .accepted:
            break
        }
    }

'''
replace_once(
    "    private func refreshLedgerSnapshot() async {\n",
    foreground + "    private func refreshLedgerSnapshot() async {\n",
    "foreground lifecycle handler",
)

replace_once(
    "    private func resetDiscoverySessionOnly() {\n        acceptanceCutIsClosed = false\n        sealedAcceptedEventPrefix = nil\n",
    "    private func resetDiscoverySessionOnly() {\n        assert(!authenticationCleanupPending)\n        authenticationAttemptID = nil\n        authenticationConnectRequestIssued = false\n        authenticationCleanupPending = false\n        acceptanceCutIsClosed = false\n        sealedAcceptedEventPrefix = nil\n",
    "fresh attempt auth reset",
)

replace_once(
    "private struct SecureLinkView: View {\n    @StateObject private var test: SecureLinkController\n",
    "private struct SecureLinkView: View {\n    @Environment(\\.scenePhase) private var scenePhase\n    @StateObject private var test: SecureLinkController\n",
    "scene environment",
)

replace_once(
    "        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in\n            if loggedIn { test.verifySDKMembership() }\n            else { test.invalidateSDKMembership() }\n        }\n    }\n",
    "        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in\n            if loggedIn { test.verifySDKMembership() }\n            else { test.invalidateSDKMembership() }\n        }\n        .onChange(of: scenePhase) { _, newPhase in\n            if newPhase != .active {\n                test.handleForegroundIntegrityLoss()\n            }\n        }\n    }\n",
    "scene lifecycle consumer",
)

replace_once(
    "                    .disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)\n",
    "                    .disabled(test.authenticationCleanupIsPending || !test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)\n",
    "OFF1 cleanup UI fence",
)

path.write_text(source)

required = [
    "@Environment(\\.scenePhase) private var scenePhase",
    "func handleForegroundIntegrityLoss()",
    "private var authenticationAttemptID: UUID?",
    "private var authenticationConnectRequestIssued = false",
    "private var authenticationCleanupPending = false",
    "authenticationAttemptStillAuthorized(attemptID, candidate: candidate)",
    "retireCancelledPreconnectGeneration",
    "authenticationConnectRequestIssued = true",
    "newPhase != .active",
    "foreground_integrity_lost",
    "invalidateObservationContinuity(",
    "invalidateInternalLifecycle(",
    "acceptanceCutIsClosed",
    "applicationUpdateAdmissionsInFlight",
]
missing = [item for item in required if item not in source]
if missing:
    raise SystemExit(f"missing repaired anchors: {missing}")

begin_source = source[source.index("    private func beginOfficialConnection(candidate: Candidate) {"):source.index("    private func authenticated(token:")]
first_begin = begin_source.index("sessionLedger.beginConnection()")
first_recheck = begin_source.index("authenticationAttemptStillAuthorized(attemptID, candidate: candidate)", first_begin)
auth_started = begin_source.index("sessionLedger.markAuthenticationStarted(for: token)")
second_recheck = begin_source.index("authenticationAttemptStillAuthorized(attemptID, candidate: candidate)", first_recheck + 1)
refresh = begin_source.index("await self.refreshLedgerSnapshot()", second_recheck)
final_recheck = begin_source.index("authenticationAttemptStillAuthorized(attemptID, candidate: candidate)", refresh)
issued = begin_source.index("authenticationConnectRequestIssued = true", final_recheck)
connect = begin_source.index("newDriver.connect(", issued)
if not (first_begin < first_recheck and auth_started < second_recheck and refresh < final_recheck < issued < connect):
    raise SystemExit("pre-connect authority ordering invariant failed")
