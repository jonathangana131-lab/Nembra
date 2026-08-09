#!/usr/bin/env python3
from pathlib import Path

path = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
text = path.read_text(encoding="utf-8")

def require_once(marker: str, label: str, start: int = 0) -> int:
    first = text.find(marker, start)
    if first < 0:
        raise SystemExit(f"{label}: marker not found")
    if text.find(marker, first + 1) >= 0:
        raise SystemExit(f"{label}: marker is not unique")
    return first

# Keep Swift braces wholly inside the same conditional-compilation branch.
complete_start_marker = "        case .complete:\n            completionPanel\n#if DEBUG && targetEnvironment(simulator)\n"
complete_end_marker = "            if let sharePreparationWarning {\n"
complete_start = require_once(complete_start_marker, "complete action start")
complete_end = text.find(complete_end_marker, complete_start)
if complete_end < 0:
    raise SystemExit("complete action end marker not found")
text = text[:complete_start] + """        case .complete:
            completionPanel
#if DEBUG && targetEnvironment(simulator)
            if let simulatorQASnapshot {
                simulatorCompletionPrimaryAction(simulatorQASnapshot)
            } else {
                finalSharePrimaryAction
            }
#else
            finalSharePrimaryAction
#endif
""" + text[complete_end:]

primary_marker = "    private func correlationReadyPanel(_ window: PassiveBluetoothPowerCycleObservationPhase) -> some View {\n"
primary_at = require_once(primary_marker, "primary helper insertion")
text = text[:primary_at] + """    @ViewBuilder
    private var finalSharePrimaryAction: some View {
        if let finalShareTransfer {
            ShareLink(
                item: finalShareTransfer,
                preview: SharePreview(finalShareTransfer.filename)
            ) {
                Label("Share Capture", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .foregroundStyle(.black)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("es80.capture.share")
        } else if coordinator.finalizedArtifact != nil {
            primaryButton(
                finalShareIntegrityReport == nil ? "Verify Capture file" : "Retry Share file",
                systemImage: "arrow.clockwise",
                identifier: "es80.capture.prepare-share"
            ) {
                prepareFinalShareForAnalysisAndSharing()
            }
        } else {
            primaryButton(
                "Share unavailable",
                systemImage: "exclamationmark.triangle",
                disabled: true,
                identifier: "es80.capture.share-unavailable"
            ) {}
        }
    }

#if DEBUG && targetEnvironment(simulator)
    @ViewBuilder
    private func simulatorCompletionPrimaryAction(
        _ snapshot: PassiveBluetoothExperimentOneSimulatorQAFixture.Snapshot
    ) -> some View {
        if snapshot.artifactState == .shareRetry {
            primaryButton(
                "Retry Share file",
                systemImage: "arrow.clockwise",
                identifier: "es80.capture.prepare-share"
            ) {}
        } else {
            primaryButton(
                "Share Capture",
                systemImage: "square.and.arrow.up",
                identifier: "es80.capture.share"
            ) {}
        }
    }
#endif

""" + text[primary_at:]

completion_at = require_once("    private var completionPanel: some View {\n", "completion panel")
conditional_start = text.find("#if DEBUG && targetEnvironment(simulator)\n", completion_at)
conditional_end_marker = "            if coordinator.status.finalizationCleanup == .failed {\n"
conditional_end = text.find(conditional_end_marker, conditional_start)
if conditional_start < 0 or conditional_end < 0:
    raise SystemExit("completion-description conditional markers not found")
text = text[:conditional_start] + "            completionDescription\n\n" + text[conditional_end:]

capture_details_marker = "    private var captureDetailsSheet: some View {\n"
capture_details_at = require_once(capture_details_marker, "completion helper insertion")
text = text[:capture_details_at] + """    @ViewBuilder
    private var completionDescription: some View {
#if DEBUG && targetEnvironment(simulator)
        if simulatorQASnapshot != nil {
            Text("Synthetic Simulator QA presentation only. No capture artifact bytes were created, and no physical, RF, protocol, telemetry, or command evidence is claimed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            verifiedCompletionDescription
        }
#else
        verifiedCompletionDescription
#endif
    }

    @ViewBuilder
    private var verifiedCompletionDescription: some View {
        if let report = finalShareIntegrityReport {
            Text("The exact \(report.finalShareByteCount.formatted())-byte Capture passed every required file-integrity check and is ready to share for analysis. Nembra has not identified scooter data fields from this file yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if let artifact = coordinator.finalizedArtifact {
            Text("\(artifact.captureJSON.count.formatted()) Capture bytes are sealed. Nembra still needs to verify the final Share file before this run is ready for analysis.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

""" + text[capture_details_at:]

capture_details_at = require_once(capture_details_marker, "capture details body")
details_conditional_start = text.find("#if DEBUG && targetEnvironment(simulator)\n", capture_details_at)
details_end_marker = "                    Divider()\n"
details_conditional_end = text.find(details_end_marker, details_conditional_start)
if details_conditional_start < 0 or details_conditional_end < 0:
    raise SystemExit("capture-details conditional markers not found")
text = text[:details_conditional_start] + """#if DEBUG && targetEnvironment(simulator)
                    if let simulatorQASnapshot {
                        simulatorCaptureDetails(simulatorQASnapshot)
                    } else {
                        captureArtifactDetails
                    }
#else
                    captureArtifactDetails
#endif

""" + text[details_conditional_end:]

phase_marker = "    private func phase(\n"
phase_at = require_once(phase_marker, "details helper insertion")
text = text[:phase_at] + """    @ViewBuilder
    private var captureArtifactDetails: some View {
        detailRow("Correlation", value: correlationDetailValue)
        detailRow("Cleanup", value: finalizationCleanupDetailValue)

        if let report = finalShareIntegrityReport {
            detailRow("Analysis readiness", value: "Ready")
            detailRow("Recipe", value: report.experimentRecipeID.rawValue)
            detailRow("Procedure", value: report.procedureVersion)
            detailRow("Final Share bytes", value: report.finalShareByteCount.formatted())
            digestDetailRow("Final Share SHA-256", value: report.finalShareSHA256)
            digestDetailRow("Software Export SHA-256", value: report.softwareExport.envelopeSHA256)
            digestDetailRow("Capture SHA-256", value: report.softwareExport.capture.sha256)
            detailRow("Capture session", value: report.softwareExport.capture.captureSessionID.uuidString)
            detailRow("Recorded events", value: report.softwareExport.capture.recordCount.formatted())
            detailRow("Raw value events", value: report.softwareExport.capture.rawValueRecordCount.formatted())
            detailRow("Build", value: report.softwareExport.buildIdentifier)
            detailRow("Build instance", value: report.buildInstanceID)
            detailRow("Source commit", value: report.softwareExport.sourceCommitSHA)
            digestDetailRow("Runtime executable SHA-256", value: report.softwareExport.executableSHA256)
        } else if let artifact = coordinator.finalizedArtifact {
            detailRow("Analysis readiness", value: "Not yet verified")
            detailRow("Capture bytes", value: artifact.captureJSON.count.formatted())
            detailRow("Observation windows", value: artifact.powerCycleResult.windows.count.formatted())
        }
    }

#if DEBUG && targetEnvironment(simulator)
    @ViewBuilder
    private func simulatorCaptureDetails(
        _ snapshot: PassiveBluetoothExperimentOneSimulatorQAFixture.Snapshot
    ) -> some View {
        Text("SIMULATOR QA / SYNTHETIC SOFTWARE STATE")
            .font(.caption.monospaced().weight(.bold))
            .foregroundStyle(.orange)
            .accessibilityIdentifier("es80.capture.details.simulator-qa")
        detailRow("Scenario", value: snapshot.title)
        detailRow("Recipe", value: snapshot.recipeID.rawValue)
        detailRow("Physical procedure", value: "Locked")
        detailRow("Bluetooth transport", value: "Not used")
        detailRow("Capture artifact", value: "Not created")
        Text("These details describe presentation QA only. They do not read, summarize, or imply a live coordinator evidence state.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
#endif

""" + text[phase_at:]

for forbidden in (
    "} else {\n#endif\n                if let finalShareTransfer",
    "} else if let report = finalShareIntegrityReport {\n#else",
    "} else {\n#endif\n                        detailRow(\"Correlation\"",
):
    if forbidden in text:
        raise SystemExit(f"forbidden split conditional remains: {forbidden!r}")

for required in (
    "private var finalSharePrimaryAction: some View",
    "private func simulatorCompletionPrimaryAction(",
    "private var completionDescription: some View",
    "private var verifiedCompletionDescription: some View",
    "private var captureArtifactDetails: some View",
    "private func simulatorCaptureDetails(",
):
    if required not in text:
        raise SystemExit(f"missing helper after transform: {required}")

path.write_text(text, encoding="utf-8")
