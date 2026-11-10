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
            await syncAttendance(baseURL: url)
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
                let old = activities[i]
                var updated = Activity(server: event, hostID: old.hostID)
                updated.attendeeIDs = old.attendeeIDs
                updated.coverPhotoData = old.coverPhotoData
                updated.seriesID = old.seriesID
                updated.hostToken = old.hostToken
                updated.myAttendeeID = old.myAttendeeID
                updated.myAttendeeToken = old.myAttendeeToken
                updated.serverAttendeeIDs = old.serverAttendeeIDs
                if updated.locationHidden == true, old.locationHidden != true {
                    // The public list hides private locations; keep the one this phone already has
                    // (you're the host, or the server already shared it with you).
                    updated.placeName = old.placeName
                    updated.address = old.address
                    updated.latitude = old.latitude
                    updated.longitude = old.longitude
                    updated.locationHidden = nil
                }
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
            markUploaded(activity.id, serverID: created.id, hostToken: created.hostToken)
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

    private func markUploaded(_ id: UUID, serverID: String, hostToken: String? = nil) {
        guard let i = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[i].serverID = serverID
        if let hostToken { activities[i].hostToken = hostToken }
        save()
    }

    // MARK: - Attendees on the server (see docs/API.md)

    /// Hosts pick up requests from other phones; guests find out when a host
    /// approved them, which is when a private location is shared.
    private func syncAttendance(baseURL url: URL) async {
        for activity in activities where activity.serverID != nil && !activity.isPast {
            if isHost(activity), let token = activity.hostToken {
                await pullServerRequests(for: activity, hostToken: token, baseURL: url)
            } else if activity.locationHidden == true, let token = activity.myAttendeeToken {
                await revealLocationIfApproved(activity, attendeeToken: token, baseURL: url)
            }
        }
    }

    private func pullServerRequests(for activity: Activity, hostToken: String, baseURL url: URL) async {
        guard let serverID = activity.serverID,
              let attendees = try? await EventServer.attendees(eventID: serverID, hostToken: hostToken, baseURL: url),
              let i = activities.firstIndex(where: { $0.id == activity.id }) else { return }
        let known = Set(activities[i].serverAttendeeIDs?.values.map { $0 } ?? [])
            .union(requests.compactMap(\.serverAttendeeID))
        // Requests withdrawn on the server disappear here too.
        let listed = Set(attendees.map(\.id))
        requests.removeAll { $0.activityID == activity.id && $0.serverAttendeeID.map { !listed.contains($0) } == true }
        for attendee in attendees where !known.contains(attendee.id) {
            let guest = Person.serverHost(named: attendee.name, category: activity.category, bio: "Joined from Swipe-n-Go.")
            if person(guest.id) == nil { people.append(guest) }
            if attendee.isApproved {
                activities[i].serverAttendeeIDs = (activities[i].serverAttendeeIDs ?? [:]).merging([guest.id: attendee.id]) { $1 }
                if !activities[i].attendeeIDs.contains(guest.id) { activities[i].attendeeIDs.append(guest.id) }
            } else {
                requests.append(JoinRequest(activityID: activity.id, personID: guest.id, note: "Wants to join your plan.", date: .now,
                                            serverAttendeeID: attendee.id))
                show(InAppBanner(title: "New join request", subtitle: "\(guest.firstName) wants to join \(activity.title)",
                                 symbol: "person.crop.circle.badge.plus", color: activity.category.color))
            }
        }
        save()
    }

    private func revealLocationIfApproved(_ activity: Activity, attendeeToken: String, baseURL url: URL) async {
        guard let serverID = activity.serverID,
              // 403 until the host approves you: the server keeps the location until then.
              let location = try? await EventServer.location(eventID: serverID, as: .attendee(attendeeToken), baseURL: url),
              let i = activities.firstIndex(where: { $0.id == activity.id }) else { return }
        activities[i].placeName = location.locationName
        activities[i].address = location.address ?? location.locationName
        if let lat = location.latitude, let lon = location.longitude {
            activities[i].latitude = lat
            activities[i].longitude = lon
        }
        activities[i].locationHidden = nil
        if isPending(activities[i]) {
            confirmServerApproval(activities[i].id)
        } else {
            save()
        }
    }

    /// Calls the server for host and guest actions on a shared event. Returns false (and says why) if it refused.
    func serverAction(_ action: (URL) async throws -> Void) async -> Bool {
        guard let url = serverURL else {
            show(InAppBanner(title: "Server not set", subtitle: "Set a server in Profile → Server to manage shared plans.",
                             symbol: "icloud.slash", color: .orange))
            return false
        }
        do {
            try await action(url)
            return true
        } catch {
            show(InAppBanner(title: "Couldn't update the plan", subtitle: Self.describe(error),
                             symbol: "exclamationmark.icloud", color: .orange))
            return false
        }
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
