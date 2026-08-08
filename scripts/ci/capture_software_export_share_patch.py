from pathlib import Path

p = Path("NembraApp/Features/Research/ES80CaptureShellView.swift")
s = p.read_text()

def one(old, new, label):
    global s
    c = s.count(old)
    if c != 1:
        raise SystemExit(f"{label}: expected 1 anchor, found {c}")
    s = s.replace(old, new, 1)

one(
'''    @State private var shareURL: URL?
    @State private var showingDetails = false
''',
'''    @State private var shareURL: URL?
    @State private var softwareExportData: Data?
    @State private var sharePreparationWarning: String?
    @State private var declaredStationarySetup: PassiveBluetoothStationaryCaptureSetup?
    @State private var showingDetails = false
''',
"state"
)
one(
'''        case let .correlationReady(window):
            correlationReadyPanel(window)
            primaryButton(
                "Begin \\(phaseShortName(window)) window",
                systemImage: window.operatorExpectedPowerOn ? "power.circle.fill" : "power.circle",
                identifier: "es80.capture.begin-window"
            ) {
                beginCorrelationWindow()
            }
''',
'''        case let .correlationReady(window):
            if window == .firstPoweredOff, declaredStationarySetup == nil {
                statePanel(
                    eyebrow: "PREFLIGHT / DECLARATION",
                    title: "Confirm stationary setup",
                    message: "Before OFF 1, unplug the scooter charger, keep Nembra foregrounded with the screen unlocked, and keep the stock scooter app closed. Confirm only when those are your declared setup conditions for this Experiment One run.",
                    symbol: "checkmark.shield"
                )
                primaryButton(
                    "Confirm setup",
                    systemImage: "checkmark.circle.fill",
                    identifier: "es80.capture.confirm-setup"
                ) {
                    declaredStationarySetup = PassiveBluetoothStationaryCaptureSetup(
                        chargerState: .disconnected,
                        executionContext: .foregroundUnlockedScreenOn,
                        stockAppReferenceSetup: .none
                    )
                }
                guidanceFootnote("This records your operator declaration; it is not independent proof that the condition held continuously.")
            } else {
                correlationReadyPanel(window)
                primaryButton(
                    "Begin \\(phaseShortName(window)) window",
                    systemImage: window.operatorExpectedPowerOn ? "power.circle.fill" : "power.circle",
                    identifier: "es80.capture.begin-window"
                ) {
                    beginCorrelationWindow()
                }
            }
''',
"correlation setup gate"
)
one(
'''            } else {
                primaryButton(
                    "Share unavailable",
                    systemImage: "exclamationmark.triangle",
                    disabled: true,
                    identifier: "es80.capture.share-unavailable"
                ) {}
            }
''',
'''            } else if coordinator.finalizedArtifact != nil {
                primaryButton(
                    "Prepare Share file",
                    systemImage: "arrow.clockwise",
                    identifier: "es80.capture.prepare-share"
                ) {
                    prepareSoftwareExportForShare()
                }
            } else {
                primaryButton(
                    "Share unavailable",
                    systemImage: "exclamationmark.triangle",
                    disabled: true,
                    identifier: "es80.capture.share-unavailable"
                ) {}
            }
            if let sharePreparationWarning {
                diagnosticBanner(sharePreparationWarning)
            }
''',
"share fallback"
)
one(
'''            if let artifact = coordinator.finalizedArtifact {
                Text("\\(artifact.captureJSON.count.formatted()) immutable JSON bytes are sealed from this Experiment One authority. Correlation evidence is retained with the same package-owned result; no protocol field meaning is claimed yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
''',
'''            if let artifact = coordinator.finalizedArtifact {
                let exportDescription = softwareExportData.map { " Package-owned Share envelope: \\($0.count.formatted()) bytes." } ?? ""
                Text("\\(artifact.captureJSON.count.formatted()) immutable capture bytes are sealed from this Experiment One authority. Correlation evidence remains bound to the same run.\\(exportDescription) No protocol field meaning is claimed yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
''',
"completion copy"
)
one(
'''    private func finalizeCapture() {
        guard !finalizationInFlight else { return }
        diagnosticMessage = nil
        finalizationInFlight = true

        Task {
            do {
                let artifact = try await coordinator.finalizeObservationHorizon()
                shareURL = try persistShareArtifact(artifact.captureJSON)
                finalizationInFlight = false
            } catch {
                finalizationInFlight = false
                localFailureMessage = "Capture sealing failed: \\(experimentErrorMessage(error))"
            }
        }
    }
''',
'''    private func finalizeCapture() {
        guard !finalizationInFlight else { return }
        diagnosticMessage = nil
        sharePreparationWarning = nil
        finalizationInFlight = true

        Task {
            do {
                _ = try await coordinator.finalizeObservationHorizon()
            } catch {
                finalizationInFlight = false
                localFailureMessage = "Capture sealing failed: \\(experimentErrorMessage(error))"
                return
            }

            // Horizon is already immutable here. Export/temporary-file failure is a
            // recoverable presentation problem and must never relabel seal truth.
            finalizationInFlight = false
            prepareSoftwareExportForShare()
        }
    }

    private func prepareSoftwareExportForShare() {
        guard coordinator.finalizedArtifact != nil else { return }
        guard let setup = declaredStationarySetup else {
            sharePreparationWarning = "Capture is sealed, but this run has no retained operator setup declaration. Start a fresh Experiment One rather than inventing setup provenance at export time."
            return
        }
        do {
            let data = try coordinator.encodedFinalizedSoftwareExportForCurrentApplication(
                setup: setup,
                prettyPrinted: true
            )
            softwareExportData = data
            shareURL = try persistShareArtifact(data)
            sharePreparationWarning = nil
        } catch {
            sharePreparationWarning = "Capture remains sealed, but the package-owned software Share envelope could not be prepared: \\(experimentErrorMessage(error))"
        }
    }
''',
"finalize"
)
one(
'''        shareURL = nil
        showingDetails = false
''',
'''        shareURL = nil
        softwareExportData = nil
        sharePreparationWarning = nil
        declaredStationarySetup = nil
        showingDetails = false
''',
"restart reset"
)
one(
'''            .appendingPathComponent("Nembra-ES80-Capture-\\(UUID().uuidString).json")
''',
'''            .appendingPathComponent("Nembra-ES80-FINGERPRINT-v1-SoftwareExport-\\(UUID().uuidString).json")
''',
"share filename"
)

p.write_text(s)
