import SwiftUI
import UIKit
import CoreLocation
import UserNotifications

/// Wraps the real iOS location and notification permission prompts so
/// onboarding can show the system "Allow" dialogs and reflect what the user chose.
@MainActor
@Observable
final class Permissions: NSObject, CLLocationManagerDelegate {
    enum State { case notAsked, allowed, denied }

    private(set) var location: State = .notAsked
    private(set) var notifications: State = .notAsked

    @ObservationIgnored private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        location = Self.state(for: locationManager.authorizationStatus)
        Task { await refreshNotifications() }
    }

    /// Shows the system "Allow Swipe-n-Go to use your location?" dialog.
    func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Shows the system "Swipe-n-Go Would Like to Send You Notifications" dialog.
    func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        await refreshNotifications()
    }

    /// Re-reads both statuses, e.g. after the user comes back from Settings.
    func refresh() async {
        location = Self.state(for: locationManager.authorizationStatus)
        await refreshNotifications()
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func refreshNotifications() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notifications = switch status {
        case .authorized, .provisional, .ephemeral: .allowed
        case .denied: .denied
        default: .notAsked
        }
    }

    private static func state(for status: CLAuthorizationStatus) -> State {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: .allowed
        case .denied, .restricted: .denied
        default: .notAsked
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.location = Self.state(for: status) }
    }
}
