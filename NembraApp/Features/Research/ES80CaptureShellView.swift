@preconcurrency import CoreBluetooth
import Dispatch
import Foundation
import NembraBluetoothCapture
import SwiftUI
import UIKit

/// Product-facing Nembra Capture shell for the first ES80 evidence workflow.
///
/// This surface consumes the accepted public four-window CoreBluetooth producer directly:
/// OFF1 -> ON1 -> OFF2 -> ON2. A single repeatable UUID is only correlated Bluetooth-target
/// evidence. It is never presented as authenticated/permanent ES80 identity.
///
/// Critical authority boundary: the current package-owned `PassiveBluetoothExperimentOneRun`
/// creates and owns its own four-window producer, and its recorder/final H-bounded seal remains
/// intentionally internal. This app must not take an independently-created public correlation
/// result and start a separate capture recorder as if those two evidence lives were one Experiment
/// One authority. Therefore this shell can complete real correlation and exact read-only target
/// reacquisition, but it deliberately does not expose Start Capture, Finish, or Share until the
/// accepted controller composes the same package-issued Experiment One run end-to-end.
@MainActor
struct ES80CaptureShellView: View {
    private enum Phase: Equatable {
        case bluetoothUnavailable(String)
        case correlationUnavailable(String)
        case correlationReady(PassiveBluetoothPowerCycleObservationPhase)
        case correlationStarting(PassiveBluetoothPowerCycleObservationPhase)
        case correlationObserving(PassiveBluetoothPowerCycleObservationPhase)
        case correlationFailed(String)
        case noRepeatableTarget
        case ambiguousTargets(Int)
        case correlatedTarget(UUID)
        case rediscoveringTarget(UUID)
        case targetReacquired(UUID)
        case targetNotConnectable(UUID)
        case failed(String)
    }

    private static let requiredCorrelationWindowDuration: TimeInterval = 10
    private static let requiredCorrelationWindowNanoseconds: UInt64 = 10_000_000_000

    let controller: ForegroundCoreBluetoothCaptureController

    @Environment(\.scenePhase) private var scenePhase

    @State private var correlationSession: PassiveBluetoothPowerCycleObservationSession?
    @State private var correlatedTargetIdentifier: UUID?
    @State private var rediscoveryRequested = false
    @State private var observedScanBeganAtUptimeNanoseconds: UInt64?
    @State private var diagnosticMessage: String?
    @State private var lifecycleFailureMessage: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let currentPhase = phase
            let nowUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero(for: currentPhase)
                    physicalRunLock
                    correlationProgress
                    primaryContent(
                        for: currentPhase,
                        nowUptimeNanoseconds: nowUptimeNanoseconds
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
                prepareCorrelationSessionIfNeeded()
                synchronizeIdleTimer(for: currentPhase)
                synchronizeObservedScanClock(isScanning: correlationIsScanning)
            }
            .onChange(of: currentPhase) { _, newPhase in
                synchronizeIdleTimer(for: newPhase)
            }
            .onChange(of: correlationIsScanning) { _, isScanning in
                synchronizeObservedScanClock(isScanning: isScanning)
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

                    Text("Find the real scooter signal.")
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

    private var physicalRunLock: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("Physical Experiment One locked")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("es80.capture.physical-run-locked")

                Text("This build can complete the real repeated Bluetooth correlation step. Passive capture remains locked until one package-owned Experiment One authority spans correlation, Ready, Horizon, immutable seal, and export. Nembra will not splice separate evidence lives just to make the workflow look complete.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var correlationProgress: some View {
        let completed = correlationSession?.progress?.completedWindowCount
            ?? correlationSession?.result?.windows.count
            ?? 0
        let current = correlationSession?.progress?.phase.rawValue

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TARGET CORRELATION")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(min(completed, 4)) / 4")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(correlationSegmentFill(index: index, completed: completed, current: current))
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
            }
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Target correlation progress, \(min(completed, 4)) of 4 observation windows complete")
        .accessibilityIdentifier("es80.capture.correlation-progress")
    }

    @ViewBuilder
    private func primaryContent(
        for phase: Phase,
        nowUptimeNanoseconds: UInt64
    ) -> some View {
        switch phase {
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

        case let .correlationUnavailable(message):
            statePanel(
                eyebrow: "PREFLIGHT",
                title: "Correlation producer unavailable",
                message: message,
                symbol: "exclamationmark.triangle"
            )
            primaryButton(
                "Retry setup",
                systemImage: "arrow.clockwise",
                identifier: "es80.capture.retry-correlation"
            ) {
                restartCorrelation()
            }

        case let .correlationReady(windowPhase):
            correlationReadyPanel(windowPhase)
            primaryButton(
                "Begin \(phaseShortName(windowPhase)) window",
                systemImage: windowPhase.operatorExpectedPowerOn ? "power.circle.fill" : "power.circle",
                identifier: "es80.capture.begin-window"
            ) {
                beginCorrelationWindow(windowPhase)
            }

        case let .correlationStarting(windowPhase):
            statePanel(
                eyebrow: "\(phaseShortName(windowPhase)) / STARTING",
                title: "Opening a fresh scan window",
                message: "Nembra is waiting for this window's new CoreBluetooth manager to report powered-on and active scanning. The evidence clock has not started yet.",
                symbol: "dot.radiowaves.left.and.right"
            )
            ProgressView()
                .tint(.white)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .correlationObserving(windowPhase):
            correlationObservingPanel(
                windowPhase,
                nowUptimeNanoseconds: nowUptimeNanoseconds
            )

            let remaining = correlationGuidanceRemainingSeconds(
                nowUptimeNanoseconds: nowUptimeNanoseconds
            )
            primaryButton(
                remaining == 0 ? "Complete \(phaseShortName(windowPhase)) window" : "Hold state — \(remaining)s",
                systemImage: remaining == 0 ? "checkmark.circle.fill" : "timer",
                disabled: remaining != 0,
                identifier: "es80.capture.complete-window"
            ) {
                completeCorrelationWindow(windowPhase)
            }

            Text("The countdown is display guidance only. The producer accepts the window only from its own monotonic receipt boundary; tapping early is not an evidence shortcut.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case let .correlationFailed(message):
            statePanel(
                eyebrow: "CORRELATION STOPPED",
                title: "Restart from OFF 1",
                message: message,
                symbol: "arrow.counterclockwise.circle"
            )
            primaryButton(
                "Restart correlation",
                systemImage: "arrow.counterclockwise",
                identifier: "es80.capture.restart-correlation"
            ) {
                restartCorrelation()
            }

        case .noRepeatableTarget:
            statePanel(
                eyebrow: "NO UNIQUE TARGET",
                title: "No scooter signal repeated twice",
                message: "Nembra found no selectable full Bluetooth identifier that was absent in both OFF windows and repeated in both ON windows. Do not guess from name or signal strength.",
                symbol: "questionmark.circle"
            )
            primaryButton(
                "Repeat all four windows",
                systemImage: "arrow.counterclockwise",
                identifier: "es80.capture.restart-correlation"
            ) {
                restartCorrelation()
            }

        case let .ambiguousTargets(count):
            statePanel(
                eyebrow: "AMBIGUOUS TARGET",
                title: "\(count) signals followed the same pattern",
                message: "More than one selectable full Bluetooth identifier repeated the OFF / ON pattern. Nembra refuses to break the tie with name, RSSI, services, or short IDs.",
                symbol: "point.3.filled.connected.trianglepath.dotted"
            )
            primaryButton(
                "Repeat all four windows",
                systemImage: "arrow.counterclockwise",
                identifier: "es80.capture.restart-correlation"
            ) {
                restartCorrelation()
            }

        case let .correlatedTarget(identifier):
            correlatedTargetPanel(identifier)
            primaryButton(
                "Confirm correlated target",
                systemImage: "checkmark.shield",
                identifier: "es80.capture.confirm-correlated-target"
            ) {
                confirmCorrelatedTarget(identifier)
            }

        case let .rediscoveringTarget(identifier):
            statePanel(
                eyebrow: "TARGET CONFIRMED",
                title: "Reacquiring the exact signal",
                message: "Nembra is using the read-only capture scanner to look for the exact full identifier that passed both OFF / ON cycles. Keep the scooter in the ON state from the final window.",
                symbol: "scope"
            )
            targetIdentifierStrip(identifier)
            ProgressView()
                .tint(.white)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)

            secondaryButton(
                "Restart rediscovery",
                systemImage: "arrow.clockwise",
                identifier: "es80.capture.restart-rediscovery"
            ) {
                startExactTargetRediscovery(identifier)
            }

        case let .targetReacquired(identifier):
            statePanel(
                eyebrow: "CORRELATED TARGET",
                title: "Exact signal reacquired",
                message: "The scanner rediscovered the same full CoreBluetooth identifier that repeated across both cycles. This is strong local correlation evidence, not permanent hardware authentication.",
                symbol: "checkmark.circle"
            )
            targetIdentifierStrip(identifier)
            captureBindingLock

        case let .targetNotConnectable(identifier):
            statePanel(
                eyebrow: "TARGET REACQUIRED",
                title: "Signal is not connectable",
                message: "The exact correlated identifier is visible, but CoreBluetooth explicitly reports it as non-connectable. Nembra will not promote this observation into a target capture session.",
                symbol: "link.badge.plus"
            )
            targetIdentifierStrip(identifier)
            primaryButton(
                "Scan again",
                systemImage: "arrow.clockwise",
                identifier: "es80.capture.restart-rediscovery"
            ) {
                startExactTargetRediscovery(identifier)
            }

        case let .failed(message):
            statePanel(
                eyebrow: "CORRELATION STOPPED",
                title: "Evidence failed closed",
                message: message,
                symbol: "exclamationmark.triangle"
            )
            primaryButton(
                "Restart from OFF 1",
                systemImage: "arrow.counterclockwise",
                identifier: "es80.capture.restart-correlation"
            ) {
                restartCorrelation()
            }
        }
    }

    private var captureBindingLock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Passive capture binding not available in this build")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            Text("Correlation is complete and the exact target was reacquired, but starting the current standalone capture controller would mint a different evidence authority. Nembra stops here until the accepted controller can continue this same package-owned Experiment One run through Ready, Horizon, seal, and export.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("es80.capture.binding-locked")
    }

    private func correlationReadyPanel(_ windowPhase: PassiveBluetoothPowerCycleObservationPhase) -> some View {
        let powerState = windowPhase.operatorExpectedPowerOn ? "ON" : "OFF"
        let cycle = (windowPhase == .firstPoweredOff || windowPhase == .firstPoweredOn) ? 1 : 2

        return statePanel(
            eyebrow: "\(phaseShortName(windowPhase)) / CYCLE \(cycle)",
            title: "Set the scooter \(powerState)",
            message: "Physically place the scooter in the expected \(powerState) state, then begin this bounded observation window. Nembra records your intended procedure state; it cannot attest that the scooter actually changed power.",
            symbol: windowPhase.operatorExpectedPowerOn ? "power.circle.fill" : "power.circle"
        )
    }

    private func correlationObservingPanel(
        _ windowPhase: PassiveBluetoothPowerCycleObservationPhase,
        nowUptimeNanoseconds: UInt64
    ) -> some View {
        let expectedState = windowPhase.operatorExpectedPowerOn ? "ON" : "OFF"
        let candidates = correlationSession?.progress?.currentObservedCandidateCount ?? 0
        let remaining = correlationGuidanceRemainingSeconds(nowUptimeNanoseconds: nowUptimeNanoseconds)

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.15), lineWidth: 7)
                        .frame(width: 62, height: 62)

                    Text(remaining == 0 ? "OK" : "\(remaining)")
                        .font(.headline.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("OBSERVING \(phaseShortName(windowPhase))")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.secondary)

                    Text("Keep the scooter \(expectedState)")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }

            Divider().overlay(.white.opacity(0.12))

            HStack {
                metric("Candidates", value: "\(candidates)")
                Spacer()
                metric("Evidence", value: remaining == 0 ? "Window eligible" : "Collecting")
            }

            Text("Candidate absence/presence here is callback evidence inside this bounded software window. It is not proof that the radio heard every nearby device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Observing \(phaseShortName(windowPhase)). Keep the scooter \(expectedState). \(candidates) Bluetooth candidates observed. \(remaining == 0 ? "Minimum display guidance complete." : "About \(remaining) seconds of display guidance remaining.")")
    }

    private func correlatedTargetPanel(_ identifier: UUID) -> some View {
        VStack(alignment: .leading, spacing: 18) {
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
                    Text("SCOOTER SIGNAL FOUND")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("One target repeated twice")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }

            targetIdentifierStrip(identifier)

            Text("This full CoreBluetooth identifier was selectable in both ON windows and absent from both OFF catalogs under one package-issued observation series. Treat it as a correlated Bluetooth target only.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func targetIdentifierStrip(_ identifier: UUID) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "number")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Candidate \(shortIdentifier(identifier))")
                .font(.subheadline.monospaced().weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            Text("FULL UUID MATCH")
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Correlated Bluetooth candidate ID \(shortIdentifier(identifier)). Exact full UUID match is used internally.")
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
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

    private var phase: Phase {
        if let lifecycleFailureMessage {
            return .failed(lifecycleFailureMessage)
        }
        if controller.hasTargetSession {
            return .failed("This app slice does not authorize a standalone target capture session because it would not share the correlation producer's Experiment One authority. Relaunch the research build.")
        }

        if let identifier = correlatedTargetIdentifier {
            if controller.bluetoothState != .poweredOn {
                return .bluetoothUnavailable(bluetoothUnavailableMessage)
            }
            if rediscoveryRequested,
               let candidate = controller.discoveredPeripherals.first(where: { $0.id == identifier }) {
                return candidate.isConnectable == false
                    ? .targetNotConnectable(identifier)
                    : .targetReacquired(identifier)
            }
            return .rediscoveringTarget(identifier)
        }

        if let result = correlationSession?.result {
            switch result.correlation.disposition {
            case .invalidObservationAuthority:
                return .correlationFailed("The four windows did not share one package-issued observation authority. Restart from OFF 1.")
            case .invalidObservationWindowOrder:
                return .correlationFailed("The four windows did not preserve the required OFF 1, ON 1, OFF 2, ON 2 ordering. Restart from OFF 1.")
            case .noRepeatableCandidate:
                return .noRepeatableTarget
            case let .ambiguousRepeatableCandidates(identifiers):
                return .ambiguousTargets(identifiers.count)
            case let .singleRepeatableCandidate(identifier):
                return .correlatedTarget(identifier)
            }
        }

        guard controller.bluetoothState == .poweredOn else {
            return .bluetoothUnavailable(bluetoothUnavailableMessage)
        }
        guard let correlationSession else {
            return .correlationUnavailable("Nembra could not initialize the bounded four-window observation producer.")
        }
        guard let progress = correlationSession.progress else {
            return .correlationUnavailable("The correlation producer has no remaining window and no final result. Restart the workflow.")
        }
        if progress.isSeriesInvalidated {
            return .correlationFailed("A known Bluetooth or scan-liveness gap invalidated this observation series. Completed windows cannot be reused across the gap.")
        }
        if progress.isScanning {
            return .correlationObserving(progress.phase)
        }
        if progress.isAwaitingBluetoothPower || progress.isAwaitingScanReadiness {
            return .correlationStarting(progress.phase)
        }
        return .correlationReady(progress.phase)
    }

    private var correlationIsScanning: Bool {
        correlationSession?.progress?.isScanning == true
    }

    private var correlationEvidenceIsLive: Bool {
        guard let progress = correlationSession?.progress else { return false }
        return progress.isAwaitingBluetoothPower || progress.isAwaitingScanReadiness || progress.isScanning
    }

    private func prepareCorrelationSessionIfNeeded() {
        guard correlationSession == nil else { return }
        do {
            correlationSession = try PassiveBluetoothPowerCycleObservationSession(
                minimumWindowDuration: Self.requiredCorrelationWindowDuration
            )
        } catch {
            diagnosticMessage = "Correlation setup failed: \(String(describing: error))"
        }
    }

    private func beginCorrelationWindow(_ expectedPhase: PassiveBluetoothPowerCycleObservationPhase) {
        diagnosticMessage = nil
        guard let correlationSession,
              correlationSession.progress?.phase == expectedPhase else {
            diagnosticMessage = "The correlation series changed before this window could start. Restart from OFF 1."
            return
        }

        do {
            try correlationSession.startCurrentWindow()
        } catch {
            diagnosticMessage = correlationErrorMessage(error)
        }
    }

    private func completeCorrelationWindow(_ expectedPhase: PassiveBluetoothPowerCycleObservationPhase) {
        diagnosticMessage = nil
        guard let correlationSession,
              correlationSession.progress?.phase == expectedPhase,
              correlationSession.progress?.isScanning == true else {
            diagnosticMessage = "This observation window is not currently live."
            return
        }

        do {
            _ = try correlationSession.finishCurrentWindow()
            observedScanBeganAtUptimeNanoseconds = nil
        } catch {
            diagnosticMessage = correlationErrorMessage(error)
        }
    }

    private func restartCorrelation() {
        guard !controller.hasTargetSession else {
            diagnosticMessage = "A target capture session already exists. Relaunch Nembra Capture instead of reusing this controller for a new Experiment One attempt."
            return
        }

        correlationSession?.abandonCurrentWindow()
        controller.stopScanning()
        correlatedTargetIdentifier = nil
        rediscoveryRequested = false
        observedScanBeganAtUptimeNanoseconds = nil
        lifecycleFailureMessage = nil
        diagnosticMessage = nil

        do {
            correlationSession = try PassiveBluetoothPowerCycleObservationSession(
                minimumWindowDuration: Self.requiredCorrelationWindowDuration
            )
        } catch {
            correlationSession = nil
            diagnosticMessage = "Correlation setup failed: \(String(describing: error))"
        }
    }

    private func confirmCorrelatedTarget(_ identifier: UUID) {
        correlatedTargetIdentifier = identifier
        startExactTargetRediscovery(identifier)
    }

    private func startExactTargetRediscovery(_ identifier: UUID) {
        diagnosticMessage = nil
        controller.stopScanning()
        rediscoveryRequested = false

        do {
            try controller.startScanning(captureAdvertisementCadence: false)
            rediscoveryRequested = true
        } catch {
            diagnosticMessage = "Exact-target rediscovery could not start: \(String(describing: error))"
        }
    }

    private func handleScenePhaseChange(_ newScenePhase: ScenePhase) {
        if newScenePhase == .active {
            if let identifier = correlatedTargetIdentifier,
               !rediscoveryRequested,
               lifecycleFailureMessage == nil {
                startExactTargetRediscovery(identifier)
            }
            return
        }

        if correlationEvidenceIsLive {
            correlationSession?.abandonCurrentWindow()
            lifecycleFailureMessage = "Nembra left the active foreground while a bounded correlation window was live. This four-window series is no longer eligible for Experiment One correlation evidence."
            diagnosticMessage = nil
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }

        if rediscoveryRequested {
            controller.stopScanning()
            rediscoveryRequested = false
        }
    }

    private func synchronizeIdleTimer(for phase: Phase) {
        switch phase {
        case .correlationStarting, .correlationObserving, .rediscoveringTarget, .targetReacquired:
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

    private func correlationErrorMessage(_ error: Error) -> String {
        guard let error = error as? PassiveBluetoothPowerCycleObservationSessionError else {
            return String(describing: error)
        }

        switch error {
        case .invalidMinimumWindowDuration:
            return "The required correlation-window duration is invalid in this build."
        case .seriesComplete:
            return "All four observation windows are already sealed."
        case .seriesInvalidated:
            return "This observation series was invalidated by a known gap. Restart from OFF 1."
        case .windowAlreadyActive:
            return "The current observation window is already active."
        case .windowNotActive:
            return "No observation window is currently active."
        case .bluetoothBecameUnavailable:
            return "Bluetooth became unavailable during the bounded window. Restart the full four-window series."
        case .scanReadinessPending:
            return "Nembra requested scanning, but the authoritative receipt window has not opened yet."
        case .scanReadinessTimedOut:
            return "CoreBluetooth never confirmed scan readiness inside the bounded startup interval. Restart from OFF 1."
        case .scanBecameInactive:
            return "The exact window's CoreBluetooth scan became inactive. Restart the full series."
        case .minimumWindowDurationNotReached:
            return "The producer's monotonic receipt window has not reached the required minimum yet."
        case .nonMonotonicWindowClock:
            return "The monotonic receipt clock could not establish a valid window. Restart from OFF 1."
        case .windowSequenceExhausted:
            return "The local observation-window sequence was exhausted. Restart the research build."
        }
    }

    private var bluetoothUnavailableMessage: String {
        switch controller.bluetoothState {
        case .unknown:
            "Waiting for CoreBluetooth to report its state."
        case .resetting:
            "Bluetooth is resetting. Keep Nembra open until the radio becomes ready."
        case .unsupported:
            "This device does not expose the Bluetooth capability required for passive capture."
        case .unauthorized:
            "Bluetooth permission is unavailable. Allow Nembra to use Bluetooth before starting correlation."
        case .poweredOff:
            "Turn Bluetooth on before beginning the first OFF observation window. The scooter's OFF state and the phone's Bluetooth state are separate requirements."
        case .poweredOn:
            "Bluetooth is ready."
        @unknown default:
            "CoreBluetooth reported an unknown future state. Capture remains unavailable."
        }
    }

    private func correlationSegmentFill(index: Int, completed: Int, current: Int?) -> Color {
        if index < completed {
            return .white
        }
        if current == index {
            return .white.opacity(0.42)
        }
        return .white.opacity(0.12)
    }

    private func phaseShortName(_ phase: PassiveBluetoothPowerCycleObservationPhase) -> String {
        switch phase {
        case .firstPoweredOff: "OFF 1"
        case .firstPoweredOn: "ON 1"
        case .secondPoweredOff: "OFF 2"
        case .secondPoweredOn: "ON 2"
        }
    }

    private func shortIdentifier(_ identifier: UUID) -> String {
        String(identifier.uuidString.prefix(8))
    }

    private func statusTitle(for phase: Phase) -> String {
        switch phase {
        case .bluetoothUnavailable, .correlationUnavailable: "Preflight required"
        case let .correlationReady(window): "Ready for \(phaseShortName(window))"
        case let .correlationStarting(window): "Starting \(phaseShortName(window))"
        case let .correlationObserving(window): "Observing \(phaseShortName(window))"
        case .correlationFailed, .noRepeatableTarget, .ambiguousTargets: "Correlation needs a fresh run"
        case .correlatedTarget: "Correlated Bluetooth target found"
        case .rediscoveringTarget: "Reacquiring exact target"
        case .targetReacquired: "Target reacquired — capture binding locked"
        case .targetNotConnectable: "Correlated target unavailable"
        case .failed: "Correlation failed closed"
        }
    }

    private func statusSymbol(for phase: Phase) -> String {
        switch phase {
        case .correlatedTarget, .targetReacquired:
            "checkmark.circle.fill"
        case .correlationObserving, .correlationStarting, .rediscoveringTarget:
            "circle.dotted"
        case .failed, .correlationFailed, .ambiguousTargets, .noRepeatableTarget, .targetNotConnectable:
            "exclamationmark.triangle.fill"
        case .bluetoothUnavailable, .correlationUnavailable, .correlationReady:
            "circle.fill"
        }
    }

    private func statusColor(for phase: Phase) -> Color {
        switch phase {
        case .correlatedTarget:
            .green
        case .failed, .correlationFailed:
            .red
        case .targetReacquired,
             .ambiguousTargets,
             .noRepeatableTarget,
             .targetNotConnectable,
             .bluetoothUnavailable,
             .correlationUnavailable:
            .orange
        case .correlationReady, .correlationStarting, .correlationObserving, .rediscoveringTarget:
            .white.opacity(0.78)
        }
    }
}
