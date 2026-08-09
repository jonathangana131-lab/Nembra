from pathlib import Path

path = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
text = path.read_text()

old_complete = '''        case .complete:
            completionPanel
#if DEBUG && targetEnvironment(simulator)
            if let simulatorQASnapshot {
                if simulatorQASnapshot.artifactState == .shareRetry {
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
            } else {
#endif
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
#if DEBUG && targetEnvironment(simulator)
            }
#endif
            if let sharePreparationWarning {
'''
new_complete = '''        case .complete:
            completionPanel
            completionShareAction
            if let sharePreparationWarning {
'''

insertion_anchor = '''    private func correlationReadyPanel(_ window: PassiveBluetoothPowerCycleObservationPhase) -> some View {
'''
completion_helpers = '''    @ViewBuilder
    private var completionShareAction: some View {
#if DEBUG && targetEnvironment(simulator)
        if let simulatorQASnapshot {
            if simulatorQASnapshot.artifactState == .shareRetry {
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
        } else {
            liveCompletionShareAction
        }
#else
        liveCompletionShareAction
#endif
    }

    @ViewBuilder
    private var liveCompletionShareAction: some View {
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

'''

old_completion_copy = '''#if DEBUG && targetEnvironment(simulator)
            if simulatorQASnapshot != nil {
                Text("Synthetic Simulator QA presentation only. No capture artifact bytes were created, and no physical, RF, protocol, telemetry, or command evidence is claimed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let report = finalShareIntegrityReport {
#else
            if let report = finalShareIntegrityReport {
#endif
                Text("The exact \\(report.finalShareByteCount.formatted())-byte Capture passed every required file-integrity check and is ready to share for analysis. Nembra has not identified scooter data fields from this file yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let artifact = coordinator.finalizedArtifact {
                Text("\\(artifact.captureJSON.count.formatted()) Capture bytes are sealed. Nembra still needs to verify the final Share file before this run is ready for analysis.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
'''
new_completion_copy = '''            completionEvidenceCopy
'''

completion_anchor = '''    private var completionPanel: some View {
'''
completion_copy_helpers = '''    @ViewBuilder
    private var completionEvidenceCopy: some View {
#if DEBUG && targetEnvironment(simulator)
        if simulatorQASnapshot != nil {
            Text("Synthetic Simulator QA presentation only. No capture artifact bytes were created, and no physical, RF, protocol, telemetry, or command evidence is claimed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            liveCompletionEvidenceCopy
        }
#else
        liveCompletionEvidenceCopy
#endif
    }

    @ViewBuilder
    private var liveCompletionEvidenceCopy: some View {
        if let report = finalShareIntegrityReport {
            Text("The exact \\(report.finalShareByteCount.formatted())-byte Capture passed every required file-integrity check and is ready to share for analysis. Nembra has not identified scooter data fields from this file yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if let artifact = coordinator.finalizedArtifact {
            Text("\\(artifact.captureJSON.count.formatted()) Capture bytes are sealed. Nembra still needs to verify the final Share file before this run is ready for analysis.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

'''

old_details = '''#if DEBUG && targetEnvironment(simulator)
                    if let simulatorQASnapshot {
                        Text("SIMULATOR QA / SYNTHETIC SOFTWARE STATE")
                            .font(.caption.monospaced().weight(.bold))
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("es80.capture.details.simulator-qa")
                        detailRow("Scenario", value: simulatorQASnapshot.title)
                        detailRow("Recipe", value: simulatorQASnapshot.recipeID.rawValue)
                        detailRow("Physical procedure", value: "Locked")
                        detailRow("Bluetooth transport", value: "Not used")
                        detailRow("Capture artifact", value: "Not created")
                        Text("These details describe presentation QA only. They do not read, summarize, or imply a live coordinator evidence state.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
#endif
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
#if DEBUG && targetEnvironment(simulator)
                    }
#endif
'''
new_details = '''                    captureDetailsRows
'''

details_anchor = '''    private func phase(
'''
details_helpers = '''    @ViewBuilder
    private var captureDetailsRows: some View {
#if DEBUG && targetEnvironment(simulator)
        if let simulatorQASnapshot {
            Text("SIMULATOR QA / SYNTHETIC SOFTWARE STATE")
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(.orange)
                .accessibilityIdentifier("es80.capture.details.simulator-qa")
            detailRow("Scenario", value: simulatorQASnapshot.title)
            detailRow("Recipe", value: simulatorQASnapshot.recipeID.rawValue)
            detailRow("Physical procedure", value: "Locked")
            detailRow("Bluetooth transport", value: "Not used")
            detailRow("Capture artifact", value: "Not created")
            Text("These details describe presentation QA only. They do not read, summarize, or imply a live coordinator evidence state.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            liveCaptureDetailsRows
        }
#else
        liveCaptureDetailsRows
#endif
    }

    @ViewBuilder
    private var liveCaptureDetailsRows: some View {
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

'''

replacements = [
    (old_complete, new_complete, "complete share action"),
    (insertion_anchor, completion_helpers + insertion_anchor, "completion action helpers"),
    (old_completion_copy, new_completion_copy, "completion evidence copy"),
    (completion_anchor, completion_copy_helpers + completion_anchor, "completion evidence helpers"),
    (old_details, new_details, "details rows"),
    (details_anchor, details_helpers + details_anchor, "details helpers"),
]

for old, new, label in replacements:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    text = text.replace(old, new, 1)

path.write_text(text)
