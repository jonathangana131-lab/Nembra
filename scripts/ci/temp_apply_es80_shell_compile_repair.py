from pathlib import Path

path = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    text = text.replace(old, new, 1)


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
#if DEBUG && targetEnvironment(simulator)
            if let simulatorQASnapshot {
                simulatorCompletionPrimaryAction(simulatorQASnapshot)
            } else {
                finalSharePrimaryAction
            }
#else
            finalSharePrimaryAction
#endif
            if let sharePreparationWarning {
'''
replace_once(old_complete, new_complete, "complete primary action")

primary_end = '''        }
    }

    private func correlationReadyPanel(_ window: PassiveBluetoothPowerCycleObservationPhase) -> some View {
'''
primary_helpers = '''        }
    }

    @ViewBuilder
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

    private func correlationReadyPanel(_ window: PassiveBluetoothPowerCycleObservationPhase) -> some View {
'''
replace_once(primary_end, primary_helpers, "primary helpers insertion")

old_completion_description = '''#if DEBUG && targetEnvironment(simulator)
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
replace_once(old_completion_description, "            completionDescription\n", "completion description")

completion_end = '''        .accessibilityIdentifier("es80.capture.complete")
    }

    private var captureDetailsSheet: some View {
'''
completion_helpers = '''        .accessibilityIdentifier("es80.capture.complete")
    }

    @ViewBuilder
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

    private var captureDetailsSheet: some View {
'''
replace_once(completion_end, completion_helpers, "completion helpers insertion")

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
new_details = '''#if DEBUG && targetEnvironment(simulator)
                    if let simulatorQASnapshot {
                        simulatorCaptureDetails(simulatorQASnapshot)
                    } else {
                        captureArtifactDetails
                    }
#else
                    captureArtifactDetails
#endif
'''
replace_once(old_details, new_details, "capture details")

details_end = '''        .preferredColorScheme(.dark)
    }

    private func phase(
'''
details_helpers = '''        .preferredColorScheme(.dark)
    }

    @ViewBuilder
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

    private func phase(
'''
replace_once(details_end, details_helpers, "details helpers insertion")

for forbidden in [
    "} else {\n#endif\n                if let finalShareTransfer",
    "} else if let report = finalShareIntegrityReport {\n#else",
    "} else {\n#endif\n                        detailRow(\"Correlation\"",
]:
    if forbidden in text:
        raise SystemExit(f"forbidden split conditional remains: {forbidden}")

for required in [
    "private var finalSharePrimaryAction: some View",
    "private var completionDescription: some View",
    "private var captureArtifactDetails: some View",
    "private func simulatorCompletionPrimaryAction(",
    "private func simulatorCaptureDetails(",
]:
    if required not in text:
        raise SystemExit(f"missing helper: {required}")

path.write_text(text, encoding="utf-8")
