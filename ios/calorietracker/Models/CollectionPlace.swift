import CoreLocation
import Foundation
import Observation

/// Where a collection applies: a circle around a spot the user saved while standing there.
nonisolated struct CollectionPlace: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var radiusMeters: Double = 150

    static let radiusChoices: [Double] = [100, 150, 250, 500]

    func contains(latitude: Double, longitude: Double) -> Bool {
        CLLocation(latitude: self.latitude, longitude: self.longitude)
            .distance(from: CLLocation(latitude: latitude, longitude: longitude)) <= radiusMeters
    }
}

/// When a collection applies without location: chosen weekdays between two times.
nonisolated struct CollectionSchedule: Codable, Equatable {
    /// Calendar weekday numbers, 1 = Sunday … 7 = Saturday.
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    var startMinute: Int = 8 * 60
    var endMinute: Int = 18 * 60

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard weekdays.contains(calendar.component(.weekday, from: date)) else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return startMinute <= endMinute
            ? (minute >= startMinute && minute < endMinute)
            : (minute >= startMinute || minute < endMinute)
    }
}

extension FoodCollection {
    /// True when the user is inside the collection's place or inside its schedule.
    func isActive(at coordinate: CLLocationCoordinate2D?, now: Date, calendar: Calendar = .current) -> Bool {
        if let place, let coordinate, place.contains(latitude: coordinate.latitude, longitude: coordinate.longitude) {
            return true
        }
        if let schedule, schedule.contains(now, calendar: calendar) { return true }
        return false
    }
}

extension FoodCollectionStore {
    /// Collections that apply right now, with items, in the user's order.
    func activeCollections(at coordinate: CLLocationCoordinate2D?, now: Date = Date(), calendar: Calendar = .current) -> [FoodCollection] {
        collections.filter { !$0.items.isEmpty && $0.isActive(at: coordinate, now: now, calendar: calendar) }
    }
}

/// The phone's location, asked for only while the app is in use and only when a collection
/// has a place. Nothing leaves the device.
@Observable
final class PlaceLocationService: NSObject, CLLocationManagerDelegate {
    static let shared = PlaceLocationService()

    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var authorization: CLAuthorizationStatus
    private(set) var lastUpdate: Date?
    private let manager = CLLocationManager()
    private var pending: [(CLLocationCoordinate2D?) -> Void] = []

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAllowed: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }

    /// Refreshes the location when it is older than a few minutes and some collection needs it.
    func refreshIfNeeded(collections: [FoodCollection]) {
        guard collections.contains(where: { $0.place != nil }), isAllowed else { return }
        if let lastUpdate, Date().timeIntervalSince(lastUpdate) < 300 { return }
        manager.requestLocation()
    }

    /// Asks permission if needed, then delivers one location (nil when refused or unavailable).
    func requestCurrentLocation(_ completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        pending.append(completion)
        switch authorization {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: finish(nil)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.isAllowed, !self.pending.isEmpty { self.manager.requestLocation() }
            if status == .denied || status == .restricted { self.finish(nil) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = location.coordinate
        Task { @MainActor in
            self.coordinate = coordinate
            self.lastUpdate = Date()
            self.finish(coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    private func finish(_ coordinate: CLLocationCoordinate2D?) {
        let callbacks = pending
        pending = []
        callbacks.forEach { $0(coordinate) }
    }
}
