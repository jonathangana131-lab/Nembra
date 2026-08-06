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
    typealias DistanceSink = @Sendable (_ meters: Double, _ receivedAtUptimeNanoseconds: UInt64) async -> Void

    private let source: any RideLocationSource
    private let routeStore: (any RideRouteStore)?
    private let routeChunkSize: Int
    private let distanceSink: DistanceSink
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
        distanceSink: @escaping DistanceSink
    ) throws {
        guard routeChunkSize > 0 else {
            throw RideRouteRecorderError.invalidChunkSize
        }
        self.source = source
        self.routeStore = routeStore
        self.routeChunkSize = routeChunkSize
        self.qualityScreen = RideLocationQualityScreen(policy: qualityPolicy)
        self.distanceSink = distanceSink
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
        // already-yielded evidence is screened before finalizing the route.
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
            // An explicit Core Location diagnostic means continuity is no longer
            // justified. Mark both evidence domains immediately. The recorder's
            // gap marker is lazy: before the first point it only forces partial
            // coverage, and after points exist it materializes a new segment only
            // when another valid coordinate is later accepted.
            qualityScreen.markKnownCoverageGap()
            await markRouteGapIfAvailable()
        }

        guard let sample = event.sample else { return }

        switch qualityScreen.screen(sample) {
        case .rejected:
            return
        case let .accepted(accepted):
            if accepted.startsNewRouteSegment {
                // Repeating the marker is intentionally harmless; the route
                // recorder collapses repeated gap notifications until a new
                // accepted point actually exists.
                await markRouteGapIfAvailable()
            }

            await appendRoutePointIfAvailable(accepted.sample)
            acceptedPointCount += 1

            if let distanceDeltaMeters = accepted.distanceDeltaMeters {
                qualityScreenedDistanceMeters += distanceDeltaMeters
                await distanceSink(
                    distanceDeltaMeters,
                    accepted.sample.receivedAtUptimeNanoseconds
                )
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
