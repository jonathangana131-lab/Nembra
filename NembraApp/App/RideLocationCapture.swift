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

    init(
        sample: RideLocationSample?,
        issue: RideLocationSourceIssue?,
        isStationary: Bool
    ) {
        self.sample = sample
        self.issue = issue
        self.isStationary = isStationary
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
actor CoreLocationRideLocationSource: RideLocationSource {
    private var continuation: AsyncStream<RideLocationSourceEvent>.Continuation?
    private var updatesTask: Task<Void, Never>?
    private var serviceSession: CLServiceSession?
    private var activeGeneration: UUID?

    func events() -> AsyncStream<RideLocationSourceEvent> {
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

        let generation = UUID()
        activeGeneration = generation
        serviceSession = CLServiceSession(authorization: .whenInUse)
        updatesTask = Task { [weak self] in
            await self?.consumeLiveUpdates(generation: generation)
        }
    }

    func stop() {
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

/// One ride-scoped bridge from phone-location transport into independent route
/// geometry and GPS-distance evidence domains.
actor RideLocationCaptureCoordinator {
    /// Legacy sink retained for tests and callers that only consume deltas. It
    /// cannot express whether the authoritative ride session accepted a sample.
    typealias DistanceSink = @Sendable (
        _ sessionID: UUID,
        _ meters: Double,
        _ receivedAtUptimeNanoseconds: UInt64
    ) async -> Void

    /// Authoritative session handoff for a screened location sample. The caller
    /// decides whether the exact ride UUID is still accepting evidence and, when
    /// a distance delta exists, owns ingesting that delta into RideEngine before
    /// returning true. Route persistence happens only after this returns true.
    /// This gives route geometry and completed GPS evidence one deterministic
    /// ride-completion cutoff without reopening `CompletedRideEvidence`.
    typealias SessionEvidenceSink = @Sendable (
        _ sessionID: UUID,
        _ distanceDeltaMeters: Double?,
        _ receivedAtUptimeNanoseconds: UInt64
    ) async -> Bool

    private let source: any RideLocationSource
    private let routeStore: (any RideRouteStore)?
    private let routeChunkSize: Int
    private let sessionEvidenceSink: SessionEvidenceSink
    private var qualityScreen: RideLocationQualityScreen
    private var routeRecorder: RideRouteRecorder?

    private var sessionID: UUID?
    private var requestedCoverage: RideDistanceCoverage = .unknown
    private var eventsTask: Task<Void, Never>?
    private var acceptedPointCount = 0
    private var qualityScreenedDistanceMeters = 0.0
    private var routePersistenceFailed = false

    /// Production/root lifecycle initializer. A screened sample is not allowed to
    /// mutate route geometry unless the authoritative ride session first accepts
    /// the same sample/delta through this callback.
    init(
        source: any RideLocationSource,
        qualityPolicy: RideLocationQualityPolicy,
        routeStore: (any RideRouteStore)?,
        routeChunkSize: Int = 8,
        sessionScopedEvidenceSink: @escaping SessionEvidenceSink
    ) throws {
        guard routeChunkSize > 0 else {
            throw RideRouteRecorderError.invalidChunkSize
        }
        self.source = source
        self.routeStore = routeStore
        self.routeChunkSize = routeChunkSize
        self.qualityScreen = RideLocationQualityScreen(policy: qualityPolicy)
        self.sessionEvidenceSink = sessionScopedEvidenceSink
    }

    /// Compatibility initializer for existing tests/callers. It preserves the
    /// previous delta callback behavior and accepts every screened point. Root
    /// production wiring should migrate to `sessionScopedEvidenceSink` so a late
    /// sample can be rejected before route persistence.
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
            sessionScopedEvidenceSink: { sessionID, distanceDeltaMeters, uptime in
                if let distanceDeltaMeters {
                    await sessionScopedDistanceSink(
                        sessionID,
                        distanceDeltaMeters,
                        uptime
                    )
                }
                return true
            }
        )
    }

    /// Transitional/test convenience for code that only observes emitted deltas
    /// and does not route them into application ride state.
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
            qualityScreen.markKnownCoverageGap()
            await markRouteGapIfAvailable()
        }

        guard let sample = event.sample else { return }

        switch qualityScreen.screen(sample) {
        case .rejected:
            return
        case let .accepted(accepted):
            guard let sessionID else { return }

            // The ride-session handoff is the cutoff authority. In particular,
            // when AppRuntime is draining an already-yielded callback after
            // `rideEnded`, RideApplicationStore can reject it here. A rejection
            // means neither route geometry nor GPS-distance accounting advances.
            let acceptedBySession = await sessionEvidenceSink(
                sessionID,
                accepted.distanceDeltaMeters,
                accepted.sample.receivedAtUptimeNanoseconds
            )
            guard acceptedBySession else { return }

            if accepted.startsNewRouteSegment {
                await markRouteGapIfAvailable()
            }

            await appendRoutePointIfAvailable(accepted.sample)
            acceptedPointCount += 1

            if let distanceDeltaMeters = accepted.distanceDeltaMeters {
                qualityScreenedDistanceMeters += distanceDeltaMeters
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

        _ = try RideRouteGeometry(manifest: manifest, chunks: chunks)
        _ = try await routeStore.commit(manifest)

        guard try await routeStore.manifest(sessionID: sessionID) == manifest else {
            throw FinalizationError.durableVerificationFailed(sessionID)
        }
        return manifest
    }
}
