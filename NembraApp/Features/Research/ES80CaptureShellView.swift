@preconcurrency import CoreBluetooth
import Dispatch
import Foundation
import NembraBluetoothCapture
import SwiftUI
import UIKit

/// Product-facing Nembra Capture shell for ES80 Experiment One.
///
/// One package-owned coordinator now carries the complete software provenance life from
/// OFF1 -> ON1 -> OFF2 -> ON2 through explicit correlated-target confirmation, fresh
/// post-admission rediscovery, passive acquisition, Ready, monotonic Horizon, immutable sealing,
/// and one package-owned verifiable software-export envelope. SwiftUI never constructs a second
/// correlation producer, never selects an authoritative UUID, and never receives the sealed
/// admission or mutable recorder.
///
/// A repeated full CoreBluetooth UUID remains correlated Bluetooth-target evidence only. It is
/// not permanent hardware authentication, RF emission-time proof, protocol semantics, or telemetry.
@MainActor
struct ES80CaptureShellView: View {
    private enum Phase: Equatable {
        case physicalProcedureLocked
        case bluetoothUnavailable(String)
        case correlationReady(PassiveBluetoothPowerCycleObservationPhase)
        case correlationStarting(PassiveBluetoothPowerCycleObservationPhase)
        case correlationObserving(PassiveBluetoothPowerCycleObservationPhase)
        case correlationFailed(String)
        case noRepeatableTarget
        case ambiguousTargets(Int)
        case correlatedTarget
        case rediscoveringTarget
        case targetReacquired
        case connecting
        case acquiring
        case observing
        case readyToSeal
        case finalizing
        case complete
        case failed(String)
    }

    private static let requiredCorrelationWindowDuration: TimeInterval = 10
    private static let requiredCorrelationWindowNanoseconds: UInt64 = 10_000_000_000
    private static let requiredObservationGuidanceNanoseconds: UInt64 = 60_000_000_000

    @Environment(\.scenePhase) private var scenePhase

    @State private var coordinator: PassiveBluetoothExperimentOneCoordinator
    @State private var observedScanBeganAtUptimeNanoseconds: UInt64?
    @State private var observationReadyBeganAtUptimeNanoseconds: UInt64?
    @State private var captureConnectionAttempted = false
    @State private var finalizationInFlight = false
    @State private var diagnosticMessage: String?
    @State private var localFailureMessage: String?
    @State private var shareURL: URL?
    @State private var softwareExport: PassiveBluetoothExperimentOneSoftwareExport?
    @State private var softwareExportByteCount: Int?
    @State private var showingDetails = false

    init(coordinator: PassiveBluetoothExperimentOneCoordinator) {
        _coordinator = State(initialValue: coordinator)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let status = coordinator.status
            let currentPhase = phase(status: status)
            let now = DispatchTime.now().uptimeNanoseconds

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero(for: currentPhase)
                    passiveSafetyPanel
                    progressRail(status: status)
                    primaryContent(
                        for: currentPhase,
                        status: status,
                        nowUptimeNanoseconds: now
                    )

                    if let diagnosticMessage {
                        diagnosticBanner(diagnosticMessage)
                    }
                }
                .frame(maxWidth: 660)
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 42)
                .frame(maxWidth: .infinity)
            }
            .background(Color.black.ignoresSafeArea())
            .onAppear {
                synchronizeIdleTimer(for: currentPhase)
                synchronizeObservedScanClock(isScanning: status.powerCycleProgress?.isScanning == true)
                synchronizeObservationReadyClock(isReady: status.observationReady)
            }
            .onChange(of: currentPhase) { _, newPhase in
                synchronizeIdleTimer(for: newPhase)
            }
            .onChange(of: status.powerCycleProgress?.isScanning == true) { _, isScanning in
                synchronizeObservedScanClock(isScanning: isScanning)
            }
            .onChange(of: status.observationReady) { _, isReady in
                synchronizeObservationReadyClock(isReady: isReady)
            }
        }
        .navigationTitle("Nembra Capture")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: scenePhase) { _, newScenePhase in
            handleScenePhaseChange(newScenePhase)
        }
        .sheet(isPresented: $showingDetails) {
            captureDetailsSheet
        }
        .accessibilityIdentifier("es80.capture-shell")
    }

    private func hero(for phase: Phase) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .frame(width: 52, height: 52)

                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("NEMBRA CAPTURE")
                        .font(.caption.monospaced().weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)

                    Text(heroTitle(for: phase))
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Image(systemName: statusSymbol(for: phase))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusColor(for: phase))
                    .accessibilityHidden(true)

                Text(statusTitle(for: phase))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer(minLength: 8)

                Text("PASSIVE / READ ONLY")
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var passiveSafetyPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("One sealed evidence life")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Nembra carries the same package-owned Experiment One authority from repeated Bluetooth correlation into passive capture and immutable Horizon sealing. It performs no application characteristic-value writes and never turns a display name, RSSI, or service hint into target authority.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("es80.capture.single-authority")
    }

    private func progressRail(
        status: PassiveBluetoothExperimentOneCoordinator.Status
    ) -> some View {
        let completed = status.powerCycleProgress?.completedWindowCount
            ?? coordinator.powerCycleResult?.windows.count
            ?? 0
        let current = status.powerCycleProgress?.phase.rawValue

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("EXPERIMENT ONE")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(progressStage(status: status, completedWindows: completed))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(progressSegmentFill(
                            index: index,
                            completedWindows: completed,
                            currentWindow: current,
                            status: status
                        ))
                        .frame(height: 5)
                }
            }

            HStack {
                Text("OFF 1")
                Spacer()
                Text("ON 1")
                Spacer()
                Text("OFF 2")
                Spacer()
                Text("ON 2")
                Spacer()
                Text("READY")
                Spacer()
                Text("SEAL")
            }
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progressAccessibilityLabel(status: status, completedWindows: completed))
        .accessibilityIdentifier("es80.capture.experiment-progress")
    }

    @ViewBuilder
    private func primaryContent(
        for phase: Phase,
        status: PassiveBluetoothExperimentOneCoordinator.Status,
        nowUptimeNanoseconds: UInt64
    ) -> some View {
        switch phase {
        case .physicalProcedureLocked:
            statePanel(
                eyebrow: "FIELD AUTHORITY",
                title: "This build is not authorized",
                message: "The package-owned physical execution gate is closed. No OFF / ON window, connection, capture, or seal action can advance through this coordinator.",
                symbol: "lock.shield.fill"
            )

        case let .bluetoothUnavailable(message):
            statePanel(
                eyebrow: "PREFLIGHT",
                title: "Bluetooth is not ready",
                message: message,
                symbol: "antenna.radiowaves.left.and.right.slash"
            )
            primaryButton(
                "Begin OFF 1 window",
                systemImage: "power",
                disabled: true,
                identifier: "es80.capture.begin-window"
            ) {}

        case let .correlationReady(window):
            correlationReadyPanel(window)
            primaryButton(
                "Begin \(phaseShortName(window)) window",
                systemImage: window.operatorExpectedPowerOn ? "power.circle.fill" : "power.circle",
                identifier: "es80.capture.begin-window"
            ) {
                beginCorrelationWindow()
            }

        case let .correlationStarting(window):
            statePanel(
                eyebrow: "\(phaseShortName(window)) / STARTING",
                title: "Opening a fresh scan window",
                message: "Nembra is waiting for this exact window to report Bluetooth powered-on and active scanning. The producer's evidence clock has not started yet.",
                symbol: "dot.radiowaves.left.and.right"
            )
            ProgressView()
                .tint(.white)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .correlationObserving(window):
            correlationObservingPanel(
                window,
                nowUptimeNanoseconds: nowUptimeNanoseconds
            )

            let remaining = correlationGuidanceRemainingSeconds(
                nowUptimeNanoseconds: nowUptimeNanoseconds
            )
            primaryButton(
                remaining == 0 ? "Complete \(phaseShortName(window)) window" : "Hold state — \(remaining)s",
                systemImage: remaining == 0 ? "checkmark.circle.fill" : "timer",
                disabled: remaining != 0,
                identifier: "es80.capture.complete-window"
            ) {
                completeCorrelationWindow()
            }

            guidanceFootnote("This countdown is display guidance only. The package producer accepts the window only from its own monotonic receipt boundary; tapping early cannot create evidence.")

        case let .correlationFailed(message):
            statePanel(
                eyebrow: "CORRELATION STOPPED",
                title: "Restart from OFF 1",
                message: message,
                symbol: "arrow.counterclockwise.circle"
            )
            primaryButton(
                "Restart Experiment One",
                systemImage: "arrow.counterclockwise",
                identifier: "es80.capture.restart-correlation"
            ) {
                restartExperiment()
            }

        case .noRepeatableTarget:
            statePanel(
                eyebrow: "NO UNIQUE TARGET",
                title: "No scooter signal repeated twice",
                message: "No selectable full Bluetooth identifier was absent in both OFF windows and repeated in both ON windows. Nembra will not guess from name, signal strength, service hints, or short IDs.",
                symbol: "questionmark.circle"
            )
            primaryButton(
                "Repeat all four windows",
                systemImage: "arrow.counterclockwise",
                identifier: "es80.capture.restart-correlation"
            ) {
                restartExperiment()
            }

        case let .ambiguousTargets(count):
            statePanel(
                eyebrow: "AMBIGUOUS TARGET",
                title: "\(count) signals followed the same pattern",
                message: "More than one selectable full Bluetooth identifier repeated the OFF / ON pattern. Nembra refuses to break the tie with display name, RSSI, services, or a short identifier.",
                symbol: "point.3.filled.connected.trianglepath.dotted"
            )
            primaryButton(
                "Repeat all four windows",
                systemImage: "arrow.counterclockwise",
                identifier: "es80.capture.restart-correlation"
            ) {
                restartExperiment()
            }

        case .correlatedTarget:
            statePanel(
                eyebrow: "SCOOTER SIGNAL FOUND",
                title: "One target repeated twice",
                message: "One full CoreBluetooth identifier was selectable in both ON windows and absent from both OFF catalogs under this exact package-owned observation series. Treat it only as a correlated Bluetooth target.",
                symbol: "checkmark.circle"
            )
            primaryButton(
                "Confirm correlated target",
                systemImage: "checkmark.shield",
                identifier: "es80.capture.confirm-correlated-target"
            ) {
                confirmCorrelatedTarget()
            }

        case .rediscoveringTarget:
            statePanel(
                eyebrow: "TARGET CONFIRMED",
                title: "Reacquiring the exact signal",
                message: "A fresh post-admission scan is looking for the exact full identifier that passed both OFF / ON cycles. Keep the scooter in the ON state from the final window.",
                symbol: "scope"
            )
            ProgressView()
                .tint(.white)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)
            secondaryButton(
                "Restart rediscovery",
                systemImage: "arrow.clockwise",
                identifier: "es80.capture.restart-rediscovery"
            ) {
                restartRediscovery()
            }

        case .targetReacquired:
            statePanel(
                eyebrow: "CORRELATED TARGET",
                title: "Exact signal reacquired",
                message: "The same full CoreBluetooth identifier reappeared in the fresh scan epoch created after the sealed admission. This remains local correlation evidence, not permanent hardware authentication.",
                symbol: "checkmark.circle"
            )
            primaryButton(
                "Begin passive observation",
                systemImage: "wave.3.right",
                identifier: "es80.capture.connect-prepared-target"
            ) {
                connectPreparedCapture()
            }

        case .connecting:
            statePanel(
                eyebrow: "PASSIVE CONNECTION",
                title: "Opening the correlated target",
                message: "Nembra is connecting only to the package-owned correlated target. No application characteristic-value writes are permitted by this workflow.",
                symbol: "link"
            )
            ProgressView()
                .tint(.white)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .acquiring:
            statePanel(
                eyebrow: "PASSIVE ACQUISITION",
                title: "Learning the readable surface",
                message: "Nembra is passively discovering services, characteristics, descriptors, reads, and notifications for the exact run-owned target session. Ready is not shown until finite acquisition is mechanically complete.",
                symbol: "waveform.path.ecg.rectangle"
            )
            ProgressView()
                .tint(.white)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .observing:
            let remaining = observationGuidanceRemainingSeconds(
                nowUptimeNanoseconds: nowUptimeNanoseconds
            )
            statePanel(
                eyebrow: "OBSERVATION READY",
                title: remaining == 0 ? "Waiting for accepted Horizon authority" : "Hold observation — \(remaining)s",
                message: "Finite acquisition is Ready. Keep Nembra foregrounded and the scooter stationary while the accepted monotonic observation interval matures. The displayed timer is guidance only.",
                symbol: "timer"
            )
            observationHealthStrip(status: status)
            primaryButton(
                status.canFinalizeObservationHorizon ? "Seal Capture" : "Observation in progress",
                systemImage: status.canFinalizeObservationHorizon ? "checkmark.seal.fill" : "timer",
                disabled: !status.canFinalizeObservationHorizon,
                identifier: "es80.capture.finish"
            ) {
                finalizeCapture()
            }

        case .readyToSeal:
            statePanel(
                eyebrow: "HORIZON READY",
                title: "Capture can be sealed",
                message: "The package-owned Ready epoch and required monotonic observation duration are both accepted. Finishing now requests one immutable Horizon from this same authority life.",
                symbol: "checkmark.seal"
            )
            observationHealthStrip(status: status)
            primaryButton(
                "Seal Capture",
                systemImage: "checkmark.seal.fill",
                identifier: "es80.capture.finish"
            ) {
                finalizeCapture()
            }

        case .finalizing:
            statePanel(
                eyebrow: "SEALING",
                title: "Freezing immutable evidence",
                message: "Nembra is draining the accepted cutoff, committing Horizon, checking final authority, and preparing one verifiable software export from the exact sealed bytes. Do not leave the app while this finishes.",
                symbol: "lock.doc"
            )
            ProgressView()
                .tint(.white)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .complete:
            completionPanel
            if let shareURL {
                ShareLink(item: shareURL) {
                    Label("Share Capture", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 56)
                        .foregroundStyle(.black)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shares the verified Experiment One software artifact containing the exact sealed capture bytes, four-window correlation evidence, manifest, and runtime build provenance.")
                .accessibilityIdentifier("es80.capture.share")
            } else {
                primaryButton(
                    "Share unavailable",
                    systemImage: "exclamationmark.triangle",
                    disabled: true,
                    identifier: "es80.capture.share-unavailable"
                ) {}
            }
            secondaryButton(
                "View Details",
                systemImage: "doc.text.magnifyingglass",
                identifier: "es80.capture.view-details"
            ) {
                showingDetails = true
            }

        case let .failed(message):
            statePanel(
                eyebrow: "CAPTURE STOPPED",
                title: "Evidence failed closed",
                message: message,
                symbol: "exclamationmark.triangle"
            )
            primaryButton(
                "Start a fresh Experiment One",
                systemImage: "arrow.counterclockwise",
                identifier: "es80.capture.restart-experiment"
            ) {
                restartExperiment()
            }
        }
    }

    private func correlationReadyPanel(_ window: PassiveBluetoothPowerCycleObservationPhase) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(phaseShortName(window)) / READY")
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(.secondary)

            Text(window.operatorExpectedPowerOn ? "Scooter ON" : "Scooter OFF")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            Text(window.operatorExpectedPowerOn
                 ? "Set the scooter to ON, keep the charger disconnected and the stock app closed, then begin this bounded observation window."
                 : "Set the scooter fully OFF, keep the charger disconnected and the stock app closed, then begin this bounded observation window.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func correlationObservingPanel(
        _ window: PassiveBluetoothPowerCycleObservationPhase,
        nowUptimeNanoseconds: UInt64
    ) -> some View {
        let remaining = correlationGuidanceRemainingSeconds(nowUptimeNanoseconds: nowUptimeNanoseconds)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(phaseShortName(window)) / LIVE")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(remaining == 0 ? "READY" : "\(remaining)s")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
            }

            Text(window.operatorExpectedPowerOn ? "Keep the scooter ON." : "Keep the scooter OFF.")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            Text("Nembra is recording the bounded CoreBluetooth advertisement catalog for this exact window. Keep the charger disconnected, the phone nearby, and the app foregrounded; do not open the stock scooter app during this series.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func observationHealthStrip(
        status: PassiveBluetoothExperimentOneCoordinator.Status
    ) -> some View {
        HStack(spacing: 12) {
            healthItem("TARGET", value: status.connection == .connected ? "BOUND" : "WAIT")
            Divider().frame(height: 28).overlay(.white.opacity(0.12))
            healthItem("FINITE", value: status.observationReady ? "READY" : "WAIT")
            Divider().frame(height: 28).overlay(.white.opacity(0.12))
            healthItem("HORIZON", value: status.canFinalizeObservationHorizon ? "READY" : "HOLD")
        }
        .padding(14)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Capture health. Target bound. Finite acquisition \(status.observationReady ? "ready" : "waiting"). Horizon \(status.canFinalizeObservationHorizon ? "ready" : "waiting").")
    }

    private var completionPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 52, height: 52)
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.black)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("CAPTURE COMPLETE")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(softwareExport == nil ? "Evidence sealed" : "Ready for analysis")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }

            if let softwareExport, let softwareExportByteCount {
                Text("\(softwareExport.captureJSON.count.formatted()) immutable capture JSON bytes and all four correlation windows are packaged into a \(softwareExportByteCount.formatted())-byte verified software artifact with manifest-v3 and exact runtime build provenance. Independent field-build authorization is still separate, and no protocol field meaning or physical ES80 authentication is claimed yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let artifact = coordinator.finalizedArtifact {
                Text("\(artifact.captureJSON.count.formatted()) immutable capture JSON bytes are sealed and retained with this Experiment One authority, but final export preparation failed closed. Share remains blocked so raw controller JSON cannot masquerade as the completed software artifact.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("es80.capture.complete")
    }

    private var captureDetailsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Experiment One")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    detailRow("Recipe", value: PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue)
                    detailRow("Correlation", value: correlationDetailValue)
                    if let artifact = coordinator.finalizedArtifact {
                        detailRow("Capture bytes", value: artifact.captureJSON.count.formatted())
                        detailRow("Observation windows", value: artifact.powerCycleResult.windows.count.formatted())
                    }
                    if let softwareExport, let softwareExportByteCount {
                        detailRow("Software artifact", value: "\(softwareExportByteCount.formatted()) bytes")
                        detailRow("Build", value: softwareExport.build.buildIdentifier)
                        detailRow("Build instance", value: softwareExport.build.buildInstanceID)
                        detailRow("Source commit", value: softwareExport.build.sourceCommitSHA)
                        detailRow("Executable SHA-256", value: softwareExport.build.executableSHA256)
                    }

                    Divider()

                    Text("Truth boundary")
                        .font(.headline)
                    Text("This export is passive software evidence. Repeated full-UUID correlation does not authenticate the physical ES80, and build-instance/runtime hashes do not independently authorize a field build. This screen does not assign GATT, Tuya/DP, battery, current, power, speed, regen, or command semantics.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(22)
                .frame(maxWidth: 660, alignment: .leading)
            }
            .navigationTitle("Capture Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingDetails = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func phase(
        status: PassiveBluetoothExperimentOneCoordinator.Status
    ) -> Phase {
        if let localFailureMessage {
            return .failed(localFailureMessage)
        }
        guard status.physicalProcedurePermitted else {
            return .physicalProcedureLocked
        }
        if status.foregroundIntegrityLost {
            return .failed("Nembra left the active foreground after Experiment One began. This evidence life cannot regain capture authority; start a fresh Experiment One.")
        }
        if finalizationInFlight {
            return .finalizing
        }
        if status.artifactFinalized || coordinator.finalizedArtifact != nil {
            return .complete
        }

        switch status.connection {
        case .connecting:
            return .connecting
        case .connected:
            if status.canFinalizeObservationHorizon {
                return .readyToSeal
            }
            if status.observationReady {
                return .observing
            }
            return .acquiring
        case .idle:
            if captureConnectionAttempted && !status.hasPreparedCaptureAdmission {
                return .failed(coordinator.lastDiagnostic ?? "The passive target connection ended before an accepted observation could be sealed. Start a fresh Experiment One rather than replaying consumed authority.")
            }
        case .unavailable:
            return .bluetoothUnavailable("The package-owned CoreBluetooth controller is unavailable for this coordinator.")
        }

        if status.hasPreparedCaptureAdmission {
            return status.isCorrelatedTargetRediscovered ? .targetReacquired : .rediscoveringTarget
        }

        switch status.correlation {
        case .invalidEvidence:
            return .correlationFailed("The four windows did not preserve one valid package-issued observation authority and required OFF 1, ON 1, OFF 2, ON 2 ordering.")
        case .noRepeatableCandidate:
            return .noRepeatableTarget
        case let .ambiguousRepeatableCandidates(count):
            return .ambiguousTargets(count)
        case .singleRepeatableCandidate:
            return .correlatedTarget
        case .incomplete:
            break
        }

        if status.bluetoothState != .poweredOn {
            return .bluetoothUnavailable(bluetoothUnavailableMessage(status.bluetoothState))
        }
        guard let progress = status.powerCycleProgress else {
            return .correlationFailed("The package-owned Experiment One workflow has no active correlation progress and no final result.")
        }
        if progress.isSeriesInvalidated {
            return .correlationFailed("A known Bluetooth, scan-liveness, or foreground gap invalidated this four-window observation series.")
        }
        if progress.isScanning {
            return .correlationObserving(progress.phase)
        }
        if progress.isAwaitingBluetoothPower || progress.isAwaitingScanReadiness {
            return .correlationStarting(progress.phase)
        }
        return .correlationReady(progress.phase)
    }

    private func beginCorrelationWindow() {
        diagnosticMessage = nil
        do {
            try coordinator.startCurrentPowerCycleWindow()
        } catch {
            diagnosticMessage = experimentErrorMessage(error)
        }
    }

    private func completeCorrelationWindow() {
        diagnosticMessage = nil
        do {
            _ = try coordinator.finishCurrentPowerCycleWindow()
            observedScanBeganAtUptimeNanoseconds = nil
        } catch {
            diagnosticMessage = experimentErrorMessage(error)
        }
    }

    private func confirmCorrelatedTarget() {
        diagnosticMessage = nil
        do {
            try coordinator.confirmCorrelatedTargetAndBeginRediscovery()
        } catch {
            diagnosticMessage = experimentErrorMessage(error)
        }
    }

    private func restartRediscovery() {
        diagnosticMessage = nil
        do {
            try coordinator.restartPreparedRediscovery()
        } catch {
            diagnosticMessage = experimentErrorMessage(error)
        }
    }

    private func connectPreparedCapture() {
        diagnosticMessage = nil
        do {
            try coordinator.connectPreparedCapture()
            captureConnectionAttempted = true
        } catch {
            diagnosticMessage = experimentErrorMessage(error)
        }
    }

    private func finalizeCapture() {
        guard !finalizationInFlight else { return }
        diagnosticMessage = nil
        finalizationInFlight = true

        Task {
            do {
                _ = try await coordinator.finalizeObservationHorizon()
                do {
                    let setup = PassiveBluetoothStationaryCaptureSetup(
                        chargerState: .disconnected,
                        executionContext: .foregroundUnlockedScreenOn,
                        stockAppReferenceSetup: .none
                    )
                    let export = try coordinator.finalizedSoftwareExportForCurrentApplication(
                        setup: setup
                    )
                    let encoded = try PassiveBluetoothExperimentOneSoftwareExportCodec.encode(export)
                    let verified = try PassiveBluetoothExperimentOneSoftwareExportCodec.decodeAndVerify(encoded)
                    softwareExport = verified
                    softwareExportByteCount = encoded.count
                    shareURL = try persistShareArtifact(encoded)
                } catch {
                    softwareExport = nil
                    softwareExportByteCount = nil
                    shareURL = nil
                    diagnosticMessage = exportPreparationErrorMessage(error)
                }
                finalizationInFlight = false
            } catch {
                finalizationInFlight = false
                localFailureMessage = "Capture sealing failed: \(experimentErrorMessage(error))"
            }
        }
    }

    private func restartExperiment() {
        coordinator.abandonExperiment()
        diagnosticMessage = nil
        localFailureMessage = nil
        captureConnectionAttempted = false
        finalizationInFlight = false
        if let shareURL {
            try? FileManager.default.removeItem(at: shareURL)
        }
        shareURL = nil
        softwareExport = nil
        softwareExportByteCount = nil
        showingDetails = false
        observedScanBeganAtUptimeNanoseconds = nil
        observationReadyBeganAtUptimeNanoseconds = nil

        do {
            coordinator = try PassiveBluetoothExperimentOneCoordinator()
        } catch {
            localFailureMessage = "Nembra could not create a fresh package-owned Experiment One workflow: \(String(describing: error))"
        }
    }

    private func handleScenePhaseChange(_ newScenePhase: ScenePhase) {
        guard newScenePhase != .active else { return }
        coordinator.invalidateForForegroundLoss()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func synchronizeIdleTimer(for phase: Phase) {
        switch phase {
        case .correlationStarting,
             .correlationObserving,
             .rediscoveringTarget,
             .targetReacquired,
             .connecting,
             .acquiring,
             .observing,
             .readyToSeal,
             .finalizing:
            UIApplication.shared.isIdleTimerDisabled = true
        default:
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func synchronizeObservedScanClock(isScanning: Bool) {
        if isScanning {
            if observedScanBeganAtUptimeNanoseconds == nil {
                observedScanBeganAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
            }
        } else {
            observedScanBeganAtUptimeNanoseconds = nil
        }
    }

    private func synchronizeObservationReadyClock(isReady: Bool) {
        if isReady {
            if observationReadyBeganAtUptimeNanoseconds == nil {
                observationReadyBeganAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
            }
        } else {
            observationReadyBeganAtUptimeNanoseconds = nil
        }
    }

    private func correlationGuidanceRemainingSeconds(nowUptimeNanoseconds: UInt64) -> Int {
        guard let beganAt = observedScanBeganAtUptimeNanoseconds,
              nowUptimeNanoseconds >= beganAt else {
            return Int(Self.requiredCorrelationWindowDuration)
        }
        let elapsed = nowUptimeNanoseconds - beganAt
        guard elapsed < Self.requiredCorrelationWindowNanoseconds else { return 0 }
        let remaining = Self.requiredCorrelationWindowNanoseconds - elapsed
        return Int((remaining + 999_999_999) / 1_000_000_000)
    }

    private func observationGuidanceRemainingSeconds(nowUptimeNanoseconds: UInt64) -> Int {
        guard let beganAt = observationReadyBeganAtUptimeNanoseconds,
              nowUptimeNanoseconds >= beganAt else {
            return 60
        }
        let elapsed = nowUptimeNanoseconds - beganAt
        guard elapsed < Self.requiredObservationGuidanceNanoseconds else { return 0 }
        let remaining = Self.requiredObservationGuidanceNanoseconds - elapsed
        return Int((remaining + 999_999_999) / 1_000_000_000)
    }

    private func persistShareArtifact(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Nembra-ES80-Experiment-One-\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func exportPreparationErrorMessage(_ error: Error) -> String {
        if let error = error as? PassiveBluetoothCaptureRuntimeBuildIdentityError {
            switch error {
            case .missingBuildIdentifier, .invalidBuildIdentifier:
                return "Capture is sealed, but Share is blocked because this running app does not carry a valid Nembra field-build identifier. The sealed evidence remains retained in this session."
            case .missingBuildInstanceID, .invalidBuildInstanceID:
                return "Capture is sealed, but Share is blocked because this running app does not carry a valid produced-build instance identifier. The sealed evidence remains retained in this session."
            case .missingSourceCommitSHA, .invalidSourceCommitSHA:
                return "Capture is sealed, but Share is blocked because this running app does not carry an exact source-commit provenance value. The sealed evidence remains retained in this session."
            case .executableUnavailable, .executableNotRegularFile, .executableUnreadable:
                return "Capture is sealed, but Share is blocked because Nembra could not hash the exact running executable for software-artifact provenance. The sealed evidence remains retained in this session."
            }
        }
        if error is PassiveBluetoothExperimentOneSoftwareExportError ||
            error is PassiveBluetoothStationaryCaptureManifestError {
            return "Capture is sealed, but Share is blocked because the final software artifact failed its package-owned correlation, manifest, capture-byte, or build-provenance integrity checks. The sealed evidence remains retained in this session."
        }
        return "Capture is sealed, but Share is blocked because Nembra could not persist the verified software artifact. The sealed evidence remains retained in this session."
    }

    private func experimentErrorMessage(_ error: Error) -> String {
        if let error = error as? PassiveBluetoothExperimentOneCoordinator.CoordinatorError {
            switch error {
            case .physicalProcedureLocked:
                return "The package-owned physical execution gate is closed for this build."
            case .foregroundIntegrityLost:
                return "Foreground integrity was lost after Experiment One began. Start a fresh experiment."
            case .captureAdmissionAlreadyPrepared:
                return "The correlated-target admission is already prepared. Continue the current rediscovery."
            case .captureAdmissionNotPrepared:
                return "No sealed correlated-target admission is ready for this step."
            case .correlationIncomplete:
                return "All four OFF / ON windows must complete before target confirmation."
            case .correlationEvidenceInvalid:
                return "The four-window evidence authority or ordering is invalid."
            case .correlationNotUnique:
                return "The four-window series did not produce exactly one repeatable target."
            case .targetNotRediscovered:
                return "The exact correlated target has not reappeared in the fresh post-admission scan yet. Keep scanning and retry."
            case .targetNotConnectable:
                return "The exact correlated target is visible but CoreBluetooth reports it as non-connectable."
            case .controllerUnavailable:
                return "The package-owned passive capture controller is unavailable."
            case .observationNotReady:
                return "The accepted Ready epoch and minimum monotonic observation interval are not complete yet."
            case .artifactAlreadyFinalized:
                return "This Experiment One artifact is already immutable."
            }
        }

        if let error = error as? PassiveBluetoothPowerCycleObservationSessionError {
            switch error {
            case .invalidMinimumWindowDuration:
                return "The accepted correlation-window duration is invalid in this build."
            case .seriesComplete:
                return "All four correlation windows are already sealed."
            case .seriesInvalidated:
                return "This correlation series was invalidated by a known evidence gap."
            case .windowAlreadyActive:
                return "The current correlation window is already active."
            case .windowNotActive:
                return "No correlation window is currently active."
            case .bluetoothBecameUnavailable:
                return "Bluetooth became unavailable during the bounded window."
            case .scanReadinessPending:
                return "Scanning was requested, but the authoritative receipt window has not opened yet."
            case .scanReadinessTimedOut:
                return "CoreBluetooth never confirmed scan readiness inside the bounded startup interval."
            case .scanBecameInactive:
                return "The exact window's CoreBluetooth scan became inactive."
            case .minimumWindowDurationNotReached:
                return "The producer's monotonic receipt window has not reached the required minimum yet."
            case .nonMonotonicWindowClock:
                return "The producer could not establish a monotonic observation window."
            case .windowSequenceExhausted:
                return "The local observation-window sequence was exhausted."
            }
        }

        return String(describing: error)
    }

    private func bluetoothUnavailableMessage(_ state: CBManagerState?) -> String {
        guard let state else {
            return "The package-owned Bluetooth controller has not been instantiated for this build."
        }
        switch state {
        case .unknown:
            return "Waiting for CoreBluetooth to report its state."
        case .resetting:
            return "Bluetooth is resetting. Keep Nembra open until the radio becomes ready."
        case .unsupported:
            return "This device does not expose the Bluetooth capability required for passive capture."
        case .unauthorized:
            return "Bluetooth permission is unavailable. Allow Nembra to use Bluetooth before starting correlation."
        case .poweredOff:
            return "Turn Bluetooth on before beginning OFF 1. The scooter's OFF state and the phone's Bluetooth state are separate requirements."
        case .poweredOn:
            return "Bluetooth is ready."
        @unknown default:
            return "CoreBluetooth reported an unknown future state. Capture remains unavailable."
        }
    }

    private func statePanel(
        eyebrow: String,
        title: String,
        message: String,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(eyebrow)
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func primaryButton(
        _ title: String,
        systemImage: String,
        disabled: Bool = false,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
                .foregroundStyle(disabled ? Color.secondary : Color.black)
                .background(
                    disabled ? .white.opacity(0.08) : .white,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier(identifier)
    }

    private func secondaryButton(
        _ title: String,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .foregroundStyle(.white)
                .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func diagnosticBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func guidanceFootnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func healthItem(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.body.monospacedDigit().weight(.medium))
                .multilineTextAlignment(.trailing)
        }
    }

    private func progressSegmentFill(
        index: Int,
        completedWindows: Int,
        currentWindow: Int?,
        status: PassiveBluetoothExperimentOneCoordinator.Status
    ) -> Color {
        if index < 4 {
            if index < completedWindows { return .white }
            if currentWindow == index { return .white.opacity(0.42) }
            return .white.opacity(0.12)
        }
        if index == 4 {
            return status.observationReady ? .white : .white.opacity(0.12)
        }
        return status.artifactFinalized ? .white : .white.opacity(0.12)
    }

    private func progressStage(
        status: PassiveBluetoothExperimentOneCoordinator.Status,
        completedWindows: Int
    ) -> String {
        if status.artifactFinalized { return "SEALED" }
        if status.canFinalizeObservationHorizon { return "H READY" }
        if status.observationReady { return "OBSERVE" }
        if status.connection == .connected { return "ACQUIRE" }
        if status.connection == .connecting { return "CONNECT" }
        if status.hasPreparedCaptureAdmission { return "REACQUIRE" }
        return "\(min(completedWindows, 4)) / 4"
    }

    private func progressAccessibilityLabel(
        status: PassiveBluetoothExperimentOneCoordinator.Status,
        completedWindows: Int
    ) -> String {
        if status.artifactFinalized {
            return "Experiment One progress, capture sealed and ready for analysis"
        }
        if status.canFinalizeObservationHorizon {
            return "Experiment One progress, observation Horizon ready to seal"
        }
        if status.observationReady {
            return "Experiment One progress, four correlation windows complete and passive observation ready"
        }
        return "Experiment One progress, \(min(completedWindows, 4)) of 4 correlation windows complete"
    }

    private func phaseShortName(_ phase: PassiveBluetoothPowerCycleObservationPhase) -> String {
        switch phase {
        case .firstPoweredOff: return "OFF 1"
        case .firstPoweredOn: return "ON 1"
        case .secondPoweredOff: return "OFF 2"
        case .secondPoweredOn: return "ON 2"
        }
    }

    private var correlationDetailValue: String {
        switch coordinator.status.correlation {
        case .incomplete: return "Incomplete"
        case .invalidEvidence: return "Invalid evidence"
        case .noRepeatableCandidate: return "No repeatable target"
        case let .ambiguousRepeatableCandidates(count): return "Ambiguous (\(count))"
        case .singleRepeatableCandidate: return "One repeatable full UUID"
        }
    }

    private func heroTitle(for phase: Phase) -> String {
        switch phase {
        case .complete: return "Evidence, sealed."
        case .readyToSeal, .observing: return "Hold the evidence line."
        case .acquiring, .connecting, .rediscoveringTarget, .targetReacquired: return "Bind the real signal."
        default: return "Find the real scooter signal."
        }
    }

    private func statusTitle(for phase: Phase) -> String {
        switch phase {
        case .physicalProcedureLocked: return "Field procedure locked"
        case .bluetoothUnavailable: return "Preflight required"
        case let .correlationReady(window): return "Ready for \(phaseShortName(window))"
        case let .correlationStarting(window): return "Starting \(phaseShortName(window))"
        case let .correlationObserving(window): return "Observing \(phaseShortName(window))"
        case .correlationFailed, .failed: return "Evidence stopped"
        case .noRepeatableTarget: return "No unique target"
        case .ambiguousTargets: return "Correlation ambiguous"
        case .correlatedTarget: return "Correlated target found"
        case .rediscoveringTarget: return "Fresh rediscovery"
        case .targetReacquired: return "Target reacquired"
        case .connecting: return "Connecting passively"
        case .acquiring: return "Finite acquisition"
        case .observing: return "Observation running"
        case .readyToSeal: return "Horizon ready"
        case .finalizing: return "Sealing artifact"
        case .complete: return "Capture complete"
        }
    }

    private func statusSymbol(for phase: Phase) -> String {
        switch phase {
        case .complete, .readyToSeal, .targetReacquired, .correlatedTarget:
            return "checkmark.circle.fill"
        case .physicalProcedureLocked, .correlationFailed, .failed, .noRepeatableTarget, .ambiguousTargets:
            return "exclamationmark.circle.fill"
        case .bluetoothUnavailable:
            return "antenna.radiowaves.left.and.right.slash"
        default:
            return "circle.fill"
        }
    }

    private func statusColor(for phase: Phase) -> Color {
        switch phase {
        case .complete, .readyToSeal, .targetReacquired, .correlatedTarget:
            return .green
        case .physicalProcedureLocked, .correlationFailed, .failed, .noRepeatableTarget, .ambiguousTargets:
            return .orange
        default:
            return .secondary
        }
    }
}
