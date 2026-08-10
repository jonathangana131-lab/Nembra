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
    "                        try await sessionLedger.sealAcceptedObservation(for: token)\n"
    "                        self.sealedAcceptedEventPrefix = self.events\n"
    "                        self.currentConnectionToken = nil\n"
    "                        await self.refreshLedgerSnapshot()\n"
    "                        self.phase = .accepted\n",
    "                        try await sessionLedger.sealAcceptedObservation(for: token)\n"
    "                        let acceptedEventPrefix = self.events\n"
    "                        self.sealedAcceptedEventPrefix = acceptedEventPrefix\n"
    "                        // The package seal retires callback authority without advancing the\n"
    "                        // already-earned ready snapshot. Freeze every acceptance-bound export\n"
    "                        // field before the next suspension point so logout/membership changes\n"
    "                        // cannot rewrite an already accepted artifact.\n"
    "                        self.sealedAcceptedExportSnapshot = self.makeExportSnapshot(\n"
    "                            phase: .accepted,\n"
    "                            exportedAt: Date(),\n"
    "                            events: acceptedEventPrefix\n"
    "                        )\n"
    "                        self.currentConnectionToken = nil\n"
    "                        await self.refreshLedgerSnapshot()\n"
    "                        self.phase = .accepted\n",
    "synchronous acceptance envelope freeze",
)

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
            exportName = "Nembra-Secure-Link-\(deviceID.prefix(8))-Diagnostics.json"
            message = "Sanitized diagnostics ready with exact compiled build provenance. No account UID, AppKey/AppSecret, password, account token, local_key, session key, raw FD50 claim, DP query, or DP command is exported."
        } catch {
            message = "Diagnostic export failed: \(error.localizedDescription)"
        }
    }

'''
text = text[:start] + new_export + text[end:]

replace_once(
    "    private func resetDiscoverySessionOnly() {\n"
    "        sealedAcceptedEventPrefix = nil\n",
    "    private func resetDiscoverySessionOnly() {\n"
    "        sealedAcceptedEventPrefix = nil\n"
    "        sealedAcceptedExportSnapshot = nil\n",
    "fresh-session accepted snapshot reset",
)

# Structural postconditions. These intentionally mirror the source contracts while
# keeping export-time Date separate from acceptance authority.
required_postconditions = (
    "private var sealedAcceptedExportSnapshot: Export?",
    "sealedAcceptedExportSnapshot = self.makeExportSnapshot(",
    "guard var acceptedSnapshot = self.sealedAcceptedExportSnapshot",
    "acceptedSnapshot.exportedAt = Date()",
    "envelope = acceptedSnapshot",
    "events: sealedAcceptedEventPrefix",
    "sealedAcceptedExportSnapshot = nil",
)
for required in required_postconditions:
    if required not in text:
        raise SystemExit(f"postcondition missing: {required}")

seal_start = text.index("try await sessionLedger.sealAcceptedObservation(for: token)")
seal_end = text.index("self.phase = .accepted", seal_start)
seal_body = text[seal_start:seal_end]
if seal_body.index("sealedAcceptedEventPrefix =") > seal_body.index("await self.refreshLedgerSnapshot()"):
    raise SystemExit("event prefix no longer freezes before post-seal suspension")
if seal_body.index("sealedAcceptedExportSnapshot =") > seal_body.index("await self.refreshLedgerSnapshot()"):
    raise SystemExit("accepted envelope no longer freezes before post-seal suspension")

path.write_text(text)
