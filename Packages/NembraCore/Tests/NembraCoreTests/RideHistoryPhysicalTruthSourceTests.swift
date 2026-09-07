import Foundation
import Testing

@Suite("Ride history physical truth")
struct RideHistoryPhysicalTruthSourceTests {
    @Test("Ride journal keeps scooter odometer and GPS distance as separate evidence")
    func journalKeepsDistanceSourcesSeparate() throws {
        let source = try rideHistoryViewSection()

        #expect(source.contains("Scooter odometer and GPS distance stay separate so the journal never turns one source into another."))
        #expect(source.contains("label: \"SCOOTER\""))
        #expect(source.contains("label: \"GPS\""))
        #expect(source.contains("qualityScreenedGPSDistanceMeters"))
        #expect(source.contains("startingOdometerKilometers"))
        #expect(source.contains("endingOdometerKilometers"))
        #expect(!source.contains("battery"))
        #expect(!source.contains("rideMode"))
        #expect(!source.contains("headlight"))
    }

    @Test("Ride detail exposes recorded evidence without collapsing source provenance")
    func detailPreservesRecordedEvidenceProvenance() throws {
        let source = try rideHistoryDetailSection()

        #expect(source.contains("title: \"Scooter\""))
        #expect(source.contains("subtitle: \"Odometer change\""))
        #expect(source.contains("title: \"GPS\""))
        #expect(source.contains("subtitle: \"Quality-screened distance\""))
        #expect(source.contains("Scooter and GPS distances are recorded independently."))
        #expect(source.contains("No positive distance measurement is available for this ride."))
        #expect(!source.contains("hasLiveVehicleCommandAuthority"))
        #expect(!source.contains("VehicleTelemetry"))
    }

    private func rideHistoryViewSection() throws -> Substring {
        let source = try readRepositoryFile("NembraApp/App/AppRootView.swift")
        guard let start = source.range(of: "private struct RideHistoryView: View"),
              let end = source.range(of: "private struct RideHistoryRowView: View", range: start.upperBound..<source.endIndex) else {
            Issue.record("RideHistoryView source section was not found")
            throw SourceContractError.sectionMissing
        }
        return source[start.lowerBound..<end.lowerBound]
    }

    private func rideHistoryDetailSection() throws -> Substring {
        let source = try readRepositoryFile("NembraApp/App/AppRootView.swift")
        guard let start = source.range(of: "private struct RideHistoryDetailView: View") else {
            Issue.record("RideHistoryDetailView source section was not found")
            throw SourceContractError.sectionMissing
        }
        return source[start.lowerBound..<source.endIndex]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
        return String(decoding: data, as: UTF8.self)
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
