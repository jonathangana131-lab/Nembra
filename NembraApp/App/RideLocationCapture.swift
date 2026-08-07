import CoreLocation
import Dispatch
import Foundation

/// Transport/authorization state from Apple's location stream. These are not
/// route-quality verdicts; `RideLocationQualityScreen` remains the authority for
/// whether a concrete coordinate can become durable ride evidence.
enum RideLocationSourceIssue: Equatable, Sendable {
    case authorizationRequestInProgress
    case authorizationDenied
    case authorizationDeniedGlobally
    case authorizationRestricted
    case accuracyLimited
    case insufficientlyInUse
    case locationUnavailable
    case serviceSessionRequired
    case invalidLocation
    case streamFailed
}

struct RideLocationSourceEvent: Equatable, Sendable {
    let sample: RideLocationSample?
    let issue: RideLocationSourceIssue?
    let isStationary: Bool
    /// Process-local receipt ordering for diagnostics that may not carry a
    /// CLLocation sample of their own. This is not scooter telemetry.
    let receivedAtUptimeNanoseconds: UInt64

    init(
        sample: RideLocationSample?,
        issue: RideLocationSourceIssue?,
        isStationary: Bool,
        receivedAtUptimeNanoseconds: UInt64? = nil
    ) {
        self.sample = sample
        self.issue = issue
        self.isStationary = isStationary
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
            ?? sample?.receivedAtUptimeNanoseconds
            ?? DispatchTime.now().uptimeNanoseconds
    }
}

/// Injectable phone-location boundary. Tests and Simulator fixtures use their
/// own implementation; production Core Location stays behind the same event
/// stream so route/distance logic never imports CoreLocation types.
protocol RideLocationSource: Sendable {
    func events() async -> AsyncStream<RideLocationSourceEvent>
    func start() async
    func stop() async
}

/// Explicit Simulator-only location transport used by the end-to-end completed
/// ride fixture. It deliberately emits ordinary raw `RideLocationSample` values
/// into the same source boundary as Core Location; no coordinate is written
/// directly to route persistence and no GPS distance is injected by the fixture.
///
/// Receipt uptime and wall-clock dates are sampled at actual delivery time. The
/// scripted path exists only to exercise software semantics and is not a claim
/// about AOVOPRO ES80 motion, outdoor GPS quality, or production cadence.
actor SimulatorRideLocationSource: RideLocationSource {
    private struct Coordinate: Sendable {
        let latitude: Double
        let longitude: Double
    }

    private let coordinates: [Coordinate]
    private let intervalNanoseconds: UInt64
    private var continuation: AsyncStream<RideLocationSourceEvent>.Continuation?
    private var deliveryTask: Task<Void, Never>?
    private var activeGeneration: UUID?

    /// The two approximately 45 m legs arrive two real seconds apart, keeping
    /// implied speed below the injected Simulator QA ceiling while producing
    /// enough screened distance to render visibly as roughly 0.1 mi in a US
    /// locale. These values remain deterministic QA fixtures only.
    static func completedRideQA() -> SimulatorRideLocationSource {
        SimulatorRideLocationSource(
            coordinates: [
                Coordinate(latitude: 37.334900, longitude: -122.009020),
                Coordinate(latitude: 37.335305, longitude: -122.009020),
                Coordinate(latitude: 37.335710, longitude: -122.009020)
            ],
            intervalNanoseconds: 2_000_000_000
        )
    }

    private init(
        coordinates: [Coordinate],
        intervalNanoseconds: UInt64
    ) {
        self.coordinates = coordinates
        self.intervalNanoseconds = intervalNanoseconds
    }

    func events() -> AsyncStream<RideLocationSourceEvent> {
        activeGeneration = nil
        deliveryTask?.cancel()
        deliveryTask = nil
        continuation?.finish()

        let pair = AsyncStream<RideLocationSourceEvent>.makeStream()
        continuation = pair.continuation
        return pair.stream
    }

    func start() {
        guard deliveryTask == nil else { return }
        let generation = UUID()
        activeGeneration = generation
        deliveryTask = Task { [weak self] in
            await self?.deliverScript(generation: generation)
        }
    }

    func stop() {
        activeGeneration = nil
        deliveryTask?.cancel()
        deliveryTask = nil
        continuation?.finish()
        continuation = nil
    }

    private func deliverScript(generation: UUID) async {
        for (index, coordinate) in coordinates.enumerated() {
            guard !Task.isCancelled,
                  activeGeneration == generation else { return }

            let receivedAtDate = Date.now
            do {
                let sample = try RideLocationSample(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    sourceMeasurementDate: receivedAtDate,
                    receivedAtDate: receivedAtDate,
                    receivedAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                    horizontalAccuracyMeters: 4,
                    isAccuracyLimited: false,
                    isSimulatedBySoftware: true
                )
                continuation?.yield(
                    RideLocationSourceEvent(
                        sample: sample,
                        issue: nil,
                        isStationary: false
                    )
                )
            } catch {
                continuation?.yield(
                    RideLocationSourceEvent(
                        sample: nil,
                        issue: .invalidLocation,
                        isStationary: false
                    )
                )
            }

            guard index < coordinates.count - 1 else { continue }
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }

        if activeGeneration == generation {
            deliveryTask = nil
        }
    }
}

/// Foreground Core Location adapter for a scooter ride.
///
/// Apple explicitly includes scooters in `.otherNavigation`. Nembra starts this
/// source only when a ride-lifecycle coordinator asks for location evidence; it
/// does not run high-accuracy location continuously at ordinary app launch.
/// Background continuation is deliberately not claimed here: that requires the
/// separate SwiftUI lifecycle/background-session gate and physical-device QA.
actor CoreLocationRideLocationSource: RideLocationSource {
    private var continuation: AsyncStream<RideLocationSourceEvent>.Continuation?
    private var updatesTask: Task<Void, Never>?
    private var serviceSession: CLServiceSession?
    private var activeGeneration: UUID?

    func events() -> AsyncStream<RideLocationSourceEvent> {
        // Replacing a consumer invalidates any older producer generation first.
        // This protects reuse across rides even if an old Core Location task is
        // still unwinding from cancellation when the next stream is created.
        activeGeneration = nil
        updatesTask?.cancel()
        updatesTask = nil
        serviceSession = nil
        continuation?.finish()

        let pair = AsyncStream<RideLocationSourceEvent>.makeStream()
        continuation = pair.continuation
        return pair.stream
    }

    func start() {
        guard updatesTask == nil else { return }

        // Holding the service session states the authorization goal explicitly
        // for the lifetime of this ride-location source. The project already has
        // NSLocationWhenInUseUsageDescription; this call is made only from a
        // user-visible ride/location flow, never as a surprise at cold launch.
        let generation = UUID()
        activeGeneration = generation
        serviceSession = CLServiceSession(authorization: .whenInUse)
        updatesTask = Task { [weak self] in
            await self?.consumeLiveUpdates(generation: generation)
        }
    }

    func stop() {
        // Invalidate before cancellation so an old task cannot report into a new
        // stream if Core Location completes asynchronously after stop returns.
        activeGeneration = nil
        updatesTask?.cancel()
        updatesTask = nil
        serviceSession = nil
        continuation?.finish()
        continuation = nil
    }

    private func consumeLiveUpdates(generation: UUID) async {
        do {
            for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                guard !Task.isCancelled,
                      activeGeneration == generation else { break }
                continuation?.yield(makeEvent(from: update))
            }
        } catch is CancellationError {
            // Normal stop/replacement path.
        } catch {
            guard activeGeneration == generation else { return }
            continuation?.yield(
                RideLocationSourceEvent(
                    sample: nil,
                    issue: .streamFailed,
                    isStationary: false
                )
            )
        }
    }

    private func makeEvent(from update: CLLocationUpdate) -> RideLocationSourceEvent {
        let issue = issue(from: update)
        guard let location = update.location else {
            return RideLocationSourceEvent(
                sample: nil,
                issue: issue ?? .locationUnavailable,
                isStationary: update.stationary
            )
        }

        do {
            let sample = try RideLocationSample(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                sourceMeasurementDate: location.timestamp,
                receivedAtDate: .now,
                receivedAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                horizontalAccuracyMeters: location.horizontalAccuracy,
                isAccuracyLimited: update.accuracyLimited,
                isSimulatedBySoftware: location.sourceInformation?.isSimulatedBySoftware ?? false
            )
            return RideLocationSourceEvent(
                sample: sample,
                issue: issue,
                isStationary: update.stationary
            )
        } catch {
            return RideLocationSourceEvent(
                sample: nil,
                issue: .invalidLocation,
                isStationary: update.stationary
            )
        }
    }

    private func issue(from update: CLLocationUpdate) -> RideLocationSourceIssue? {
        if update.authorizationDeniedGlobally { return .authorizationDeniedGlobally }
        if update.authorizationRestricted { return .authorizationRestricted }
        if update.authorizationDenied { return .authorizationDenied }
        if update.serviceSessionRequired { return .serviceSessionRequired }
        if update.authorizationRequestInProgress { return .authorizationRequestInProgress }
        if update.insufficientlyInUse { return .insufficientlyInUse }
        if update.locationUnavailable { return .locationUnavailable }
        if update.accuracyLimited { return .accuracyLimited }
        return nil
    }
}

enum RideLocationCaptureError: Error, Equatable, Sendable {
    case alreadyCapturing(UUID)
    case noActiveCapture
}

struct RideLocationCaptureSummary: Equatable, Sendable {
    let sessionID: UUID
    let routeManifest: RideRouteManifest?
    let acceptedPointCount: Int
    let qualityScreenedDistanceMeters: Double
    let routePersistenceFailed: Bool
}

/// One ride-scoped bridge from phone-location transport into two intentionally
/// separate evidence domains:
///
/// 1. accepted coordinates -> immutable route chunks for later MapKit display
/// 2. adjacent accepted coordinate distance -> RideEngine GPS-distance evidence
///
/// Route persistence failure is additive and does not discard a valid screened
/// GPS-distance delta. Conversely, a rendered/persisted route is never measured
/// later and promoted into ride distance. Both domains originate from the same
/// screened samples but remain independently truthful after that boundary.
actor RideLocationCaptureCoordinator {
    /// Production lifecycle admission sink. Every screened point carries the
    /// exact ride UUID this capture began with. Returning `false` means the ride
    /// application has already closed that session's evidence boundary, so the
    /// same point is excluded from route persistence as well as GPS distance.
    /// A nil distance is an identity/continuity event (first anchor, stationary
    /// duplicate, or source diagnostic) and must not manufacture movement.
    typealias EvidenceAdmissionSink = @Sendable (
        _ sessionID: UUID,
        _ distanceDeltaMeters: Double?,
        _ receivedAtUptimeNanoseconds: UInt64
    ) async -> Bool

    typealias DistanceSink = @Sendable (
        _ sessionID: UUID,
        _ meters: Double,
        _ receivedAtUptimeNanoseconds: UInt64
    ) async -> Void

    private let source: any RideLocationSource
    private let routeStore: (any RideRouteStore)?
    private let routeChunkSize: Int
    private let evidenceAdmissionSink: EvidenceAdmissionSink
    private var qualityScreen: RideLocationQualityScreen
    private var routeRecorder: RideRouteRecorder?

    private var sessionID: UUID?
    private var requestedCoverage: RideDistanceCoverage = .unknown
    private var eventsTask: Task<Void, Never>?
    private var acceptedPointCount = 0
    private var qualityScreenedDistanceMeters = 0.0
    private var routePersistenceFailed = false

    init(
        source: any RideLocationSource,
        qualityPolicy: RideLocationQualityPolicy,
        routeStore: (any RideRouteStore)?,
        routeChunkSize: Int = 8,
        sessionScopedEvidenceAdmissionSink: @escaping EvidenceAdmissionSink
    ) throws {
        guard routeChunkSize > 0 else {
            throw RideRouteRecorderError.invalidChunkSize
        }
        self.source = source
        self.routeStore = routeStore
        self.routeChunkSize = routeChunkSize
        self.qualityScreen = RideLocationQualityScreen(policy: qualityPolicy)
        self.evidenceAdmissionSink = sessionScopedEvidenceAdmissionSink
    }

    /// Compatibility initializer for existing callers that already scope each
    /// emitted nonzero delta to a ride UUID. The wrapper admits identity-only
    /// events and preserves the old sink behavior for positive distance deltas.
    init(
        source: any RideLocationSource,
        qualityPolicy: RideLocationQualityPolicy,
        routeStore: (any RideRouteStore)?,
        routeChunkSize: Int = 8,
        sessionScopedDistanceSink: @escaping DistanceSink
    ) throws {
        try self.init(
            source: source,
            qualityPolicy: qualityPolicy,
            routeStore: routeStore,
            routeChunkSize: routeChunkSize,
            sessionScopedEvidenceAdmissionSink: { sessionID, meters, uptime in
                if let meters, meters > 0 {
                    await sessionScopedDistanceSink(sessionID, meters, uptime)
                }
                return true
            }
        )
    }

    /// Transitional/test convenience for code that only observes emitted deltas
    /// and does not route them into application ride state. Production ride
    /// lifecycle wiring should use `sessionScopedEvidenceAdmissionSink` instead.
    init(
        source: any RideLocationSource,
        qualityPolicy: RideLocationQualityPolicy,
        routeStore: (any RideRouteStore)?,
        routeChunkSize: Int = 8,
        distanceSink: @escaping @Sendable (
            _ meters: Double,
            _ receivedAtUptimeNanoseconds: UInt64
        ) async -> Void
    ) throws {
        try self.init(
            source: source,
            qualityPolicy: qualityPolicy,
            routeStore: routeStore,
            routeChunkSize: routeChunkSize,
            sessionScopedDistanceSink: { _, meters, uptime in
                await distanceSink(meters, uptime)
            }
        )
    }

    func begin(
        sessionID: UUID,
        requestedCoverage: RideDistanceCoverage
    ) async throws {
        if let active = self.sessionID {
            throw RideLocationCaptureError.alreadyCapturing(active)
        }

        self.sessionID = sessionID
        self.requestedCoverage = requestedCoverage
        acceptedPointCount = 0
        qualityScreenedDistanceMeters = 0
        routePersistenceFailed = routeStore == nil
        routeRecorder = nil
        qualityScreen.reset()

        if let routeStore {
            do {
                let recorder = try RideRouteRecorder(
                    store: routeStore,
                    chunkSize: routeChunkSize
                )
                try await recorder.begin(
                    sessionID: sessionID,
                    coverageAlreadyPartial: requestedCoverage != .complete
                )
                routeRecorder = recorder
            } catch {
                // Location/distance evidence remains useful even if the additive
                // route store cannot begin. Do not turn a map-storage failure
                // into loss of the ride engine's independent GPS evidence.
                routeRecorder = nil
                routePersistenceFailed = true
            }
        }

        let stream = await source.events()
        eventsTask = Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled else { break }
                await self?.consume(event)
            }
        }
        await source.start()
    }

    @discardableResult
    func finish() async throws -> RideLocationCaptureSummary {
        guard let sessionID else {
            throw RideLocationCaptureError.noActiveCapture
        }

        // Finishing the source closes its AsyncStream. Await the consumer so all
        // already-yielded events reach the same ride-admission boundary before
        // finalizing the route. Buffered points rejected by the application are
        // excluded from both route persistence and GPS distance deterministically.
        await source.stop()
        if let eventsTask {
            await eventsTask.value
        }
        self.eventsTask = nil

        var manifest: RideRouteManifest?
        if let routeRecorder {
            do {
                manifest = try await routeRecorder.finish(
                    requestedCoverage: requestedCoverage
                )
            } catch {
                routePersistenceFailed = true
                manifest = nil
            }
        }

        let summary = RideLocationCaptureSummary(
            sessionID: sessionID,
            routeManifest: manifest,
            acceptedPointCount: acceptedPointCount,
            qualityScreenedDistanceMeters: qualityScreenedDistanceMeters,
            routePersistenceFailed: routePersistenceFailed
        )
        resetAfterFinish()
        return summary
    }

    private func consume(_ event: RideLocationSourceEvent) async {
        if event.issue != nil {
            // A source diagnostic is itself evidence that route continuity was
            // interrupted. First ask the application whether this diagnostic is
            // still inside the exact ride boundary. If so, materialize the gap
            // immediately so a trailing issue followed by finish cannot retain
            // a false `.complete` manifest. A buffered post-completion issue is
            // rejected and therefore cannot rewrite pre-completion route truth.
            if let sessionID {
                let admittedIssue = await evidenceAdmissionSink(
                    sessionID,
                    nil,
                    event.receivedAtUptimeNanoseconds
                )
                if admittedIssue {
                    await markRouteGapIfAvailable()
                }
            }
            qualityScreen.markKnownCoverageGap()
        }

        guard let sample = event.sample else { return }

        switch qualityScreen.screen(sample) {
        case .rejected:
            return
        case let .accepted(accepted):
            guard let sessionID else { return }
            // Exact zero displacement is not movement evidence. Route identity is
            // still checked, but RideEngine is not fed a stationary GPS sample
            // that could end the ride from inside this capture task and create a
            // coordinator.finish() self-await cycle.
            let movementDelta = accepted.distanceDeltaMeters.flatMap { $0 > 0 ? $0 : nil }
            let admitted = await evidenceAdmissionSink(
                sessionID,
                movementDelta,
                accepted.sample.receivedAtUptimeNanoseconds
            )
            guard admitted else {
                // The quality screen already advanced its accepted baseline. If
                // the application rejects this point, continuity to the next
                // point is no longer proven for either GPS distance or route
                // topology. Force the next accepted point to begin after a known
                // gap instead of measuring from evidence the ride did not admit.
                qualityScreen.markKnownCoverageGap()
                return
            }

            if accepted.startsNewRouteSegment {
                await markRouteGapIfAvailable()
            }

            await appendRoutePointIfAvailable(accepted.sample)
            acceptedPointCount += 1

            if let movementDelta {
                qualityScreenedDistanceMeters += movementDelta
            }
        }
    }

    private func markRouteGapIfAvailable() async {
        guard let routeRecorder else { return }
        do {
            try await routeRecorder.markKnownGap()
        } catch {
            self.routeRecorder = nil
            routePersistenceFailed = true
        }
    }

    private func appendRoutePointIfAvailable(_ sample: RideLocationSample) async {
        guard let routeRecorder else { return }
        do {
            try await routeRecorder.append(
                latitude: sample.latitude,
                longitude: sample.longitude,
                capturedAtDate: sample.receivedAtDate,
                sourceMeasurementDate: sample.sourceMeasurementDate,
                horizontalAccuracyMeters: sample.horizontalAccuracyMeters
            )
        } catch {
            self.routeRecorder = nil
            routePersistenceFailed = true
        }
    }

    private func resetAfterFinish() {
        sessionID = nil
        requestedCoverage = .unknown
        eventsTask = nil
        routeRecorder = nil
        qualityScreen.reset()
        acceptedPointCount = 0
        qualityScreenedDistanceMeters = 0
        routePersistenceFailed = false
    }
}

/// Finalizes durable route chunks that survived a process stop after RideEngine
/// wrote `completedPendingCommit` but before the ride-scoped recorder could
/// commit its manifest.
///
/// Recovery is deliberately conservative: surviving chunks prove that Nembra
/// recorded geometry, but a process boundary means full coverage can no longer
/// be claimed. A recovered draft therefore receives `.partial` coverage. No
/// coordinate is invented, reordered, joined across an unknown gap, or measured
/// later to manufacture GPS ride distance.
struct RideRouteDraftFinalizer: Sendable {
    enum FinalizationError: Error, Equatable, Sendable {
        case durableVerificationFailed(UUID)
    }

    private let routeStore: any RideRouteStore

    init(routeStore: any RideRouteStore) {
        self.routeStore = routeStore
    }

    @discardableResult
    func finalizePartialDraftIfNeeded(sessionID: UUID) async throws -> RideRouteManifest? {
        if let existing = try await routeStore.manifest(sessionID: sessionID) {
            return existing
        }

        let chunks = try await routeStore.chunks(sessionID: sessionID)
        guard !chunks.isEmpty else { return nil }

        let segmentIndices = Set(chunks.map(\.id.segmentIndex)).sorted()
        let pointCount = chunks.reduce(0) { $0 + $1.points.count }
        let manifest = try RideRouteManifest(
            sessionID: sessionID,
            coverage: .partial,
            segmentCount: segmentIndices.count,
            pointCount: pointCount,
            knownGapCount: max(0, segmentIndices.count - 1)
        )

        // Reuse the accepted geometry validator before making a recovered
        // manifest durable. It rejects mismatched sessions, non-contiguous
        // segments/chunks, bad sequence ordering, and count mismatches.
        _ = try RideRouteGeometry(manifest: manifest, chunks: chunks)
        _ = try await routeStore.commit(manifest)

        guard try await routeStore.manifest(sessionID: sessionID) == manifest else {
            throw FinalizationError.durableVerificationFailed(sessionID)
        }
        return manifest
    }
}
