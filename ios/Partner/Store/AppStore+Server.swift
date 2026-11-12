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
        guard auth.isSignedIn else { return }
        if !serverStatus.isOnline { serverStatus = .connecting }
        do {
            let events = try await EventServer.fetchEvents(baseURL: url)
            merge(events)
            serverStatus = .online(events: events.count, at: .now)
            await uploadPendingHostedEvents()
            await syncCovers(baseURL: url)
            await syncSaved(baseURL: url)
            await syncName(baseURL: url)
            await syncAttendance(baseURL: url)
        } catch let error as EventServer.ServerError where error.status == 401 || error.status == 403 {
            // The server no longer accepts this sign-in (expired, revoked, or not @ucdavis.edu).
            auth.signOut(message: error.message)
        } catch {
            serverStatus = .offline(Self.describe(error))
        }
    }

    // MARK: - Sign-in (see Auth.swift)

    /// After signing in: the server records the account and double-checks it's @ucdavis.edu.
    /// Without a server (or if it's unreachable) the sign-in stands; every request is checked anyway.
    func confirmSignIn() async {
        guard let url = serverURL, let account = auth.account else { return }
        do {
            let user = try await EventServer.confirmSignIn(baseURL: url)
            adoptAccountName(user)
        } catch let error as EventServer.ServerError where error.status == 401 || error.status == 403 {
            if auth.account == account { auth.signOut(message: error.message) }
        } catch {
            // Offline: try again on the next sync.
        }
    }

    /// Whether the server offers dev sign-in (local servers with DEV_SIGN_IN=on only).
    func devSignInAvailable() async -> Bool {
        guard let url = serverURL else { return false }
        return (try? await EventServer.authConfig(baseURL: url).devSignIn) ?? false
    }

    private func merge(_ events: [EventServer.ServerEvent]) {
        // Runs every 15 seconds: only touch (and save) what actually changed, so the screen
        // isn't redrawn and the state file isn't rewritten when nothing is new.
        let before = activities
        var newHosts: [Person] = []
        var fetched = Set<UUID>()
        for event in events {
            let localID = EventServer.localID(for: event.id)
            fetched.insert(localID)
            if let i = activities.firstIndex(where: { $0.id == localID }) {
                // Refresh server-owned details, keep what only this phone knows.
                let old = activities[i]
                var updated = Activity(server: event, hostID: hostedByMe(event) ? me.id : old.hostID)
                updated.attendeeIDs = old.attendeeIDs
                updated.coverPhotoData = old.coverPhotoData
                updated.coverSyncedURL = old.coverSyncedURL
                updated.seriesID = old.seriesID
                updated.myAttendeeID = old.myAttendeeID
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
                if activities[i] != updated { activities[i] = updated }
            } else if hostedByMe(event) {
                // Posted from your account on another phone (or before reinstalling).
                activities.append(Activity(server: event, hostID: me.id))
            } else {
                let host = Person.serverHost(named: event.hostName, category: ActivityCategory(serverValue: event.category))
                if person(host.id) == nil, !newHosts.contains(where: { $0.id == host.id }) { newHosts.append(host) }
                activities.append(Activity(server: event, hostID: host.id))
            }
        }
        if !newHosts.isEmpty { people.append(contentsOf: newHosts) }
        // Drop server events that disappeared, unless you're part of them.
        if activities.contains(where: { a in
            a.serverID != nil && !fetched.contains(a.id) && !isHost(a) && !isGoing(a) && !isPending(a)
        }) {
            activities.removeAll { a in
                a.serverID != nil && !fetched.contains(a.id) && !isHost(a) && !isGoing(a) && !isPending(a)
            }
        }
        if !activities.isSorted(by: { $0.date <= $1.date }) { activities.sort { $0.date < $1.date } }
        if activities != before || !newHosts.isEmpty { save() }
    }

    /// Sends the name from your profile, so your events show it instead of the sign-in name.
    /// If the server can't be reached, it's sent on the next sync.
    func syncMyName() async {
        let name = me.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        nameNeedsSync = true
        guard let url = serverURL, auth.isSignedIn else { return }
        if (try? await EventServer.updateMyName(name, baseURL: url)) != nil,
           me.name.trimmingCharacters(in: .whitespacesAndNewlines) == name {
            nameNeedsSync = false
        }
    }

    /// The account's name is the one on the server, so every device signed in to it shows the same
    /// one. This device's name is only sent when it was changed here (or none was ever chosen).
    private func adoptAccountName(_ user: EventServer.SignedInUser) {
        if let chosen = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !chosen.isEmpty {
            if me.name != chosen, !nameNeedsSync { me.name = chosen; save() }
            if nameNeedsSync { Task { await syncMyName() } }
        } else if me.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            me.name = user.name
            save()
        } else {
            Task { await syncMyName() }
        }
    }

    private func syncName(baseURL url: URL) async {
        if nameNeedsSync { await syncMyName(); return }
        if let user = try? await EventServer.me(baseURL: url) { adoptAccountName(user) }
    }

    // MARK: Saved events

    /// Records a save or unsave of a server event and sends it. Sample events stay on this phone.
    func savedChanged(_ activity: Activity, saved: Bool) {
        guard let serverID = activity.serverID else { return }
        pendingSaves[serverID] = saved
        Task { await sendPendingSaves() }
    }

    /// Sends saves made on this phone. Each one is kept until the server confirms it.
    func sendPendingSaves() async {
        guard let url = serverURL, auth.isSignedIn, !pendingSaves.isEmpty else { return }
        let pendingBefore = pendingSaves.count
        for (eventID, saved) in pendingSaves {
            do {
                try await EventServer.setSaved(eventID, saved, baseURL: url)
            } catch let error as EventServer.ServerError where error.status == 404 {
                // The event is gone; nothing to save.
            } catch {
                break   // offline: try again on the next sync
            }
            // Only clear it if it wasn't changed again while the request was in flight.
            if pendingSaves[eventID] == saved { pendingSaves[eventID] = nil }
        }
        if pendingSaves.count != pendingBefore { save() }
    }

    /// The server's list is the truth for server events once this phone's changes are sent.
    private func syncSaved(baseURL url: URL) async {
        await sendPendingSaves()
        guard pendingSaves.isEmpty, let ids = try? await EventServer.savedEventIDs(baseURL: url) else { return }
        let onServer = Set(ids.map(EventServer.localID(for:)))
        let serverEvents = Set(activities.filter { $0.serverID != nil }.map(\.id))
        let merged = savedIDs.subtracting(serverEvents).union(onServer)
        guard merged != savedIDs else { return }
        savedIDs = merged
        save()
    }

    /// Hosts upload their cover once; everyone else downloads covers they don't have yet.
    private func syncCovers(baseURL url: URL) async {
        for activity in activities where activity.serverID != nil && !activity.isPast {
            guard let serverID = activity.serverID else { continue }
            if isHost(activity), let photo = activity.coverPhotoData, activity.coverSyncedURL == nil {
                guard let jpeg = Self.coverJPEG(photo),
                      let imageURL = try? await EventServer.uploadCover(eventID: serverID, jpeg: jpeg, baseURL: url),
                      let i = activities.firstIndex(where: { $0.id == activity.id }) else { continue }
                activities[i].serverCoverURL = imageURL
                activities[i].coverSyncedURL = imageURL
                save()
            } else if let imageURL = activity.serverCoverURL, imageURL != activity.coverSyncedURL {
                guard let data = try? await EventServer.downloadCover(imageURL, baseURL: url),
                      UIImage(data: data) != nil,
                      let i = activities.firstIndex(where: { $0.id == activity.id }) else { continue }
                activities[i].coverPhotoData = data
                activities[i].coverSyncedURL = imageURL
                save()
            }
        }
    }

    /// The cover as a JPEG the server accepts (under 900 KB), shrinking quality if needed.
    static func coverJPEG(_ data: Data) -> Data? {
        guard let original = UIImage(data: data), original.size.width > 0, original.size.height > 0 else { return nil }
        // Covers are shown at most 1600 points wide; a full-size photo or flyer is shrunk first
        // (in pixels, scale 1), or it could never fit under the limit.
        let pixels = CGSize(width: original.size.width * original.scale, height: original.size.height * original.scale)
        let shrink = min(1, 1600 / max(pixels.width, pixels.height))
        let size = CGSize(width: (pixels.width * shrink).rounded(), height: (pixels.height * shrink).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            original.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [0.8, 0.65, 0.5, 0.35, 0.2] {
            if let jpeg = image.jpegData(compressionQuality: quality), jpeg.count <= 900 * 1024 { return jpeg }
        }
        return nil
    }

    private func hostedByMe(_ event: EventServer.ServerEvent) -> Bool {
        event.hostId != nil && event.hostId == auth.account?.id
    }

    /// Sends a plan you host to the server. Safe to call more than once:
    /// the app sends its own id, so a retry can't create a duplicate.
    func upload(_ activity: Activity) async {
        guard let url = serverURL, activity.serverID == nil, isHost(activity), !activity.isPast,
              !rejectedUploads.contains(activity.id) else { return }
        do {
            let created = try await EventServer.create(activity.serverBody(), baseURL: url)
            markUploaded(activity.id, serverID: created.id)
            // Send the cover now rather than on the next sync. It's retried every sync until the
            // server has it, so a failed upload never leaves other devices without one for good.
            await syncCovers(baseURL: url)
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

    // MARK: - Attendees on the server (see docs/API.md)

    /// Hosts pick up requests from other phones; guests find out when a host
    /// approved them, which is when a private location is shared.
    private func syncAttendance(baseURL url: URL) async {
        for activity in activities where activity.serverID != nil && !activity.isPast {
            if isHost(activity) {
                await pullServerRequests(for: activity, baseURL: url)
            } else if activity.locationHidden == true, activity.myAttendeeID != nil {
                await revealLocationIfApproved(activity, baseURL: url)
            }
        }
    }

    private func pullServerRequests(for activity: Activity, baseURL url: URL) async {
        guard let serverID = activity.serverID,
              let attendees = try? await EventServer.attendees(eventID: serverID, baseURL: url),
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

    private func revealLocationIfApproved(_ activity: Activity, baseURL url: URL) async {
        guard let serverID = activity.serverID,
              // 403 until the host approves you: the server keeps the location until then.
              let location = try? await EventServer.location(eventID: serverID, baseURL: url),
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

private extension Array {
    func isSorted(by inOrder: (Element, Element) -> Bool) -> Bool {
        zip(self, dropFirst()).allSatisfy { inOrder($0, $1) }
    }
}
