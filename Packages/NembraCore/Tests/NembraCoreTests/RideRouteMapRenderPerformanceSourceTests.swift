import Foundation
import Testing

@Suite("Ride route map render performance source")
struct RideRouteMapRenderPerformanceSourceTests {
    @Test("Route rendering does not rebuild the same segment coordinates twice per body pass")
    func avoidsDuplicateCoordinateProjection() throws {
        let source = try String(contentsOf: appRootViewURL, encoding: .utf8)

        let mapStart = try #require(source.range(of: "private struct RideRouteMapView: View"))
        let mapSource = String(source[mapStart.lowerBound...])

        #expect(!mapSource.contains("MapPolyline(coordinates: coordinates(for: segment))\n                        .stroke(Color(uiColor: .systemBackground), lineWidth: 8)\n                    MapPolyline(coordinates: coordinates(for: segment))"))
    }

    @Test("Route region calculation does not allocate one flattened all-points array on every body evaluation")
    func avoidsRepeatedFlattenedRegionProjection() throws {
        let source = try String(contentsOf: appRootViewURL, encoding: .utf8)

        let mapStart = try #require(source.range(of: "private struct RideRouteMapView: View"))
        let mapSource = String(source[mapStart.lowerBound...])

        #expect(!mapSource.contains("let allPoints = geometry.segments.flatMap(\\.points)"))
    }

    private var appRootViewURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NembraApp/App/AppRootView.swift")
    }
}
