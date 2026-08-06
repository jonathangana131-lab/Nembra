import Dispatch
import Foundation

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

/// Explicit Simulator-only source for the completed-ride end-to-end proof.
///
/// The two approximately 45 m legs arrive two real seconds apart, keeping the
/// implied speed below the injected Simulator QA ceiling while producing enough
/// screened GPS evidence to render visibly as roughly `0.1 mi` in a US locale.
/// Coordinates, cadence, accuracy, and speed are deterministic test fixtures,
/// not AOVOPRO ES80 or outdoor iPhone measurements.
actor CompletedRideQALocationSource: RideLocationSource {
    private struct Coordinate: Sendable {
        let latitude: Double
        let longitude: Double
    }

    private let coordinates: [Coordinate] = [
        Coordinate(latitude: 37.334900, longitude: -122.009020),
        Coordinate(latitude: 37.335305, longitude: -122.009020),
        Coordinate(latitude: 37.335710, longitude: -122.009020)
    ]
    private let intervalNanoseconds: UInt64 = 2_000_000_000

    private var continuation: AsyncStream<RideLocationSourceEvent>.Continuation?
    private var deliveryTask: Task<Void, Never>?
    private var activeGeneration: UUID?

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
