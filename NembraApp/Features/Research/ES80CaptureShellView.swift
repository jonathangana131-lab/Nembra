@preconcurrency import CoreBluetooth
import CoreTransferable
import CryptoKit
import Dispatch
import Foundation
import NembraBluetoothCapture
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Product-facing Nembra Capture shell for the first ES80 evidence workflow.
///
/// One package-owned `PassiveBluetoothExperimentOneControllerSession` now spans the
/// exact four-window OFF1 -> ON1 -> OFF2 -> ON2 producer, post-admission exact-target
/// rediscovery, passive controller acquisition, trusted Ready -> Horizon finalization,
/// immutable JSON, local integrity summary, and Share. The app never receives the
/// admission token, mutable recorder, target authority, or generic controller.
///
/// A repeatable full CoreBluetooth UUID remains only a correlated Bluetooth target.
/// No state in this view authenticates the physical scooter or assigns GATT/Tuya/
/// telemetry semantics. The workflow is passive/read-only and the initial recipe is
/// stationary.
@MainActor
struct ES80CaptureShellView: View {
    private enum Phase: Equatable {
        case bluetoothUnavailable(String)
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
        case connecting(UUID)
        case passiveDiscovery(UUID)
        case observationReady(UUID, retainedTransport: Bool)
        case readyToFinish(UUID, retainedTransport: Bool)
        case finalizing
        case complete
        case failed(String)
    }

    private struct ArtifactSummary: Sendable {
        let sessionID: UUID
        let byteCount: Int
        let recordCount: Int
        let valueRecordCount: Int
        let sha256: String
    }

    private enum ArtifactAnalysis: Sendable {
        case ready(ArtifactSummary)
        case unavailable(sha256: String, reason: String)
    }

    private struct FinalizedCaptureArtifact: Sendable, Transferable {
        let data: Data
        let analysis: ArtifactAnalysis
        let fileName: String

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(exportedContentType: .json) { artifact in
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent(artifact.fileName, isDirectory: false)
                try artifact.data.write(to: destination, options: .atomic)
                return SentTransferredFile(destination)
            }
        }
    }

    private static let correlationGuidanceDuration: TimeInterval = 10
    private static let correlationGuidanceNanoseconds: UInt64 = 10_000_000_000

    let session: PassiveBluetoothExperimentOneControllerSession

    @Environment(\.scenePhase) private var scenePhase

    @State private var correlatedTargetIdentifier: UUID?
    @State private var rediscoveryRequested = false
    @State private var observedCorrelationScanBeganAtUptimeNanoseconds: UInt64?
    @State private var diagnosticMessage: String?
    @State private var lifecycleFailureMessage: String?
    @State private var isFinalizing = false
    @State private var finalizedArtifact: FinalizedCaptureArtifact?
    @State private var showsArtifactDetails = false

    private var correlationSession: PassiveBluetoothPowerCycleObservationSession {
        session.powerCycleObservationSession
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let currentPhase = phase
            let nowUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero(for: currentPhase)
                    procedureBoundary

                    if finalizedArtifact == nil {
                        correlationProgress
                    }

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
                synchronizeIdleTimer(for: currentPhase)
                synchronizeObservedCorrelationScanClock(isScanning: correlationIsScanning)
            }
            .onChange(of: currentPhase) { _, newPhase in
                synchronizeIdleTimer(for: newPhase)
            }
            .onChange(of: correlationIsScanning) { _, isScanning in
                synchronizeObservedCorrelationScanClock(isScanning: isScanning)
            }
        }
        .navigationTitle("Nembra Capture")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            if finalizedArtifact == nil, session.hasTargetSession {
                session.invalidateActiveCaptureForForegroundLoss()
            }
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

                    Image(systemName: phase == .complete ? "checkmark.seal.fill" : "wave.3.right.circle.fill")
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

    private var procedureBoundary: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("ES80-FINGERPRINT-v1")
                    .font(.headline.monospaced())
                    .foregroundStyle(.white)

                Text("Keep the scooter stationary for this first experiment. Nembra records software-observed Bluetooth evidence only; correlation is not physical authentication, and no control write is authorized by this workflow.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("es80.capture.procedure-boundary")
    }

    private var correlationProgress: some View {
        let completed = correlationSession.progress?.completedWindowCount
            ?? correlationSession.result?.windows.count
            ?? 0

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
                        .fill(index < completed ? .white : .white.opacity(0.12))
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
                title: "Opening a fresh observation window",
                message: "Nembra is waiting for the package-owned window producer to establish Bluetooth and scan readiness. The evidence clock has not started yet.",
                symbol: "dot.radiowaves.left.and.right"
            )
            progressIndicator()

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

            Text("The countdown is display guidance only. The producer accepts a window from its own monotonic receipt boundary; tapping early cannot manufacture duration evidence.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case let .correlationFailed(message):
            statePanel(
                eyebrow: "CORRELATION STOPPED",
                title: "Start a fresh evidence life",
                message: message,
                symbol: "arrow.counterclockwise.circle"
            )
            restartButton()

        case .noRepeatableTarget:
            statePanel(
                eyebrow: "NO UNIQUE TARGET",
                title: "No signal repeated twice",
                message: "No selectable full Bluetooth identifier was absent in both OFF windows and repeated in both ON windows. Nembra will not guess from name, RSSI, services, or a short ID.",
                symbol: "questionmark.circle"
            )
            restartButton()

        case let .ambiguousTargets(count):
            statePanel(
                eyebrow: "AMBIGUOUS TARGET",
                title: "\(count) signals followed the same pattern",
                message: "More than one selectable full Bluetooth identifier repeated the OFF / ON pattern. Nembra refuses to break the tie with weak evidence.",
                symbol: "point.3.filled.connected.trianglepath.dotted"
            )
            restartButton()

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
                message: "The same package-owned Experiment One run issued its capture admission before this fresh scan epoch. Keep the scooter ON and stationary.",
                symbol: "scope"
            )
            targetIdentifierStrip(identifier)
            progressIndicator()
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
                message: "The scanner received the same full CoreBluetooth identifier in the fresh post-admission epoch. This is local correlation evidence, not permanent hardware authentication.",
                symbol: "checkmark.circle"
            )
            targetIdentifierStrip(identifier)
            primaryButton(
                "Begin passive discovery",
                systemImage: "antenna.radiowaves.left.and.right",
                identifier: "es80.capture.start"
            ) {
                connectReacquiredTarget()
            }

        case let .targetNotConnectable(identifier):
            statePanel(
                eyebrow: "TARGET REACQUIRED",
                title: "Signal is not connectable",
                message: "CoreBluetooth reports the exact correlated identifier as non-connectable. Nembra will not promote it into a target capture session.",
                symbol: "link.badge.plus"
            )
            targetIdentifierStrip(identifier)
            secondaryButton(
                "Scan again",
                systemImage: "arrow.clockwise",
                identifier: "es80.capture.restart-rediscovery"
            ) {
                startExactTargetRediscovery(identifier)
            }

        case let .connecting(identifier):
            statePanel(
                eyebrow: "PASSIVE DISCOVERY",
                title: "Opening the target session",
                message: "Nembra is connecting the run-owned recorder to the exact correlated target. No application characteristic write is performed.",
                symbol: "link"
            )
            targetIdentifierStrip(identifier)
            progressIndicator()

        case let .passiveDiscovery(identifier):
            statePanel(
                eyebrow: "PASSIVE DISCOVERY",
                title: "Building the finite evidence map",
                message: "Keep Nembra foreground, the screen on, and the scooter stationary. Services, characteristics, descriptors, subscriptions, and raw values remain uninterpreted evidence.",
                symbol: "waveform.path.ecg"
            )
            targetIdentifierStrip(identifier)
            progressIndicator()
            Text("Do not interact with the phone while the capture is armed for any later motion experiment. This first fingerprint recipe remains stationary.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case let .observationReady(identifier, retainedTransport):
            statePanel(
                eyebrow: retainedTransport ? "EVIDENCE RETAINED" : "OBSERVATION READY",
                title: retainedTransport ? "Finite evidence is retained" : "Observation horizon is maturing",
                message: retainedTransport
                    ? "The finite acquisition is complete and retained after transport ended. Nembra will not reconnect inside this evidence life. Finish unlocks only when the trusted monotonic Ready-to-Horizon gate permits it."
                    : "Finite acquisition is complete. Keep Nembra foreground and stationary; Finish remains unavailable until the package-owned monotonic Ready-to-Horizon duration gate becomes eligible.",
                symbol: retainedTransport ? "archivebox" : "hourglass"
            )
            targetIdentifierStrip(identifier)
            progressIndicator()
            Text("There is intentionally no visual countdown claiming evidence authority. The UI polls only the accepted package gate.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case let .readyToFinish(identifier, retainedTransport):
            statePanel(
                eyebrow: retainedTransport ? "EVIDENCE RETAINED / READY" : "HORIZON READY",
                title: "Ready to seal the capture",
                message: "The finite target evidence is complete and the trusted monotonic minimum duration gate now permits one terminal Horizon. Confirm you are safely stopped before interacting.",
                symbol: "checkmark.seal"
            )
            targetIdentifierStrip(identifier)
            primaryButton(
                "I’m safely stopped — Finish Capture",
                systemImage: "seal.fill",
                identifier: "es80.capture.finish"
            ) {
                finalizeCapture()
            }

        case .finalizing:
            statePanel(
                eyebrow: "SEALING",
                title: "Freezing the immutable artifact",
                message: "Nembra is draining the accepted FIFO prefix, recording the terminal Horizon, validating authority, and materializing exact JSON. Post-H callbacks cannot become evidence for this frozen artifact.",
                symbol: "lock.doc"
            )
            progressIndicator()

        case .complete:
            captureCompletePanel()

        case let .failed(message):
            statePanel(
                eyebrow: "CAPTURE STOPPED",
                title: "Evidence failed closed",
                message: message,
                symbol: "exclamationmark.triangle"
            )
            if finalizedArtifact == nil {
                restartButton()
            }
        }
    }

    private func correlationReadyPanel(
        _ windowPhase: PassiveBluetoothPowerCycleObservationPhase
    ) -> some View {
        statePanel(
            eyebrow: phaseShortName(windowPhase),
            title: windowPhase.operatorExpectedPowerOn ? "Turn the scooter ON" : "Turn the scooter OFF",
            message: windowPhase.operatorExpectedPowerOn
                ? "Set the scooter to ON, keep it stationary, then begin this bounded observation window."
                : "Set the scooter to OFF, keep the phone Bluetooth on, then begin this bounded observation window.",
            symbol: windowPhase.operatorExpectedPowerOn ? "power.circle.fill" : "power.circle"
        )
    }

    private func correlationObservingPanel(
        _ windowPhase: PassiveBluetoothPowerCycleObservationPhase,
        nowUptimeNanoseconds: UInt64
    ) -> some View {
        let remaining = correlationGuidanceRemainingSeconds(
            nowUptimeNanoseconds: nowUptimeNanoseconds
        )
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(phaseShortName(windowPhase)) / OBSERVING")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(remaining == 0 ? "MINIMUM MET" : "\(remaining)s")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
            }

            Text(windowPhase.operatorExpectedPowerOn ? "Hold the scooter ON" : "Hold the scooter OFF")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            Text("Do not change the requested power state until the producer accepts this window. Names, RSSI, and services do not break correlation ties.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
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

            Text("This full CoreBluetooth identifier was selectable in both ON windows and absent from both OFF catalogs under one package-owned observation series. Treat it only as a correlated Bluetooth target.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func captureCompletePanel() -> some View {
        if let finalizedArtifact {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CAPTURE COMPLETE")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.secondary)

                    switch finalizedArtifact.analysis {
                    case .ready:
                        Text("Ready for analysis")
                            .font(.system(.title, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                    case .unavailable:
                        Text("Artifact sealed")
                            .font(.system(.title, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Text(completionMessage(for: finalizedArtifact.analysis))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ShareLink(item: finalizedArtifact) {
                    Label("SHARE CAPTURE", systemImage: "square.and.arrow.up.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 56)
                        .foregroundStyle(.black)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("es80.capture.share")

                secondaryButton(
                    showsArtifactDetails ? "Hide details" : "VIEW DETAILS",
                    systemImage: showsArtifactDetails ? "chevron.up" : "info.circle",
                    identifier: "es80.capture.view-details"
                ) {
                    showsArtifactDetails.toggle()
                }

                if showsArtifactDetails {
                    artifactDetails(finalizedArtifact)
                }
            }
            .padding(18)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func artifactDetails(_ artifact: FinalizedCaptureArtifact) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider().overlay(.white.opacity(0.12))

            switch artifact.analysis {
            case let .ready(summary):
                metric("Session", value: shortIdentifier(summary.sessionID))
                metric("Artifact bytes", value: summary.byteCount.formatted())
                metric("Recorded events", value: summary.recordCount.formatted())
                metric("Raw value records", value: summary.valueRecordCount.formatted())
                metric("SHA-256", value: String(summary.sha256.prefix(16)) + "…")
            case let .unavailable(sha256, reason):
                metric("Artifact bytes", value: artifact.data.count.formatted())
                metric("SHA-256", value: String(sha256.prefix(16)) + "…")
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("These are exact-file and recorded-event facts only. They do not identify Tuya fields, prove RF completeness, or verify battery/current/power/speed semantics.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("es80.capture.artifact-details")
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
                .textSelection(.enabled)
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

    private func progressIndicator() -> some View {
        ProgressView()
            .tint(.white)
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Working")
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

    private func restartButton() -> some View {
        primaryButton(
            "Restart from OFF 1",
            systemImage: "arrow.counterclockwise",
            identifier: "es80.capture.restart-correlation"
        ) {
            restartExperimentOne()
        }
    }

    private var phase: Phase {
        if finalizedArtifact != nil {
            return .complete
        }
        if isFinalizing {
            return .finalizing
        }
        if let lifecycleFailureMessage {
            return .failed(lifecycleFailureMessage)
        }
        if session.captureFailed {
            return .failed(
                session.lastDiagnostic
                    ?? "The package-owned Experiment One controller failed closed. Start a fresh evidence life."
            )
        }

        if session.hasTargetSession {
            guard let identifier = correlatedTargetIdentifier ?? selectedConnectionIdentifier else {
                return .failed("The package-owned target session has no correlated identifier available to the product surface. Nembra will not fabricate one or continue this evidence life.")
            }

            switch session.connectionPhase {
            case let .connecting(connectedIdentifier):
                return .connecting(connectedIdentifier)
            case let .connected(connectedIdentifier):
                if session.hasCompleteTargetEvidence {
                    return session.canFinalizeObservationHorizon
                        ? .readyToFinish(connectedIdentifier, retainedTransport: false)
                        : .observationReady(connectedIdentifier, retainedTransport: false)
                }
                return .passiveDiscovery(connectedIdentifier)
            case .idle:
                if session.hasCompleteTargetEvidence {
                    return session.canFinalizeObservationHorizon
                        ? .readyToFinish(identifier, retainedTransport: true)
                        : .observationReady(identifier, retainedTransport: true)
                }
                if session.isSelectedTargetAwaitingTerminalCallback {
                    return .failed("The target transport ended before finite evidence became ready. Nembra is preserving the terminal callback quarantine; start a fresh Experiment One after it resolves or relaunch if it never resolves.")
                }
                return .failed("The target session ended before finite evidence became ready. Nembra will not reconnect inside this evidence life.")
            }
        }

        if let identifier = correlatedTargetIdentifier {
            if session.bluetoothState != .poweredOn {
                return .bluetoothUnavailable(bluetoothUnavailableMessage)
            }
            if rediscoveryRequested,
               let candidate = session.discoveredPeripherals.first(where: { $0.id == identifier }) {
                return candidate.isConnectable == false
                    ? .targetNotConnectable(identifier)
                    : .targetReacquired(identifier)
            }
            return .rediscoveringTarget(identifier)
        }

        if let result = correlationSession.result {
            switch result.correlation.disposition {
            case .invalidObservationAuthority:
                return .correlationFailed("The four windows did not share one package-owned observation authority. Restart from OFF 1.")
            case .invalidObservationWindowOrder:
                return .correlationFailed("The four windows did not preserve OFF 1, ON 1, OFF 2, ON 2 ordering. Restart from OFF 1.")
            case .noRepeatableCandidate:
                return .noRepeatableTarget
            case let .ambiguousRepeatableCandidates(identifiers):
                return .ambiguousTargets(identifiers.count)
            case let .singleRepeatableCandidate(identifier):
                return .correlatedTarget(identifier)
            }
        }

        guard session.bluetoothState == .poweredOn else {
            return .bluetoothUnavailable(bluetoothUnavailableMessage)
        }
        guard let progress = correlationSession.progress else {
            return .correlationFailed("The observation producer has no remaining window and no final result. Start a fresh evidence life.")
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

    private var selectedConnectionIdentifier: UUID? {
        switch session.connectionPhase {
        case let .connecting(identifier), let .connected(identifier):
            identifier
        case .idle:
            nil
        }
    }

    private var correlationIsScanning: Bool {
        correlationSession.progress?.isScanning == true
    }

    private var correlationEvidenceIsLive: Bool {
        guard let progress = correlationSession.progress else { return false }
        return progress.isAwaitingBluetoothPower
            || progress.isAwaitingScanReadiness
            || progress.isScanning
    }

    private func beginCorrelationWindow(
        _ expectedPhase: PassiveBluetoothPowerCycleObservationPhase
    ) {
        diagnosticMessage = nil
        guard correlationSession.progress?.phase == expectedPhase else {
            diagnosticMessage = "The correlation series changed before this window could start. Restart from OFF 1."
            return
        }

        do {
            try correlationSession.startCurrentWindow()
        } catch {
            diagnosticMessage = correlationErrorMessage(error)
        }
    }

    private func completeCorrelationWindow(
        _ expectedPhase: PassiveBluetoothPowerCycleObservationPhase
    ) {
        diagnosticMessage = nil
        guard correlationSession.progress?.phase == expectedPhase,
              correlationSession.progress?.isScanning == true else {
            diagnosticMessage = "This observation window is not currently live."
            return
        }

        do {
            _ = try correlationSession.finishCurrentWindow()
            observedCorrelationScanBeganAtUptimeNanoseconds = nil
        } catch {
            diagnosticMessage = correlationErrorMessage(error)
        }
    }

    private func restartExperimentOne() {
        diagnosticMessage = nil
        do {
            try session.restartExperimentOne()
            correlatedTargetIdentifier = nil
            rediscoveryRequested = false
            observedCorrelationScanBeganAtUptimeNanoseconds = nil
            lifecycleFailureMessage = nil
            isFinalizing = false
            finalizedArtifact = nil
            showsArtifactDetails = false
        } catch {
            diagnosticMessage = "A fresh Experiment One could not start: \(String(describing: error))"
        }
    }

    private func confirmCorrelatedTarget(_ identifier: UUID) {
        correlatedTargetIdentifier = identifier
        startExactTargetRediscovery(identifier)
    }

    private func startExactTargetRediscovery(_ identifier: UUID) {
        diagnosticMessage = nil
        session.stopExactTargetRediscovery()
        rediscoveryRequested = false

        do {
            try session.prepareCaptureAndStartExactTargetRediscovery()
            rediscoveryRequested = true
        } catch {
            diagnosticMessage = "Exact-target rediscovery could not start: \(String(describing: error))"
        }
    }

    private func connectReacquiredTarget() {
        diagnosticMessage = nil
        do {
            try session.connectReacquiredTarget()
            rediscoveryRequested = false
        } catch {
            lifecycleFailureMessage = "The run-owned target admission could not become a passive capture session: \(String(describing: error)). Start a fresh Experiment One; this admission is not replayable."
        }
    }

    private func finalizeCapture() {
        guard !isFinalizing,
              finalizedArtifact == nil,
              session.canFinalizeObservationHorizon else {
            return
        }

        isFinalizing = true
        diagnosticMessage = nil

        Task { @MainActor in
            do {
                let data = try await session.encodedFinalizedObservationHorizonJSON(
                    prettyPrinted: true
                )
                let artifact = await Self.prepareFinalizedArtifact(data)
                finalizedArtifact = artifact

                do {
                    try session.teardownActiveConnectionAfterFinalization()
                } catch {
                    diagnosticMessage = "The artifact is sealed and shareable, but finalized transport teardown did not complete cleanly. Relaunch before any later capture: \(String(describing: error))"
                }
            } catch {
                lifecycleFailureMessage = "Nembra could not seal the accepted observation Horizon: \(String(describing: error)). No completion claim or Share action was created."
            }
            isFinalizing = false
        }
    }

    private nonisolated static func prepareFinalizedArtifact(
        _ data: Data
    ) async -> FinalizedCaptureArtifact {
        await Task.detached(priority: .utility) {
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

            do {
                let capture = try PassiveBluetoothCaptureJSON.decode(data)
                let valueCount = capture.records.reduce(into: 0) { count, record in
                    if case .value = record.event { count += 1 }
                }
                let summary = ArtifactSummary(
                    sessionID: capture.id,
                    byteCount: data.count,
                    recordCount: capture.records.count,
                    valueRecordCount: valueCount,
                    sha256: digest
                )
                return FinalizedCaptureArtifact(
                    data: data,
                    analysis: .ready(summary),
                    fileName: "Nembra-ES80-Capture-\(capture.id.uuidString).json"
                )
            } catch {
                return FinalizedCaptureArtifact(
                    data: data,
                    analysis: .unavailable(
                        sha256: digest,
                        reason: "The immutable bytes were preserved, but Nembra could not decode them with this build's capture schema: \(String(describing: error))"
                    ),
                    fileName: "Nembra-ES80-Capture-\(String(digest.prefix(12))).json"
                )
            }
        }.value
    }

    private func handleScenePhaseChange(_ newScenePhase: ScenePhase) {
        if newScenePhase == .active {
            if let identifier = correlatedTargetIdentifier,
               !session.hasTargetSession,
               !rediscoveryRequested,
               lifecycleFailureMessage == nil,
               finalizedArtifact == nil {
                startExactTargetRediscovery(identifier)
            }
            return
        }

        if finalizedArtifact != nil {
            return
        }

        if correlationEvidenceIsLive {
            correlationSession.abandonCurrentWindow()
            lifecycleFailureMessage = "Nembra left the active foreground while a bounded correlation window was live. This four-window series is no longer eligible for Experiment One evidence."
            diagnosticMessage = nil
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }

        if session.hasTargetSession {
            session.invalidateActiveCaptureForForegroundLoss()
            lifecycleFailureMessage = "Nembra left the active foreground before immutable artifact freeze. This durable capture is permanently invalid for Experiment One evidence; start a fresh run."
            diagnosticMessage = nil
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }

        if rediscoveryRequested {
            session.stopExactTargetRediscovery()
            rediscoveryRequested = false
        }
    }

    private func synchronizeIdleTimer(for phase: Phase) {
        switch phase {
        case .correlationStarting,
             .correlationObserving,
             .rediscoveringTarget,
             .targetReacquired,
             .connecting,
             .passiveDiscovery,
             .observationReady,
             .readyToFinish,
             .finalizing:
            UIApplication.shared.isIdleTimerDisabled = true
        default:
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func synchronizeObservedCorrelationScanClock(isScanning: Bool) {
        if isScanning {
            if observedCorrelationScanBeganAtUptimeNanoseconds == nil {
                observedCorrelationScanBeganAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
            }
        } else {
            observedCorrelationScanBeganAtUptimeNanoseconds = nil
        }
    }

    private func correlationGuidanceRemainingSeconds(
        nowUptimeNanoseconds: UInt64
    ) -> Int {
        guard let beganAt = observedCorrelationScanBeganAtUptimeNanoseconds,
              nowUptimeNanoseconds >= beganAt else {
            return Int(Self.correlationGuidanceDuration)
        }
        let elapsed = nowUptimeNanoseconds - beganAt
        guard elapsed < Self.correlationGuidanceNanoseconds else { return 0 }
        let remaining = Self.correlationGuidanceNanoseconds - elapsed
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
            return "The observation-window sequence was exhausted. Start a fresh Experiment One."
        }
    }

    private var bluetoothUnavailableMessage: String {
        switch session.bluetoothState {
        case .unknown:
            "Waiting for CoreBluetooth to report its state."
        case .resetting:
            "Bluetooth is resetting. Keep Nembra open until the radio becomes ready."
        case .unsupported:
            "This device does not expose the Bluetooth capability required for passive capture."
        case .unauthorized:
            "Bluetooth permission is unavailable. Allow Nembra to use Bluetooth before starting correlation."
        case .poweredOff:
            "Turn phone Bluetooth on before beginning the first OFF observation window. Scooter power state and phone Bluetooth state are separate requirements."
        case .poweredOn:
            "Bluetooth is ready."
        @unknown default:
            "CoreBluetooth reported an unknown state."
        }
    }

    private func phaseShortName(
        _ phase: PassiveBluetoothPowerCycleObservationPhase
    ) -> String {
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

    private func heroTitle(for phase: Phase) -> String {
        switch phase {
        case .complete:
            "Capture sealed."
        case .finalizing:
            "Seal the evidence."
        case .observationReady, .readyToFinish, .passiveDiscovery, .connecting:
            "Observe the machine."
        case .correlatedTarget, .rediscoveringTarget, .targetReacquired, .targetNotConnectable:
            "Signal locked."
        default:
            "Find the real scooter signal."
        }
    }

    private func statusTitle(for phase: Phase) -> String {
        switch phase {
        case .bluetoothUnavailable: "Preflight blocked"
        case .correlationReady: "Ready for next window"
        case .correlationStarting: "Opening observation window"
        case .correlationObserving: "Correlation live"
        case .correlationFailed, .failed: "Evidence stopped"
        case .noRepeatableTarget: "No unique target"
        case .ambiguousTargets: "Target ambiguous"
        case .correlatedTarget: "Correlated signal found"
        case .rediscoveringTarget: "Exact-target rediscovery"
        case .targetReacquired: "Exact signal reacquired"
        case .targetNotConnectable: "Target not connectable"
        case .connecting: "Opening passive target session"
        case .passiveDiscovery: "Passive discovery live"
        case .observationReady: "Observation ready"
        case .readyToFinish: "Horizon eligible"
        case .finalizing: "Sealing artifact"
        case .complete: "Immutable artifact ready"
        }
    }

    private func statusSymbol(for phase: Phase) -> String {
        switch phase {
        case .complete, .readyToFinish, .correlatedTarget, .targetReacquired:
            "checkmark.circle.fill"
        case .bluetoothUnavailable, .correlationFailed, .failed, .targetNotConnectable:
            "exclamationmark.triangle.fill"
        case .noRepeatableTarget, .ambiguousTargets:
            "questionmark.circle.fill"
        case .finalizing, .correlationStarting, .correlationObserving, .rediscoveringTarget, .connecting, .passiveDiscovery, .observationReady:
            "circle.dotted"
        case .correlationReady:
            "circle.fill"
        }
    }

    private func statusColor(for phase: Phase) -> Color {
        switch phase {
        case .bluetoothUnavailable, .correlationFailed, .failed, .targetNotConnectable:
            .orange
        default:
            .white
        }
    }

    private func completionMessage(for analysis: ArtifactAnalysis) -> String {
        switch analysis {
        case .ready:
            "The exact H-bounded JSON decoded successfully with this build and is ready to share for offline protocol analysis."
        case .unavailable:
            "The H-bounded bytes are sealed and preserved, but this build could not complete its local schema check. Share the exact artifact for recovery analysis."
        }
    }
}
