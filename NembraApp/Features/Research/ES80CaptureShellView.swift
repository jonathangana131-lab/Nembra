@preconcurrency import CoreBluetooth
import Dispatch
import Foundation
import NembraBluetoothCapture
import SwiftUI
import UIKit

/// Presentation-only polling for the non-observable package coordinator.
///
/// Capture authority and all evidence clocks remain package-owned. The shell polls often enough
/// to keep state changes subsecond while avoiding four full hierarchy evaluations per second for
/// integer-second guidance that is never evidence.
enum ES80CaptureRefreshPolicy {
    static let statusPollInterval: TimeInterval = 0.5
}

/// Product-facing Nembra Capture shell for ES80 Experiment One.
///
/// One package-owned coordinator now carries the complete software provenance life from
/// OFF1 -> ON1 -> OFF2 -> ON2 through explicit correlated-target confirmation, fresh
/// post-admission rediscovery, passive acquisition, Ready, monotonic Horizon, and immutable
/// finalized JSON. SwiftUI never constructs a second correlation producer, never selects an
/// authoritative UUID, and never receives the sealed admission or mutable recorder.
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
    @State private var finalShareData: Data?
    @State private var finalShareFilename: String?
    @State private var finalShareIntegrityReport: PassiveBluetoothExperimentOneFinalShareIntegrityReport?
    @State private var sharePreparationWarning: String?
    @State private var declaredStationarySetup: PassiveBluetoothStationaryCaptureSetup?
    @State private var showingDetails = false

    private let onFreshExperimentRequested: () throws -> PassiveBluetoothExperimentOneCoordinator
#if DEBUG && targetEnvironment(simulator)
    private let simulatorQASnapshot: PassiveBluetoothExperimentOneSimulatorQAFixture.Snapshot?
#endif

    init(
        coordinator: PassiveBluetoothExperimentOneCoordinator,
        onFreshExperimentRequested: @escaping () throws -> PassiveBluetoothExperimentOneCoordinator
    ) {
        _coordinator = State(initialValue: coordinator)
        self.onFreshExperimentRequested = onFreshExperimentRequested
#if DEBUG && targetEnvironment(simulator)
        simulatorQASnapshot = nil
#endif
    }

#if DEBUG && targetEnvironment(simulator)
    init(
        coordinator: PassiveBluetoothExperimentOneCoordinator,
        simulatorQASnapshot: PassiveBluetoothExperimentOneSimulatorQAFixture.Snapshot,
        onFreshExperimentRequested: @escaping () throws -> PassiveBluetoothExperimentOneCoordinator
    ) {
        _coordinator = State(initialValue: coordinator)
        self.onFreshExperimentRequested = onFreshExperimentRequested
        self.simulatorQASnapshot = simulatorQASnapshot
    }
#endif

    var body: some View {
        TimelineView(.periodic(
            from: .now,
            by: ES80CaptureRefreshPolicy.statusPollInterval
        )) { _ in
            let status = coordinator.status
            let currentPhase = phase(status: status)
            let now = DispatchTime.now().uptimeNanoseconds

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero(for: currentPhase)
#if DEBUG && targetEnvironment(simulator)
                    if let simulatorQASnapshot {
                        simulatorQABadge(simulatorQASnapshot)
                    }
#endif
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
                synchronizeObservationReadyClock(isReady: presentationObservationReady(status: status))
            }
            .onChange(of: currentPhase) { _, newPhase in
                synchronizeIdleTimer(for: newPhase)
            }
            .onChange(of: status.powerCycleProgress?.isScanning == true) { _, isScanning in
                synchronizeObservedScanClock(isScanning: isScanning)
            }
            .onChange(of: presentationObservationReady(status: status)) { _, isReady in
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

#if DEBUG && targetEnvironment(simulator)
    private func simulatorQABadge(
        _ snapshot: PassiveBluetoothExperimentOneSimulatorQAFixture.Snapshot
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "hammer.fill")
                .accessibilityHidden(true)
            Text("\(snapshot.evidenceLabel) · SYNTHETIC SOFTWARE STATE")
        }
        .font(.caption.monospaced().weight(.bold))
        .foregroundStyle(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.10), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            snapshot.accessibilitySummary
                + " No Bluetooth transport or capture evidence is created by this presentation fixture."
        )
        .accessibilityIdentifier("es80.capture.simulator-qa")
    }
#endif

    private var passiveSafetyPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("One continuous capture")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Nembra keeps target matching and passive capture in one continuous run. It never sends scooter commands and never chooses a target from its name, signal strength, or service hints.")
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
        let completed = presentationCompletedWindows(status: status)
        let current = presentationCurrentWindow(status: status)

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
        .accessibilityLabel(
            progressAccessibilityLabel(
                status: status,
                completedWindows: completed,
                analysisReady: presentationAnalysisReady
            )
        )
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
                message: "Field capture is locked for this build. OFF / ON windows, connection, capture, and sealing stay unavailable until this exact build is authorized.",
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
                    "Begin \(phaseShortName(window)) window",
                    systemImage: window.operatorExpectedPowerOn ? "power.circle.fill" : "power.circle",
                    identifier: "es80.capture.begin-window"
                ) {
                    beginCorrelationWindow()
                }
            }

        case let .correlationStarting(window):
            statePanel(
                eyebrow: "\(phaseShortName(window)) / STARTING",
                title: "Opening a fresh scan window",
                message: "Nembra is waiting for Bluetooth to become ready and scanning to begin. The observation window has not started yet.",
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(phaseShortName(window)) observation")
            .accessibilityValue(
                window.operatorExpectedPowerOn
                    ? "Keep the scooter on"
                    : "Keep the scooter off"
            )
            .accessibilityHint("Nembra is recording this bounded Bluetooth observation window.")

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
            .accessibilityLabel("\(phaseShortName(window)) observation timer")
            .accessibilityValue(
                remaining == 0
                    ? "Display guidance complete; ready to request window completion"
                    : "\(remaining) seconds of display guidance remaining"
            )
            .accessibilityHint("The capture system, not this display timer, decides whether the window has enough evidence.")

            guidanceFootnote("This countdown is display guidance only. Nembra accepts the window only after the required observation time is recorded; tapping early cannot create evidence.")

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
                message: "No Bluetooth signal was absent in both OFF windows and repeated in both ON windows. Nembra will not guess from name, signal strength, service hints, or short IDs.",
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
                message: "More than one Bluetooth signal repeated the OFF / ON pattern. Nembra refuses to break the tie with display name, signal strength, services, or a short identifier.",
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
                message: "One Bluetooth signal appeared in both ON windows and stayed absent from both OFF windows during this run. Treat it only as a correlated scooter signal, not verified scooter identity.",
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
                message: "A fresh scan is looking for the same Bluetooth signal that passed both OFF / ON cycles. Keep the scooter in the ON state from the final window.",
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
                message: "The same Bluetooth signal reappeared in the fresh scan after target confirmation. This remains local correlation evidence, not permanent hardware authentication.",
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
                message: "Nembra is connecting only to the confirmed correlated signal. This workflow remains read only and sends no scooter commands.",
                symbol: "link"
            )
            ProgressView()
                .tint(.white)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .acquiring:
            statePanel(
                eyebrow: "PASSIVE DISCOVERY",
                title: "Learning the readable surface",
                message: "Nembra is passively discovering what this target exposes. Observation starts only after that discovery is complete.",
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
                title: remaining == 0 ? "Waiting for seal readiness" : "Hold observation — \(remaining)s",
                message: "Passive discovery is complete. Keep Nembra foregrounded and the scooter stationary while the required observation period finishes. The displayed timer is guidance only.",
                symbol: "timer"
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Observation ready")
            .accessibilityValue(
                remaining == 0
                    ? "Display guidance complete; waiting for seal readiness"
                    : "\(remaining) seconds of display guidance remaining"
            )
            .accessibilityHint("Keep Nembra foregrounded and the scooter stationary.")
            observationHealthStrip(status: status)
            let canFinalize = presentationCanFinalizeObservationHorizon(status: status)
            primaryButton(
                canFinalize ? "Seal Capture" : "Observation in progress",
                systemImage: canFinalize ? "checkmark.seal.fill" : "timer",
                disabled: !canFinalize,
                identifier: "es80.capture.finish"
            ) {
                finalizeCapture()
            }
            .accessibilityLabel("Seal Capture")
            .accessibilityValue(
                canFinalize
                    ? "Ready"
                    : "Unavailable; waiting for the required observation period"
            )
            .accessibilityHint("Available only after Nembra accepts the required observation duration.")

        case .readyToSeal:
            statePanel(
                eyebrow: "READY TO SEAL",
                title: "Capture can be sealed",
                message: "Passive discovery and the required observation period are complete. Finishing now seals one final capture from this same run.",
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
                title: "Freezing final evidence",
                message: "Nembra is sealing the final evidence cutoff, checking capture integrity, and preparing the final capture artifact. Do not leave the app while this finishes.",
                symbol: "lock.doc"
            )
            ProgressView()
                .tint(.white)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .complete:
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
                    .accessibilityIdentifier("es80.capture.share")
                } else if coordinator.finalizedArtifact != nil {
                    primaryButton(
                        finalShareIntegrityReport == nil ? "Verify final artifact" : "Retry Share file",
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
                diagnosticBanner(sharePreparationWarning)
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
                title: "Capture stopped safely",
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
                 ? "Set the scooter to ON, keep the stock app closed, then begin this bounded observation window."
                 : "Set the scooter fully OFF, keep the stock app closed, then begin this bounded observation window.")
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

            Text("Nembra is recording Bluetooth signals for this exact window. Keep the phone nearby and the app foregrounded; do not open the stock scooter app during this series.")
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
        let connection = presentationConnection(status: status)
        let observationReady = presentationObservationReady(status: status)
        let horizonReady = presentationCanFinalizeObservationHorizon(status: status)

        return HStack(spacing: 12) {
            healthItem("TARGET", value: connection == .connected ? "BOUND" : "WAIT")
            Divider().frame(height: 28).overlay(.white.opacity(0.12))
            healthItem("DISCOVERY", value: observationReady ? "READY" : "WAIT")
            Divider().frame(height: 28).overlay(.white.opacity(0.12))
            healthItem("SEAL", value: horizonReady ? "READY" : "HOLD")
        }
        .padding(14)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Capture health. Target \(connection == .connected ? "bound" : "waiting"). Passive discovery \(observationReady ? "ready" : "waiting"). Seal \(horizonReady ? "ready" : "waiting")."
        )
    }

    private var completionPanel: some View {
        let analysisReady = presentationAnalysisReady
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(analysisReady ? .white : .white.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: analysisReady ? "checkmark" : "lock.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(analysisReady ? .black : .white)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(analysisReady ? "CAPTURE COMPLETE" : "CAPTURE SEALED")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(analysisReady ? "Ready for analysis" : "Integrity check required")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }

#if DEBUG && targetEnvironment(simulator)
            if simulatorQASnapshot != nil {
                Text("Synthetic Simulator QA presentation only. No capture artifact bytes were created, and no physical, RF, protocol, telemetry, or command evidence is claimed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let report = finalShareIntegrityReport {
#else
            if let report = finalShareIntegrityReport {
#endif
                Text("The exact \(report.finalShareByteCount.formatted())-byte final Share artifact passed the final Share and nested capture integrity checks. No protocol field meaning is claimed yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let artifact = coordinator.finalizedArtifact {
                Text("\(artifact.captureJSON.count.formatted()) capture bytes are sealed from this run. Analysis readiness is not earned until Nembra verifies the exact final Share bytes and their nested evidence.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if coordinator.status.finalizationCleanup == .failed {
                Text("The artifact remains sealed, but post-seal Bluetooth cleanup did not complete. Preserve this capture and restart Nembra before another Experiment One run.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(analysisReady ? "Ready for analysis" : "Capture sealed, integrity check required")
        .accessibilityIdentifier("es80.capture.complete")
    }

    private var captureDetailsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Experiment One")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
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
#endif
                        detailRow("Recipe", value: PassiveBluetoothExperimentOneFieldExecutionGate.recipeID.rawValue)
                        detailRow("Correlation", value: correlationDetailValue)
                        detailRow("Cleanup", value: finalizationCleanupDetailValue)

                        if let report = finalShareIntegrityReport {
                            detailRow("Analysis readiness", value: "Ready")
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

                    Divider()

                    Text("Truth boundary")
                        .font(.headline)
                    Text("This artifact is passive software evidence. File and build hashes are software provenance, not independent field authorization. Repeated full-UUID correlation does not authenticate the physical ES80, and this screen does not assign GATT, Tuya/DP, battery, current, power, speed, regen, or command semantics.")
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
#if DEBUG && targetEnvironment(simulator)
        if let simulatorQASnapshot {
            return simulatorQAPhase(simulatorQASnapshot.scenario)
        }
#endif
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

#if DEBUG && targetEnvironment(simulator)
    private func simulatorQAPhase(
        _ scenario: PassiveBluetoothExperimentOneSimulatorQAFixture.Scenario
    ) -> Phase {
        switch scenario {
        case .stationaryPreflight, .firstPoweredOff:
            return .correlationReady(.firstPoweredOff)
        case .firstPoweredOn:
            return .correlationReady(.firstPoweredOn)
        case .secondPoweredOff:
            return .correlationReady(.secondPoweredOff)
        case .secondPoweredOn, .targetConfirmation:
            return .correlatedTarget
        case .passiveDiscovery:
            return .connecting
        case .observationReady, .captureInProgress:
            return .observing
        case .observationHorizonReady:
            return .readyToSeal
        case .horizonSealed:
            return .finalizing
        case .captureComplete, .shareRetry:
            return .complete
        case .foregroundInterrupted:
            return .failed("Simulator QA interruption fixture. This synthetic state represents a foreground-invalidated evidence life; it is not physical evidence.")
        }
    }
#endif

    private var presentationAnalysisReady: Bool {
#if DEBUG && targetEnvironment(simulator)
        if let simulatorQASnapshot {
            return simulatorQASnapshot.artifactState == .completeReadyForAnalysis
                || simulatorQASnapshot.artifactState == .shareRetry
        }
#endif
        return finalShareIntegrityReport != nil
    }

    private func presentationCompletedWindows(
        status: PassiveBluetoothExperimentOneCoordinator.Status
    ) -> Int {
#if DEBUG && targetEnvironment(simulator)
        if let simulatorQASnapshot {
            switch simulatorQASnapshot.scenario {
            case .stationaryPreflight, .firstPoweredOff: return 0
            case .firstPoweredOn: return 1
            case .secondPoweredOff: return 2
            default: return 4
            }
        }
#endif
        return status.powerCycleProgress?.completedWindowCount
            ?? coordinator.powerCycleResult?.windows.count
            ?? 0
    }

    private func presentationCurrentWindow(
        status: PassiveBluetoothExperimentOneCoordinator.Status
    ) -> Int? {
#if DEBUG && targetEnvironment(simulator)
        if let simulatorQASnapshot {
            switch simulatorQASnapshot.scenario {
            case .stationaryPreflight, .firstPoweredOff:
                return PassiveBluetoothPowerCycleObservationPhase.firstPoweredOff.rawValue
            case .firstPoweredOn:
                return PassiveBluetoothPowerCycleObservationPhase.firstPoweredOn.rawValue
            case .secondPoweredOff:
                return PassiveBluetoothPowerCycleObservationPhase.secondPoweredOff.rawValue
            default:
                return nil
            }
        }
#endif
        return status.powerCycleProgress?.phase.rawValue
    }

    private func presentationObservationReady(
        status: PassiveBluetoothExperimentOneCoordinator.Status
    ) -> Bool {
#if DEBUG && targetEnvironment(simulator)
        if let simulatorQASnapshot { return simulatorQASnapshot.observationReady }
#endif
        return status.observationReady
    }

    private func presentationCanFinalizeObservationHorizon(
        status: PassiveBluetoothExperimentOneCoordinator.Status
    ) -> Bool {
#if DEBUG && targetEnvironment(simulator)
        if let simulatorQASnapshot { return simulatorQASnapshot.canFinalizeObservationHorizon }
#endif
        return status.canFinalizeObservationHorizon
    }

    private func presentationConnection(
        status: PassiveBluetoothExperimentOneCoordinator.Status
    ) -> PassiveBluetoothExperimentOneCoordinator.ConnectionStatus {
#if DEBUG && targetEnvironment(simulator)
        if let simulatorQASnapshot { return simulatorQASnapshot.connection }
#endif
        return status.connection
    }

    private func presentationHasPreparedCaptureAdmission(
        status: PassiveBluetoothExperimentOneCoordinator.Status
    ) -> Bool {
#if DEBUG && targetEnvironment(simulator)
        if let simulatorQASnapshot { return simulatorQASnapshot.hasPreparedCaptureAdmission }
#endif
        return status.hasPreparedCaptureAdmission
    }

    private func presentationArtifactFinalized(
        status: PassiveBluetoothExperimentOneCoordinator.Status
    ) -> Bool {
#if DEBUG && targetEnvironment(simulator)
        if let simulatorQASnapshot {
            return simulatorQASnapshot.artifactState == .sealed
                || simulatorQASnapshot.artifactState == .completeReadyForAnalysis
                || simulatorQASnapshot.artifactState == .shareRetry
        }
#endif
        return status.artifactFinalized
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
        sharePreparationWarning = nil
        finalizationInFlight = true

        Task {
            do {
                _ = try await coordinator.finalizeObservationHorizon()
            } catch {
                finalizationInFlight = false
                localFailureMessage = "Capture sealing failed: \(experimentErrorMessage(error))"
                return
            }

            // Horizon is already immutable here. Final-share verification and temporary-file staging
            // are recoverable product layers and must never relabel seal truth.
            finalizationInFlight = false
            prepareFinalShareForAnalysisAndSharing()
        }
    }

    private func prepareFinalShareForAnalysisAndSharing() {
        guard coordinator.finalizedArtifact != nil else { return }
        guard let setup = declaredStationarySetup else {
            sharePreparationWarning = "Capture is sealed, but this run has no retained operator setup declaration. Start a fresh Experiment One rather than inventing setup provenance at export time."
            return
        }

        // A previously verified exact artifact is retained independently from temporary file staging.
        // Retrying a failed Share file must never silently mint new evidence bytes.
        if let data = finalShareData,
           finalShareIntegrityReport != nil,
           let filename = finalShareFilename {
            do {
                shareURL = try persistShareArtifact(data, suggestedFilename: filename)
                sharePreparationWarning = nil
            } catch {
                shareURL = nil
                sharePreparationWarning = "Capture remains sealed and ready for analysis, but the temporary Share file could not be staged: \(experimentErrorMessage(error))"
            }
            return
        }

        let artifact: PassiveBluetoothExperimentOneFinalShareArtifact
        let report: PassiveBluetoothExperimentOneFinalShareIntegrityReport
        do {
            artifact = try coordinator.finalizedShareArtifactForCurrentApplication(setup: setup)
            report = try PassiveBluetoothExperimentOneFinalShareIntegrity.inspect(artifact.json)
        } catch {
            finalShareData = nil
            finalShareFilename = nil
            finalShareIntegrityReport = nil
            shareURL = nil
            sharePreparationWarning = "Capture remains sealed, but the exact final Share artifact did not earn analysis readiness: \(experimentErrorMessage(error))"
            return
        }

        finalShareData = artifact.json
        finalShareFilename = artifact.suggestedFilename
        finalShareIntegrityReport = report

        do {
            shareURL = try persistShareArtifact(
                artifact.json,
                suggestedFilename: artifact.suggestedFilename
            )
            sharePreparationWarning = nil
        } catch {
            shareURL = nil
            sharePreparationWarning = "Capture remains sealed and ready for analysis, but the temporary Share file could not be staged: \(experimentErrorMessage(error))"
        }
    }

    private func restartExperiment() {
        coordinator.abandonExperiment()
        diagnosticMessage = nil
        localFailureMessage = nil
        captureConnectionAttempted = false
        finalizationInFlight = false
        shareURL = nil
        finalShareData = nil
        finalShareFilename = nil
        finalShareIntegrityReport = nil
        sharePreparationWarning = nil
        declaredStationarySetup = nil
        showingDetails = false
        observedScanBeganAtUptimeNanoseconds = nil
        observationReadyBeganAtUptimeNanoseconds = nil

        do {
            coordinator = try onFreshExperimentRequested()
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

    private func persistShareArtifact(
        _ data: Data,
        suggestedFilename: String
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(suggestedFilename)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func experimentErrorMessage(_ error: Error) -> String {
        if let error = error as? PassiveBluetoothExperimentOneCoordinator.CoordinatorError {
            switch error {
            case .physicalProcedureLocked:
                return "Field capture is locked for this build."
            case .foregroundIntegrityLost:
                return "Nembra left the foreground after capture began. Start a fresh capture."
            case .captureAdmissionAlreadyPrepared:
                return "The correlated target is already prepared. Continue the current rediscovery."
            case .captureAdmissionNotPrepared:
                return "No confirmed correlated target is ready for this step."
            case .correlationIncomplete:
                return "All four OFF / ON windows must complete before target confirmation."
            case .correlationEvidenceInvalid:
                return "The four-window evidence or ordering is invalid."
            case .correlationNotUnique:
                return "The four-window series did not produce exactly one repeatable target."
            case .targetNotRediscovered:
                return "The exact correlated target has not reappeared in the fresh scan yet. Keep scanning and retry."
            case .targetNotConnectable:
                return "The exact correlated target is visible but Bluetooth reports it as non-connectable."
            case .controllerUnavailable:
                return "Passive Bluetooth capture is unavailable."
            case .observationNotReady:
                return "Passive discovery and the minimum observation period are not complete yet."
            case .artifactAlreadyFinalized:
                return "This capture is already sealed."
            }
        }

        if let error = error as? PassiveBluetoothPowerCycleObservationSessionError {
            switch error {
            case .invalidMinimumWindowDuration:
                return "This build has an invalid observation-window duration. Capture cannot continue."
            case .seriesComplete:
                return "All four correlation windows are already sealed."
            case .seriesInvalidated:
                return "This OFF / ON series has an evidence gap. Start a fresh capture."
            case .windowAlreadyActive:
                return "The current correlation window is already active."
            case .windowNotActive:
                return "No correlation window is currently active."
            case .bluetoothBecameUnavailable:
                return "Bluetooth became unavailable during this observation window."
            case .scanReadinessPending:
                return "Scanning was requested, but the observation window has not opened yet."
            case .scanReadinessTimedOut:
                return "Bluetooth did not become ready in time for this observation window."
            case .scanBecameInactive:
                return "This window's Bluetooth scan became inactive."
            case .minimumWindowDurationNotReached:
                return "The observation window has not reached the required minimum yet."
            case .nonMonotonicWindowClock:
                return "Nembra could not establish a valid observation window."
            case .windowSequenceExhausted:
                return "This OFF / ON sequence cannot continue. Start a fresh capture."
            }
        }

        return "Capture stopped because an unexpected error occurred. Start a fresh capture."
    }

    private func bluetoothUnavailableMessage(_ state: CBManagerState?) -> String {
        guard let state else {
            return "Bluetooth capture is not available for this build."
        }
        switch state {
        case .unknown:
            return "Waiting for Bluetooth to report its state."
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
            return "Bluetooth reported an unknown future state. Capture remains unavailable."
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
                .textSelection(.enabled)
        }
    }

    private func digestDetailRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
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
            return presentationObservationReady(status: status) ? .white : .white.opacity(0.12)
        }
        return presentationArtifactFinalized(status: status) ? .white : .white.opacity(0.12)
    }

    private func progressStage(
        status: PassiveBluetoothExperimentOneCoordinator.Status,
        completedWindows: Int
    ) -> String {
        if presentationArtifactFinalized(status: status) { return "SEALED" }
        if presentationCanFinalizeObservationHorizon(status: status) { return "SEAL READY" }
        if presentationObservationReady(status: status) { return "OBSERVE" }
        if presentationConnection(status: status) == .connected { return "DISCOVER" }
        if presentationConnection(status: status) == .connecting { return "CONNECT" }
        if presentationHasPreparedCaptureAdmission(status: status) { return "REACQUIRE" }
        return "\(min(completedWindows, 4)) / 4"
    }

    private func progressAccessibilityLabel(
        status: PassiveBluetoothExperimentOneCoordinator.Status,
        completedWindows: Int,
        analysisReady: Bool
    ) -> String {
        if presentationArtifactFinalized(status: status) {
            return analysisReady
                ? "Experiment One progress, capture sealed and ready for analysis"
                : "Experiment One progress, capture sealed; final artifact integrity not yet verified"
        }
        if presentationCanFinalizeObservationHorizon(status: status) {
            return "Experiment One progress, observation ready to seal"
        }
        if presentationObservationReady(status: status) {
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

    private var finalizationCleanupDetailValue: String {
        switch coordinator.status.finalizationCleanup {
        case .notAttempted: return "Not attempted"
        case .complete: return "Complete"
        case .failed: return "Recovery needed"
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
        case .correlationFailed, .failed: return "Capture stopped"
        case .noRepeatableTarget: return "No unique target"
        case .ambiguousTargets: return "Correlation ambiguous"
        case .correlatedTarget: return "Correlated target found"
        case .rediscoveringTarget: return "Fresh rediscovery"
        case .targetReacquired: return "Target reacquired"
        case .connecting: return "Connecting passively"
        case .acquiring: return "Passive discovery"
        case .observing: return "Observation running"
        case .readyToSeal: return "Ready to seal"
        case .finalizing: return "Sealing capture"
        case .complete: return presentationAnalysisReady ? "Capture complete" : "Capture sealed"
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
