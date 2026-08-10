#!/usr/bin/env python3
from pathlib import Path

p = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
s = p.read_text()

def once(a: str, b: str, label: str) -> None:
    global s
    n = s.count(a)
    if n != 1:
        raise SystemExit(f"{label}: expected 1 match, got {n}")
    s = s.replace(a, b, 1)

once("        let exportedAt: Date\n", "        var exportedAt: Date\n", "exportedAt")
once(
    "    private var sealedAcceptedEventPrefix: [Event]?\n",
    "    private var sealedAcceptedEventPrefix: [Event]?\n    private var sealedAcceptedExportSnapshot: Export?\n",
    "snapshot storage",
)
once(
    "    var secureSessionEstablished: Bool {\n",
    "    private var acceptanceSourceAuthorityIsStillAuthorized: Bool {\n"
    "        buildIdentity.isAuthoritativeFieldBuild\n"
    "            && privateConfig\n"
    "            && sdkAccountLoggedIn\n"
    "            && sdkDeviceMembershipVerified\n"
    "            && accountIdentityLeaseIsAuthorized\n"
    "    }\n\n"
    "    var secureSessionEstablished: Bool {\n",
    "source authority predicate",
)

old_accept = '''                    self.acceptanceCutIsClosed = true
                    // Freeze only the current physical attempt. Older failed-attempt diagnostics stay
                    // available in the live controller log but cannot contaminate accepted evidence.
                    let acceptedEventPrefixAtCut = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))
                    do {
                        try await sessionLedger.sealAcceptedObservation(for: token)
                        self.sealedAcceptedEventPrefix = acceptedEventPrefixAtCut
                        self.currentConnectionToken = nil
                        await self.refreshLedgerSnapshot()
                        self.phase = .accepted
'''
new_accept = '''                    self.acceptanceCutIsClosed = true
                    // Freeze only the current physical attempt. Older failed-attempt diagnostics stay
                    // available in the live controller log but cannot contaminate accepted evidence.
                    let acceptedEventPrefixAtCut = Array(self.events.dropFirst(self.captureAttemptEventStartIndex))
                    // Freeze all acceptance-bound metadata at the same quiescent cut. This candidate
                    // becomes authoritative only after the package seal succeeds and source authority
                    // is rechecked after that suspension point.
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
once(old_accept, new_accept, "acceptance block")

start = s.index("    func prepareExport() {\n")
end = s.index("    private func resetDiscoverySessionOnly() {\n", start)
old_export = s[start:end]
for token in ("sealedAcceptedEventPrefix = acceptedEventPrefix", "events: sealedAcceptedEventPrefix", "schemaVersion: 8"):
    if token not in old_export:
        raise SystemExit(f"old export missing {token}")

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
            acceptedSnapshot.exportedAt = Date()
            envelope = acceptedSnapshot
        } else {
            envelope = makeExportSnapshot(phase: phase, exportedAt: Date(), events: sealedAcceptedEventPrefix)
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            exportData = try encoder.encode(envelope)
            exportName = "Nembra-Secure-Link-\(deviceID.prefix(8))-Diagnostics.json"
            message = "Sanitized diagnostics ready with exact compiled build provenance. No account UID, AppKey/AppSecret, password, account token, local_key, session key, raw FD50 claim, DP query, or DP command is exported."
        } catch {
            message = "Diagnostic export failed: \(error.localizedDescription)"
        }
    }

'''
s = s[:start] + new_export + s[end:]
once(
    "        acceptanceCutIsClosed = false\n        sealedAcceptedEventPrefix = nil\n",
    "        acceptanceCutIsClosed = false\n        sealedAcceptedEventPrefix = nil\n        sealedAcceptedExportSnapshot = nil\n",
    "reset",
)

for token in (
    "sealedAcceptedExportSnapshot: Export?",
    "acceptedExportSnapshotAtCut = self.makeExportSnapshot(",
    "guard self.acceptanceSourceAuthorityIsStillAuthorized",
    "self.sealedAcceptedExportSnapshot = acceptedExportSnapshotAtCut",
    "guard var acceptedSnapshot = self.sealedAcceptedExportSnapshot",
    "acceptedSnapshot.exportedAt = Date()",
):
    if token not in s:
        raise SystemExit(f"postcondition missing {token}")

p.write_text(s)
