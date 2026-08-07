import NembraCore

public enum NavigationRouteSelectionError: Error, Equatable, Sendable {
    case emptyRoutes
    case invalidSelectionIndex
}

/// Explicit selection state for one immutable provider result set.
///
/// Nembra deliberately starts unselected even when one or more routes exist;
/// provider ordering is preserved but is not promoted into a product claim that
/// the first route is "best", safest, legal for scooters, or user-preferred.
public struct NavigationRouteSelectionState: Equatable, Sendable {
    public private(set) var routes: [NavigationRouteSnapshot]
    public private(set) var selectedIndex: Int?

    public init(routes: [NavigationRouteSnapshot]) throws {
        guard !routes.isEmpty else {
            throw NavigationRouteSelectionError.emptyRoutes
        }
        self.routes = routes
        selectedIndex = nil
    }

    public var selectedRoute: NavigationRouteSnapshot? {
        guard let selectedIndex else { return nil }
        return routes[selectedIndex]
    }

    public mutating func select(index: Int) throws {
        guard routes.indices.contains(index) else {
            throw NavigationRouteSelectionError.invalidSelectionIndex
        }
        selectedIndex = index
    }

    public mutating func clearSelection() {
        selectedIndex = nil
    }

    /// Replacing a provider result set always clears selection. Route indices are
    /// meaningful only within the exact immutable result array they came from.
    public mutating func replaceRoutes(
        _ newRoutes: [NavigationRouteSnapshot]
    ) throws {
        guard !newRoutes.isEmpty else {
            throw NavigationRouteSelectionError.emptyRoutes
        }
        routes = newRoutes
        selectedIndex = nil
    }
}
