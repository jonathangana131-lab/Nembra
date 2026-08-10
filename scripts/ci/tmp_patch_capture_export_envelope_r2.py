#!/usr/bin/env python3
from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
text = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    text = text.replace(old, new, 1)


replace_once(
    "        let exportedAt: Date\n",
    "        var exportedAt: Date\n",
    "export-time-only mutability",
)

replace_once(
    "    private var sealedAcceptedEventPrefix: [Event]?\n",
    "    private var sealedAcceptedEventPrefix: [Event]?\n"
    "    private var sealedAcceptedExportSnapshot: Export?\n",
    "accepted export snapshot storage",
)

replace_once(
    "    var accountIdentityLeaseIsAuthorized: Bool {\n"
    "        TuyaSDKAccountIdentityLeaseGate.verdict(for: accountIdentityLeaseSnapshot) == .authorized\n"
    "    }\n\n"
    "    var secureSessionEstablished: Bool {\n",
    "    var accountIdentityLeaseIsAuthorized: Bool {\n"
    "        TuyaSDKAccountIdentityLeaseGate.verdict(for: accountIdentityLeaseSnapshot) == .authorized\n"
    "    }\n\n"
    "    private var acceptanceSourceAuthorityIsStillAuthorized: Bool {\n"
    "        buildIdentity.isAuthoritativeFieldBuild\n"
    "            && privateConfig\n"
    "            && sdkAccountLoggedIn\n"
    "            && sdkDeviceMembershipVerified\n"
    "            && accountIdentityLeaseIsAuthorized\n"
    "    }\n\n"
    "    var secureSessionEstablished: Bool {\n",
    "post-seal source-authority predicate",
)

old_accept = '''                    self.acceptanceCutIsClosed = true
                    let acceptedEventPrefixAtCut = self.events
                    do {
                        try await sessionLedger.sealAcceptedObservation(for: token)
                        self.sealedAcceptedEventPrefix = acceptedEventPrefixAtCut
                        self.currentConnectionToken = nil
                        await self.refreshLedgerSnapshot()
                        self.phase = .accepted
'''
new_accept = '''                    self.acceptanceCutIsClosed = true
                    let acceptedEventPrefixAtCut = self.events
                    // Freeze the complete candidate envelope at the same quiescent cut as the
                    // application-event prefix. It becomes authoritative only if the package seal
                    // succeeds and current source authority still matches after that suspension.
                    let acceptedExportSnapshotAtCut = self.makeExportSnapshot(
                        phase: .accepted,
                        exportedAt: Date(),
                        events: acceptedEventPrefixAtCut
                    )
                    do {
                        try await sessionLedger.sealAcceptedObservation(for: token)
                        guard self.acceptanceSourceAuthorityIsStillAuthorized else {
                            self.sealedAcceptedEventPrefix = nil
                            self.sealedAcceptedExportSnapshot = nil
                            self.currentConnectionToken = nil
                            self.localBLESettlementToken = nil
                            self.sdkLocalBLEOnline = false
                            self.driver = nil
                            await self.refreshLedgerSnapshot()
                            self.phase = .failed
                            self.message = "Source authority changed while canonical acceptance was sealing. The package generation was retired, but no accepted artifact was published. Re-verify the exact SDK account/device and restart from OFF1."
                            self.log("source_authority_changed_during_acceptance_seal", [
                                "generation": String(token.diagnosticGeneration)
                            ])
                            return
                        }
                        self.sealedAcceptedEventPrefix = acceptedEventPrefixAtCut
                        self.sealedAcceptedExportSnapshot = acceptedExportSnapshotAtCut
                        self.currentConnectionToken = nil
                        await self.refreshLedgerSnapshot()
                        self.phase = .accepted
'''
replace_once(old_accept, new_accept, "quiescent full-envelope acceptance freeze")

start_marker = "    func prepareExport() {\n"
end_marker = "    private func resetDiscoverySessionOnly() {\n"
start = text.find(start_marker)
end = text.find(end_marker, start + len(start_marker))
if start < 0 or end < 0:
    raise SystemExit("prepareExport boundaries missing")
old_export = text[start:end]
for required in (
    "guard let acceptedEventPrefix = self.sealedAcceptedEventPrefix",
    "sealedAcceptedEventPrefix = acceptedEventPrefix",
    "events: sealedAcceptedEventPrefix",
    "schemaVersion: 8",
    "sdkAccountLoggedIn: sdkAccountLoggedIn",
    "sdkDeviceMembershipVerified: sdkDeviceMembershipVerified",
):
    if required not in old_export:
        raise SystemExit(f"prepareExport precondition missing: {required}")

new_export = '''    private func makeExportSnapshot(
        phase: Phase,
        exportedAt: Date,
        events: [Event]
    ) -> Export {
        Export(
            schemaVersion: 8,
            purpose: "Sanitized Tuya authenticated read-only stationary preflight",
            exportedAt: exportedAt,
            buildIdentifier: buildIdentity.buildIdentifier,
            sourceCommitSHA: buildIdentity.sourceCommitSHA,
            tuyaDeviceID: deviceID,
            tuyaUUID: tuyaUUID,
            productID: productID,
            selectedPeripheralID: selectedID?.uuidString,
            targetCorrelationMethod: targetCorrelationMethod,
            targetCorrelationWindowCount: targetCorrelationWindowCount,
            targetCorrelationOperatorConfirmed: targetCorrelationOperatorConfirmed,
            targetCorrelationProvenance: correlationProvenance,
            phase: phase,
            privateConfigPresent: privateConfig,
            sdkAccountLoggedIn: sdkAccountLoggedIn,
            sdkDeviceMembershipVerified: sdkDeviceMembershipVerified,
            secureSessionEstablished: secureSessionEstablished,
            canonicalObservedAgeSeconds: canonicalObservedAgeSeconds,
            sdkLocalBLEOnline: sdkLocalBLEOnline,
            applicationUpdateCount: applicationUpdateCount,
            connectionGeneration: ledgerSnapshot.connectionGeneration,
            authenticationMethod: ledgerSnapshot.authenticationMethod?.rawValue,
            preflightVerdict: preflightVerdictText,
            applicationValueRepresentation: "ThingSmartDeviceDelegate dpsUpdate values projected with String(describing:); application-level SDK data, not byte-exact or raw FD50 transport",
            rawFD50BytesCaptured: false,
            secretsRedacted: true,
            dpQueriesSent: false,
            dpCommandsSent: false,
            candidates: candidates,
            events: events
        )
    }

    func prepareExport() {
        let sealedAcceptedEventPrefix: [Event]
        if phase == .accepted {
            guard let acceptedEventPrefix = self.sealedAcceptedEventPrefix else {
                exportData = nil
                message = "Accepted diagnostics cannot be exported because the immutable accepted event prefix is unavailable. Restart from OFF1 rather than exporting mutable post-seal diagnostics."
                return
            }
            sealedAcceptedEventPrefix = acceptedEventPrefix
        } else {
            sealedAcceptedEventPrefix = events
        }

        let envelope: Export
        if phase == .accepted {
            guard var acceptedSnapshot = self.sealedAcceptedExportSnapshot else {
                exportData = nil
                message = "Accepted diagnostics cannot be exported because the immutable accepted evidence envelope is unavailable. Restart from OFF1 rather than exporting mutable post-seal authority."
                return
            }
            // `exportedAt` is share-time metadata only. Mutating this local value copy cannot
            // change the stored accepted snapshot or any acceptance-bound evidence field.
            acceptedSnapshot.exportedAt = Date()
            envelope = acceptedSnapshot
        } else {
            envelope = makeExportSnapshot(
                phase: phase,
                exportedAt: Date(),
                events: sealedAcceptedEventPrefix
            )
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            exportData = try encoder.encode(envelope)
            exportName = "Nembra-Secure-Link-\\(deviceID.prefix(8))-Diagnostics.json"
            message = "Sanitized diagnostics ready with exact compiled build provenance. No account UID, AppKey/AppSecret, password, account token, local_key, session key, raw FD50 claim, DP query, or DP command is exported."
        } catch {
            message = "Diagnostic export failed: \\(error.localizedDescription)"
        }
    }

'''
text = text[:start] + new_export + text[end:]

replace_once(
    "    private func resetDiscoverySessionOnly() {\n"
    "        acceptanceCutIsClosed = false\n"
    "        sealedAcceptedEventPrefix = nil\n",
    "    private func resetDiscoverySessionOnly() {\n"
    "        acceptanceCutIsClosed = false\n"
    "        sealedAcceptedEventPrefix = nil\n"
    "        sealedAcceptedExportSnapshot = nil\n",
    "fresh-session accepted snapshot reset",
)

required_postconditions = (
    "private var sealedAcceptedExportSnapshot: Export?",
    "private var acceptanceSourceAuthorityIsStillAuthorized: Bool",
    "let acceptedExportSnapshotAtCut = self.makeExportSnapshot(",
    "guard self.acceptanceSourceAuthorityIsStillAuthorized",
    "sealedAcceptedExportSnapshot = acceptedExportSnapshotAtCut",
    "guard var acceptedSnapshot = self.sealedAcceptedExportSnapshot",
    "acceptedSnapshot.exportedAt = Date()",
    "envelope = acceptedSnapshot",
    "events: sealedAcceptedEventPrefix",
    "sealedAcceptedExportSnapshot = nil",
)
for required in required_postconditions:
    if required not in text:
        raise SystemExit(f"postcondition missing: {required}")

watchdog_start = text.index("private func startWatchdog")
seal_start = text.index("self.acceptanceCutIsClosed = true", watchdog_start)
seal_end = text.index("self.phase = .accepted", seal_start)
seal_body = text[seal_start:seal_end]
for token in (
    "let acceptedEventPrefixAtCut = self.events",
    "let acceptedExportSnapshotAtCut = self.makeExportSnapshot(",
    "try await sessionLedger.sealAcceptedObservation(for: token)",
    "guard self.acceptanceSourceAuthorityIsStillAuthorized",
    "self.sealedAcceptedEventPrefix = acceptedEventPrefixAtCut",
    "self.sealedAcceptedExportSnapshot = acceptedExportSnapshotAtCut",
):
    if token not in seal_body:
        raise SystemExit(f"acceptance sequence missing: {token}")

positions = [seal_body.index(token) for token in (
    "let acceptedEventPrefixAtCut = self.events",
    "let acceptedExportSnapshotAtCut = self.makeExportSnapshot(",
    "try await sessionLedger.sealAcceptedObservation(for: token)",
    "guard self.acceptanceSourceAuthorityIsStillAuthorized",
    "self.sealedAcceptedEventPrefix = acceptedEventPrefixAtCut",
    "self.sealedAcceptedExportSnapshot = acceptedExportSnapshotAtCut",
)]
if positions != sorted(positions):
    raise SystemExit("acceptance sequence ordering regressed")

path.write_text(text)
