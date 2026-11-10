import SwiftUI

enum ServerStatus: Equatable {
    case off                          // no server address set
    case connecting
    case online(events: Int, at: Date)
    case offline(String)

    var isOnline: Bool { if case .online = self { true } else { false } }
}

/// Keeps the shared events in sync with the backend. Everything else
/// (joining, chats, requests) still lives on this phone for now.
extension AppStore {
    static let serverURLKey = "serverURL"
    static let showSampleEventsKey = "showSampleEvents"

    static var defaultServerURL: String {
        #if targetEnvironment(simulator)
        "http://localhost:8080"     // the simulator shares the Mac's network
        #else
        ""                          // on a phone, enter the Mac's Wi-Fi address in Profile → Server
        #endif
    }

    var serverURL: URL? {
        let trimmed = serverURLString.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "http://" + trimmed
        guard let url = URL(string: withScheme), url.host() != nil else { return nil }
        return url
    }

    /// Events shown in Discover and Explore: server events and your own,
    /// plus the built-in samples unless they're turned off.
    var feedActivities: [Activity] {
        guard !showSampleEvents else { return activities }
        return activities.filter { $0.serverID != nil || isHost($0) || isGoing($0) || isPending($0) }
    }

    func syncWithServer() async {
        guard let url = serverURL else {
            serverStatus = .off
            return
        }
        if !serverStatus.isOnline { serverStatus = .connecting }
        do {
            let events = try await EventServer.fetchEvents(baseURL: url)
            merge(events)
            serverStatus = .online(events: events.count, at: .now)
            await uploadPendingHostedEvents()
        } catch {
            serverStatus = .offline(Self.describe(error))
        }
    }

    private func merge(_ events: [EventServer.ServerEvent]) {
        var newHosts: [Person] = []
        var fetched = Set<UUID>()
        for event in events {
            let localID = EventServer.localID(for: event.id)
            fetched.insert(localID)
            if let i = activities.firstIndex(where: { $0.id == localID }) {
                // Refresh server-owned details, keep what only this phone knows.
                var updated = Activity(server: event, hostID: activities[i].hostID)
                updated.attendeeIDs = activities[i].attendeeIDs
                updated.coverPhotoData = activities[i].coverPhotoData
                updated.seriesID = activities[i].seriesID
                activities[i] = updated
            } else {
                let host = Person.serverHost(named: event.hostName, category: ActivityCategory(serverValue: event.category))
                if person(host.id) == nil, !newHosts.contains(where: { $0.id == host.id }) { newHosts.append(host) }
                activities.append(Activity(server: event, hostID: host.id))
            }
        }
        if !newHosts.isEmpty { people.append(contentsOf: newHosts) }
        // Drop server events that disappeared, unless you're part of them.
        activities.removeAll { a in
            a.serverID != nil && !fetched.contains(a.id) && !isHost(a) && !isGoing(a) && !isPending(a)
        }
        activities.sort { $0.date < $1.date }
        save()
    }

    /// Sends a plan you host to the server. Safe to call more than once:
    /// the app sends its own id, so a retry can't create a duplicate.
    func upload(_ activity: Activity) async {
        guard let url = serverURL, activity.serverID == nil, isHost(activity), !activity.isPast,
              !rejectedUploads.contains(activity.id) else { return }
        do {
            let created = try await EventServer.create(activity.serverBody(hostName: me.name), baseURL: url)
            markUploaded(activity.id, serverID: created.id)
        } catch let error as EventServer.ServerError where error.message.contains("already exists") {
            markUploaded(activity.id, serverID: activity.id.uuidString.lowercased())
        } catch let error as EventServer.ServerError {
            // The server answered but refused the plan: say why once, don't retry.
            rejectedUploads.insert(activity.id)
            show(InAppBanner(title: "Not shared with others", subtitle: error.message,
                             symbol: "exclamationmark.icloud", color: .orange))
        } catch {
            serverStatus = .offline(Self.describe(error))
            show(InAppBanner(title: "Saved on this phone only",
                             subtitle: "Couldn't reach the server. We'll try again when it's back.",
                             symbol: "icloud.slash", color: .orange))
        }
    }

    /// Retries any of your plans that were created while the server was unreachable.
    func uploadPendingHostedEvents() async {
        for activity in activities where activity.serverID == nil && isHost(activity) && !activity.isPast {
            await upload(activity)
        }
    }

    private func markUploaded(_ id: UUID, serverID: String) {
        guard let i = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[i].serverID = serverID
        save()
    }

    private static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost:
                return "Can't reach the server. Is it running, and is this device on the same Wi-Fi?"
            case .notConnectedToInternet:
                return "This device is offline."
            case .appTransportSecurityRequiresSecureConnection:
                return "iOS blocked this address. Use your Mac's local IP (like 192.168.x.x) or an https URL."
            default:
                return urlError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
