import SwiftUI
import MapKit
import PhotosUI
import ImageIO
import AVFoundation
import Speech

extension Place {
    /// Popular spots that match, then Apple Maps results near Davis.
    static func search(_ query: String) async -> [Place] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let local = presets.filter { $0.name.localizedCaseInsensitiveContains(q) }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        request.region = MKCoordinateRegion(center: Geo.home, span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6))
        guard let response = try? await MKLocalSearch(request: request).start() else { return local }
        let found = response.mapItems.prefix(12).map { item in
            Place(name: item.name ?? q,
                  address: item.address?.shortAddress ?? item.address?.fullAddress ?? "",
                  latitude: item.location.coordinate.latitude,
                  longitude: item.location.coordinate.longitude)
        }
        return local + found
    }
}

struct Place: Codable, Identifiable, Hashable {
    var id: String { "\(name)|\(latitude)|\(longitude)" }
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double

    static let presets: [Place] = [
        Place(name: "UC Davis Arboretum", address: "Garrod Dr, Davis, CA", latitude: 38.5372, longitude: -121.7531),
        Place(name: "Central Park", address: "4th & C St, Davis, CA", latitude: 38.5455, longitude: -121.7442),
        Place(name: "Activities & Recreation Center", address: "ARC, UC Davis", latitude: 38.5426, longitude: -121.7597),
        Place(name: "Memorial Union", address: "Memorial Union, UC Davis", latitude: 38.5424, longitude: -121.7494),
        Place(name: "Mishka's Café", address: "610 2nd St, Davis, CA", latitude: 38.5440, longitude: -121.7407),
        Place(name: "Shields Library", address: "100 NW Quad, UC Davis", latitude: 38.5397, longitude: -121.7495),
        Place(name: "Mondavi Center", address: "1 Shields Ave, Davis, CA", latitude: 38.5347, longitude: -121.7489),
        Place(name: "Golden 1 Center", address: "500 David J Stern Walk, Sacramento", latitude: 38.5802, longitude: -121.4997)
    ]
}

struct CreateActivityView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let draft: ActivityDraft?
    @State private var draftID = UUID()
    @State private var restoredDraft = false
    @State private var repeats = false
    @State private var frequency: EventRecurrence.Frequency = .weekly
    @State private var occurrenceCount = 6
    @State private var recurrenceTimeZoneID = TimeZone.current.identifier
    @State private var schedulePost = false
    @State private var publishAt = Date.now.addingTimeInterval(3600)
    @State private var showExitSheet = false
    @State private var exitChoice: PlanExitChoice?
    /// The form as it was when the sheet opened (defaults, or the draft being edited).
    @State private var baseline: PlanFormSnapshot?

    init(draft: ActivityDraft? = nil) {
        self.draft = draft
    }

    @State private var category: ActivityCategory = .social
    @State private var title = ""
    @State private var date = Calendar.current.date(byAdding: .hour, value: 3, to: .now)!.roundedToHalfHour
    @State private var duration = 90
    @State private var place: Place?
    @State private var capacity = 4
    @State private var level: ActivityLevel = .anyone
    @State private var requiresApproval = false
    @State private var privateLocation = false
    /// Free or paid. When paid, `cost` holds what the host typed after the "$" (e.g. "12" or "5 members").
    @State private var costIsFree = true
    @State private var cost = ""
    @State private var details = ""
    /// Optional: "@club" or an instagram.com link.
    @State private var instagram = ""
    @State private var showPlacePicker = false
    @State private var flyerPhoto: PhotosPickerItem?
    @State private var flyerData: Data?
    @State private var capturedFlyerData: Data?
    @State private var scanResult: FlyerScanResult?
    /// A flyer that couldn't be read, kept so the host can try it again.
    @State private var failedScan: FailedScan?
    /// "Describe your plan": what the host typed, and the text being read right now.
    @State private var planDescription = ""
    @State private var describedText: String?
    @State private var voiceSession: UUID?
    @State private var voiceCapture: PlanVoiceCapture?
    @State private var voiceTranscript = ""
    @State private var voiceError: String?
    @State private var scanning = false
    @State private var showCamera = false
    @State private var scannedLocation = ""
    @State private var reviewedLocation: FlyerLocation?
    @State private var pendingFlyerCover: UIImage?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var coverPhotoData: Data?
    @State private var cropSource: CropSource?
    @State private var photoError: String?
    @State private var isLoadingPhoto = false
    @State private var published = false
    @FocusState private var focus: Field?

    enum Field { case title, details, cost, instagram, planDescription }

    /// The Duration picker's options, in minutes.
    static let durations = [30, 45, 60, 90, 120, 180, 240, 480]

    static func durationOptions(including selected: Int) -> [Int] {
        durations.contains(selected) ? durations : (durations + [selected]).sorted()
    }

    private var formSnapshot: PlanFormSnapshot {
        PlanFormSnapshot(
            category: category, title: title, date: date, duration: duration, placeID: place?.id,
            suggestedLocation: scannedLocation, capacity: capacity, level: level,
            requiresApproval: requiresApproval, privateLocation: privateLocation,
            costIsFree: costIsFree, cost: cost, details: details, coverPhotoData: coverPhotoData,
            repeats: repeats, frequency: frequency, occurrenceCount: occurrenceCount,
            schedulePost: schedulePost, publishAt: publishAt, instagram: instagram
        )
    }

    /// X or a swipe down. A plan with barely anything in it just closes; real work asks first.
    /// A draft that's already saved is never deleted here: closing it unchanged just closes.
    private func attemptClose() {
        focus = nil
        let now = formSnapshot
        let start = baseline ?? now
        if draft != nil {
            if now == start { dismiss() } else { showExitSheet = true }
        } else if DraftEligibility.isWorthSaving(now, comparedTo: start) {
            showExitSheet = true
        } else {
            dismiss()
        }
    }

    private var canPublish: Bool {
        !scanning && !isLoadingPhoto && missing.isEmpty
    }

    /// What still stops the plan from posting, in the order the form asks for it.
    private var missing: [String] {
        var items: [String] = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { items.append("a title") }
        if date <= .now { items.append("a time in the future") }
        if place == nil { items.append("a location") }
        if !costIsFree && cost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { items.append("a price") }
        if !InstagramHandle.isAcceptable(instagram) { items.append("a valid Instagram handle") }
        if schedulePost && !(publishAt > .now && publishAt < date) { items.append("a publish time before the plan") }
        return items
    }

    private var costText: String { PlanCost.text(isFree: costIsFree, amount: cost) }

    /// Loads a saved or scanned cost into the Free / Paid controls.
    private func setCost(_ text: String) {
        (costIsFree, cost) = PlanCost.parse(text)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    flyerSection
                    categorySection
                    titleSection
                    whenSection
                    whereSection
                    detailsSection
                    groupSection
                    preview
                    moreOptionsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .onDisappear { stopVoiceCapture() }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Host a plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { attemptClose() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if !missing.isEmpty && focus == nil {
                        Text("Add \(missing.formatted(.list(type: .and))) to post.")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .glassEffect(.regular, in: Capsule())
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    Button(action: publish) {
                        Label(schedulePost ? "Schedule post" : "Post plan", systemImage: schedulePost ? "clock" : "paperplane.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: AnyShapeStyle(category.gradient)))
                    .disabled(!canPublish)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .background {
                    LinearGradient(stops: [.init(color: Color(.systemGroupedBackground).opacity(0), location: 0),
                                           .init(color: Color(.systemGroupedBackground), location: 0.35)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                .animation(.snappy, value: missing)
            }
            .onAppear {
                defer { if baseline == nil { baseline = formSnapshot } }
                guard !restoredDraft, let draft else { return }
                restoredDraft = true
                draftID = draft.id
                category = draft.category
                title = draft.title
                date = draft.date
                duration = draft.duration
                place = draft.place
                capacity = draft.capacity
                level = draft.level
                requiresApproval = draft.requiresApproval
                privateLocation = draft.privateLocation == true
                setCost(draft.cost)
                details = draft.details
                instagram = draft.instagram ?? ""
                coverPhotoData = draft.coverPhotoData
                reviewedLocation = draft.reviewedFlyerLocation
                scannedLocation = reviewedLocation?.query ?? draft.suggestedLocation ?? ""
                repeats = draft.recurrence != nil
                frequency = draft.recurrence?.frequency ?? .weekly
                occurrenceCount = draft.recurrence?.count ?? 6
                recurrenceTimeZoneID = draft.recurrence?.timeZoneID ?? TimeZone.current.identifier
                schedulePost = draft.scheduledAt != nil
                publishAt = draft.scheduledAt ?? .now.addingTimeInterval(3600)
            }
            .onDismissAttempt { attemptClose() }
            .sheet(isPresented: $showExitSheet, onDismiss: {
                // Act once the small sheet is gone, so closing the form doesn't race it.
                let choice = exitChoice
                exitChoice = nil
                switch choice {
                case .save: saveDraftAndClose()
                case .discard: dismiss()
                case .keepEditing, nil: break
                }
            }) {
                PlanExitSheet(isExistingDraft: draft != nil,
                              pausesSchedule: schedulePost,
                              canSave: !isLoadingPhoto && !scanning) { choice in
                    exitChoice = choice
                    showExitSheet = false
                }
            }
            .sheet(isPresented: $showPlacePicker) {
                PlacePickerView(selection: Binding(get: { place }, set: { match in
                    place = match.map { reviewedLocation?.pinned(to: $0) ?? $0 }
                    reviewedLocation = nil
                    scannedLocation = ""
                }), initialQuery: scannedLocation)
            }
            .sheet(item: $cropSource, onDismiss: { selectedPhoto = nil }) { source in
                CoverPhotoCropView(image: source.image) { data in
                    coverPhotoData = data
                }
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: {
                flyerData = capturedFlyerData
                capturedFlyerData = nil
            }) {
                FlyerCameraView { data in capturedFlyerData = data }
                    .ignoresSafeArea()
            }
            .sheet(item: $scanResult, onDismiss: {
                flyerPhoto = nil
                flyerData = nil
                describedText = nil
                if let image = pendingFlyerCover {
                    cropSource = CropSource(image: image)
                    pendingFlyerCover = nil
                }
            }) { result in
                FlyerReviewView(result: result) { fields in
                    title = fields.title
                    date = fields.date
                    place = fields.place
                    reviewedLocation = fields.place == nil ? fields.location : nil
                    scannedLocation = reviewedLocation?.query ?? ""
                    if !fields.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { details = fields.details }
                    if !fields.cost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { setCost(fields.cost) }
                    if let scanned = fields.category { category = scanned }
                    if let minutes = fields.duration { duration = minutes }
                    if !fields.instagram.isEmpty { instagram = fields.instagram }
                    pendingFlyerCover = fields.cover
                }
            }
            .task(id: flyerPhoto) {
                guard let flyerPhoto else { return }
                scanning = true
                do {
                    guard let data = try await flyerPhoto.loadTransferable(type: Data.self) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    try Task.checkCancellation()
                    flyerData = data
                } catch is CancellationError {
                    scanning = false
                } catch {
                    scanning = false
                    self.flyerPhoto = nil
                    photoError = "The flyer could not be opened. Please choose another image."
                }
            }
            .task(id: flyerData) {
                guard let flyerData else { return }
                scanning = true
                defer { scanning = false }
                do {
                    let result = try await FlyerScanner.scan(flyerData, serverURL: store.serverURL)
                    try Task.checkCancellation()
                    scanResult = result
                } catch is CancellationError {
                    return
                } catch {
                    flyerPhoto = nil
                    self.flyerData = nil
                    failedScan = FailedScan(data: flyerData, error: error)
                }
            }
            .task(id: describedText) {
                // "Describe your plan": the same review screen as a scanned flyer.
                guard let describedText else { return }
                scanning = true
                defer { scanning = false }
                do {
                    let result = try await FlyerScanner.read(text: describedText, serverURL: store.serverURL)
                    try Task.checkCancellation()
                    scanResult = result
                } catch {
                    self.describedText = nil
                }
            }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                isLoadingPhoto = true
                defer { isLoadingPhoto = false }
                do {
                    guard let data = try await selectedPhoto.loadTransferable(type: Data.self),
                          let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: 2400
                          ] as CFDictionary) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    try Task.checkCancellation()
                    cropSource = CropSource(image: UIImage(cgImage: thumbnail))
                } catch is CancellationError {
                    return
                } catch {
                    photoError = "This photo could not be opened. Please choose another image."
                }
            }
            // A failed scan never leaves an unexplained empty form: say why, and offer a retry or typing it in.
            .alert("Couldn't read this flyer", isPresented: Binding(
                get: { failedScan != nil },
                set: { if !$0 { failedScan = nil } }
            ), presenting: failedScan) { failed in
                Button("Try Again") {
                    failedScan = nil
                    flyerData = failed.data
                }
                Button("Enter Manually") {
                    failedScan = nil
                    focus = .title
                }
                Button("Cancel", role: .cancel) { failedScan = nil }
            } message: { failed in
                Text(failed.message)
            }
            .alert("Unable to complete action", isPresented: Binding(
                get: { photoError != nil },
                set: { if !$0 { photoError = nil } }
            )) {
                Button("OK") { photoError = nil }
            } message: {
                Text(photoError ?? "")
            }
            .sensoryFeedback(.success, trigger: published)
        }
        .interactiveDismissDisabled()
    }

    // MARK: Preview

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("Cover & preview")
            ZStack(alignment: .bottomLeading) {
                ActivityCover(category: category, photoData: coverPhotoData)
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    // Shown, not edited: the title is typed once, in "Plan title" above.
                    Text(title.isEmpty ? "Your plan title" : title)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                        .opacity(title.isEmpty ? 0.6 : 1)
                    Text("\(date.friendlyDateTime)\(place.map { " · \($0.name)" } ?? "") · \(costText)")
                        .font(.subheadline.weight(.medium))
                        .opacity(0.9)
                }
                .foregroundStyle(.white)
                .padding(18)
            }
            .frame(height: CoverShape.isPoster(coverPhotoData) ? 460 : 180)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(alignment: .topTrailing) { coverButton.padding(12) }
            .overlay {
                if isLoadingPhoto {
                    ProgressView().tint(.white)
                }
            }
            .animation(.smooth, value: coverPhotoData)
            .animation(.smooth, value: category)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Preview of your plan")
        }
    }

    /// Add, replace or remove the cover, right on the preview.
    @ViewBuilder private var coverButton: some View {
        Group {
            if coverPhotoData == nil {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Add cover photo", systemImage: "photo.badge.plus")
                }
            } else {
                Menu {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Replace photo", systemImage: "photo.on.rectangle")
                    }
                    Button("Remove photo", systemImage: "trash", role: .destructive) {
                        coverPhotoData = nil
                        selectedPhoto = nil
                    }
                } label: {
                    Label("Edit cover", systemImage: "photo")
                }
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: Capsule())
        .disabled(isLoadingPhoto || scanning)
    }

    // MARK: Sections

    private var flyerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("Autofill plan details")
            Text("Scan a flyer, type a sentence or say it, and we'll fill in the form.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                PhotosPicker(selection: $flyerPhoto, matching: .images) {
                    Label("Upload flyer", systemImage: "doc.viewfinder")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                Button {
                    Task {
                        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                            photoError = "A camera is unavailable on this device. Use Upload flyer to choose an image."
                            return
                        }
                        let allowed = await AVCaptureDevice.requestAccess(for: .video)
                        if allowed {
                            showCamera = true
                        } else {
                            photoError = "Camera access is off. Enable it in Settings to take a flyer photo, or use Upload flyer."
                        }
                    }
                } label: {
                    Label("Take flyer photo", systemImage: "camera")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .buttonStyle(.bordered)
            .tint(Brand.accent)
            .disabled(voiceSession != nil)

            HStack(alignment: .bottom, spacing: 10) {
            TextField(voiceCapture == nil ? "Or describe it, e.g. free soccer Saturday at 3 at the ARC" : "Listening…",
                      text: $planDescription, axis: .vertical)
                .lineLimit(2...5)
                .focused($focus, equals: .planDescription)
                // Return means "Go": the floating Post plan bar covers the button below while the
                // keyboard is up. Depending on the keyboard, iOS sends Return as a submit or types a newline.
                .submitLabel(.go)
                .onSubmit(fillFromDescription)
                .onChange(of: planDescription) { old, new in
                    guard new.hasSuffix("\n"), new.count == old.count + 1 else { return }
                    planDescription = String(new.dropLast())
                    fillFromDescription()
                }
                .accessibilityIdentifier("planDescription")
                .disabled(voiceSession != nil)
                // One button, like Messages: a mic when empty, send when there's text, stop while listening.
                describeButton
            }
            .padding(16)
            .cardStyle(radius: 18)

            if let voiceError {
                Text(voiceError).font(.caption).foregroundStyle(.secondary)
            }

            if scanning {
                ProgressView(describedText != nil
                             ? (store.serverURL == nil ? "Reading your description…" : "Reading your description with Claude…")
                             : (store.serverURL == nil ? "Reading flyer…" : "Reading flyer with Claude…"))
            }
        }
        .disabled(scanning || isLoadingPhoto)
    }

    @ViewBuilder private var describeButton: some View {
        let hasText = !planDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if voiceCapture != nil {
            Button("Stop and autofill", systemImage: "stop.circle.fill", action: finishVoiceCapture)
                .labelStyle(.iconOnly)
                .font(.title)
                .foregroundStyle(.red)
                .symbolEffect(.pulse, isActive: true)
        } else if hasText {
            Button("Autofill from text", systemImage: "arrow.up.circle.fill", action: fillFromDescription)
                .labelStyle(.iconOnly)
                .font(.title)
                .foregroundStyle(Brand.accent)
                .disabled(voiceSession != nil)
        } else {
            Button("Speak your plan", systemImage: "mic.circle.fill", action: startVoiceCapture)
                .labelStyle(.iconOnly)
                .font(.title)
                .foregroundStyle(Brand.accent)
                .disabled(voiceSession != nil)
        }
    }

    private func startVoiceCapture() {
        let session = UUID()
        voiceSession = session
        voiceError = nil
        voiceTranscript = ""
        focus = nil

        Task { @MainActor in
            let authorization: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard voiceSession == session else { return }
            guard authorization == .authorized,
                  await AVAudioApplication.requestRecordPermission() else {
                stopVoiceCapture()
                voiceError = "Allow speech recognition and microphone access in Settings."
                return
            }
            guard voiceSession == session else { return }

            do {
                let capture = try await PlanVoiceCapture.start { transcript, finished, failure in
                    guard voiceSession == session else { return }
                    if let transcript, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        voiceTranscript = transcript
                        planDescription = transcript
                    }
                    if let failure, voiceTranscript.isEmpty {
                        stopVoiceCapture()
                        voiceError = "Speech recognition couldn’t start: \(failure)"
                    } else if finished, voiceTranscript.isEmpty {
                        stopVoiceCapture()
                        voiceError = "Speech recognition ended before returning any words. Try the keyboard microphone or type your plan."
                        focus = .planDescription
                    } else if finished {
                        finishVoiceCapture()
                    }
                }
                guard voiceSession == session else {
                    capture.stop()
                    return
                }
                voiceCapture = capture
            } catch {
                guard voiceSession == session else { return }
                stopVoiceCapture()
                voiceError = "Couldn’t start voice input: \(error.localizedDescription)"
            }
        }
    }

    private func finishVoiceCapture() {
        stopVoiceCapture()
        guard !voiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            voiceError = "No speech was recognized. Try again or type your plan."
            return
        }
        planDescription = voiceTranscript
        fillFromDescription()
    }

    private func stopVoiceCapture() {
        voiceSession = nil
        voiceCapture?.stop()
        voiceCapture = nil
    }

    /// Opens the same review screen for typed and spoken descriptions.
    private func fillFromDescription() {
        let text = planDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !scanning, describedText == nil, voiceSession == nil else { return }
        focus = nil
        describedText = String(text.prefix(ClaudeTextReader.maxCharacters))
    }

    private var moreOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("More options")
            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: $repeats.animation(.snappy)) {
                    Label("Repeat", systemImage: "repeat")
                }
                .padding(14)
                if repeats {
                    Divider().padding(.leading, 14)
                    Picker("Every", selection: $frequency) {
                        ForEach(EventRecurrence.Frequency.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    Divider().padding(.leading, 14)
                    Stepper("\(occurrenceCount) events", value: $occurrenceCount, in: 2...12)
                        .padding(14)
                    if let last = currentDraft().occurrenceDates.last {
                        Text("Last one \(last.formatted(date: .abbreviated, time: .shortened)). All dates post together as separate events.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14).padding(.bottom, 12)
                    }
                }
                Divider().padding(.leading, 14)
                Toggle(isOn: $schedulePost.animation(.snappy)) {
                    Label("Schedule for later", systemImage: "clock")
                }
                .padding(14)
                if schedulePost {
                    Divider().padding(.leading, 14)
                    DatePicker("Post on", selection: $publishAt, in: Date.now...)
                        .padding(14)
                    Text("Pick a time before the plan starts. The app must be open to post it; missed ones go back to drafts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14).padding(.bottom, 12)
                }
            }
            .cardStyle(radius: 18)
            .tint(category.color)

            Button("Save draft and close", systemImage: "square.and.arrow.down") {
                saveDraftAndClose()
            }
            .font(.subheadline.weight(.semibold))
            .disabled(isLoadingPhoto || scanning)
        }
    }

    private func currentDraft(scheduledAt: Date? = nil) -> ActivityDraft {
        ActivityDraft(
            id: draftID, category: category, title: title, date: date,
            duration: duration, place: place, capacity: capacity, level: level,
            requiresApproval: requiresApproval || privateLocation,
            privateLocation: privateLocation ? true : nil, cost: costText, details: details,
            coverPhotoData: coverPhotoData, scheduledAt: scheduledAt,
            recurrence: repeats ? EventRecurrence(frequency: frequency, count: occurrenceCount,
                                                  timeZoneID: recurrenceTimeZoneID) : nil,
            suggestedLocation: scannedLocation.isEmpty ? nil : scannedLocation,
            reviewedFlyerLocation: reviewedLocation,
            instagram: instagram.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : instagram,
            updatedAt: .now
        )
    }

    private func saveDraftAndClose() {
        guard store.saveDraft(currentDraft()) else {
            photoError = "Your draft could not be saved. Please try again."
            return
        }
        dismiss()
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("Category")
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(ActivityCategory.allCases) { cat in
                        Button {
                            withAnimation(.snappy) { category = cat }
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: cat.symbol)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(category == cat ? .white : cat.color)
                                    .frame(width: 58, height: 58)
                                    .background {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(category == cat ? AnyShapeStyle(cat.gradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
                                    }
                                Text(cat.title)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(category == cat ? .primary : .secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(minHeight: 34, alignment: .top)
                            }
                            .frame(width: 76)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, -20)
            .scrollIndicators(.hidden)
            .sensoryFeedback(.selection, trigger: category)
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("Plan title")
            TextField("e.g. \(suggestions.first ?? "Sunday morning run")", text: $title)
                .font(.title3.weight(.medium))
                .focused($focus, equals: .title)
                .submitLabel(.done)
                .padding(16)
                .cardStyle(radius: 18)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { s in
                        Button(s) { title = s }
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(category.color.opacity(0.12), in: Capsule())
                            .foregroundStyle(category.color)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("Date & time")
            HStack(spacing: 8) {
                quickTime("Tonight", hour: 19, dayOffset: 0)
                quickTime("Tomorrow AM", hour: 8, dayOffset: 1)
                quickTime("This weekend", hour: 10, dayOffset: daysUntilSaturday)
            }
            VStack(spacing: 0) {
                DatePicker("Starts", selection: $date, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                    .padding(14)
                Divider().padding(.leading, 14)
                Picker("Duration", selection: $duration) {
                    ForEach(Self.durationOptions(including: duration), id: \.self) { m in
                        Text(m < 60 ? "\(m) min" : m % 60 == 0 ? "\(m / 60) hr" : "\(m / 60)h \(m % 60)m").tag(m)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .cardStyle(radius: 18)
        }
    }

    private var whereSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("Location")
            if !scannedLocation.isEmpty && place == nil {
                Text("From the scan: \(scannedLocation). Choose a map match below.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button { showPlacePicker = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: place == nil ? "mappin.and.ellipse" : "mappin.circle.fill")
                        .font(.title2)
                        .foregroundStyle(category.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place?.name ?? "Choose a place").font(.body.weight(.semibold)).foregroundStyle(.primary)
                        Text(place?.address ?? "Search or pick a popular spot").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(16)
                .cardStyle(radius: 18)
            }
            .buttonStyle(PressableStyle())

            Toggle(isOn: $privateLocation.animation(.snappy)) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Keep location private", systemImage: "eye.slash.fill")
                    Text("Only people you accept see where it is").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .cardStyle(radius: 18)
            .tint(category.color)
        }
    }

    private var groupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("Attendance & cost")
            VStack(spacing: 0) {
                HStack {
                    Label("Group size", systemImage: "person.2.fill")
                    Spacer()
                    Text("\(capacity) people")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(capacity)))
                    // Clubs can be big: 1 at a time up to 20, then 5s, then 25s.
                    Stepper("Group size", value: $capacity.animation(.snappy), in: 2...500,
                            step: capacity < 20 ? 1 : capacity < 100 ? 5 : 25).labelsHidden()
                }
                .padding(14)
                Divider().padding(.leading, 14)
                Picker(selection: $level) {
                    ForEach(ActivityLevel.allCases) { Text($0.rawValue).tag($0) }
                } label: {
                    Label("Level", systemImage: "chart.bar.fill")
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                Divider().padding(.leading, 14)
                Toggle(isOn: privateLocation ? .constant(true) : $requiresApproval) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Approve requests", systemImage: "hand.raised.fill")
                        if privateLocation {
                            Text("Required for private locations")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(privateLocation)
                .padding(14)
                Divider().padding(.leading, 14)
                HStack {
                    Label("Cost", systemImage: "creditcard.fill")
                    Spacer()
                    Picker("Cost", selection: $costIsFree.animation(.snappy)) {
                        Text("Free").tag(true)
                        Text("Paid").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .onChange(of: costIsFree) { _, free in
                        // Paid: straight to the price, keyboard up. Free: nothing to type.
                        focus = free ? nil : .cost
                    }
                }
                .padding(14)
                if !costIsFree {
                    HStack(spacing: 4) {
                        Text("$")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("0", text: $cost)
                            .font(.title3.weight(.semibold))
                            .keyboardType(.decimalPad)
                            .focused($focus, equals: .cost)
                            .accessibilityLabel("Price in dollars")
                        Text("per person")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .cardStyle(radius: 18)
            .tint(category.color)
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("Details")
            TextField("What should people know or bring?", text: $details, axis: .vertical)
                .lineLimit(4...8)
                .focused($focus, equals: .details)
                .padding(16)
                .cardStyle(radius: 18)
            instagramField
        }
    }

    /// Optional. Guests see it as a link on the event that opens Instagram.
    private var instagramField: some View {
        let valid = InstagramHandle.isAcceptable(instagram)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "camera.circle.fill")
                    .font(.title3)
                    .foregroundStyle(category.color)
                    .accessibilityHidden(true)
                TextField("Instagram (optional), e.g. @ucdavis", text: $instagram)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($focus, equals: .instagram)
                    .accessibilityLabel("Instagram handle or link, optional")
            }
            .padding(16)
            .cardStyle(radius: 18)
            .overlay {
                if !valid {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.red, lineWidth: 1.5)
                }
            }
            if !valid {
                Text("Enter a handle like @ucdavis or an instagram.com profile link.")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let handle = InstagramHandle.normalize(instagram), focus != .instagram {
                Text("Guests will see @\(handle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Helpers

    private func label(_ text: String) -> some View {
        Text(text).font(.headline)
    }

    private func quickTime(_ text: String, hour: Int, dayOffset: Int) -> some View {
        Button(text) {
            let cal = Calendar.current
            let base = cal.date(byAdding: .day, value: dayOffset, to: .now)!
            var d = cal.date(bySettingHour: hour, minute: 0, second: 0, of: base)!
            if d < .now { d = cal.date(byAdding: .day, value: 1, to: d)! }
            withAnimation(.snappy) { date = d }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .foregroundStyle(.primary)
    }

    private var daysUntilSaturday: Int {
        let weekday = Calendar.current.component(.weekday, from: .now) // 1 = Sunday
        return (7 - weekday + 7) % 7
    }

    private var suggestions: [String] {
        switch category {
        case .sports: ["Open practice", "Intro scrimmage", "Tryout info night"]
        case .outdoors: ["Weekend hike", "Group bike ride", "Camping trip planning"]
        case .wellness: ["Sunset yoga", "Mindfulness session", "Gym buddy meetup"]
        case .cultural: ["Culture night", "Language exchange", "Heritage potluck"]
        case .arts: ["Film screening", "Improv workshop", "Gallery night"]
        case .music: ["Open mic", "Jam session", "Choir rehearsal"]
        case .academic: ["Midterm study group", "Tutoring hours", "Research panel"]
        case .career: ["Resume review", "Networking mixer", "Mock interviews"]
        case .tech: ["Hackathon team mixer", "Coding workshop", "Project demo night"]
        case .service: ["Volunteer shift", "Campus cleanup", "Fundraiser"]
        case .greek: ["Recruitment open house", "Philanthropy event", "Meet the chapter"]
        case .faith: ["Weekly fellowship", "Interfaith dinner", "Meditation circle"]
        case .gaming: ["Smash tournament", "Board game night", "Esports watch party"]
        case .social: ["General meeting", "Welcome mixer", "Club potluck"]
        }
    }

    private func publish() {
        guard canPublish else { return }
        let draft = currentDraft(scheduledAt: schedulePost ? publishAt : nil)
        let saved = schedulePost ? store.saveDraft(draft) : store.publishDraft(draft)
        guard saved else {
            photoError = "Your post could not be saved. Please try again."
            return
        }
        published = true
        store.show(InAppBanner(
            title: schedulePost ? "Your post is scheduled" : (repeats ? "Your event series is live!" : "Your plan is live!"),
            subtitle: schedulePost ? "Manage it in Plans → Hosting → Scheduled."
                : store.isGuest ? "Saved on this iPhone. Sign in to share it with other students."
                : "People can now find your plan.",
            symbol: schedulePost ? "clock" : category.symbol, color: category.color
        ))
        dismiss()
    }
}

extension Date {
    var roundedToHalfHour: Date {
        let cal = Calendar.current
        let minute = cal.component(.minute, from: self)
        let add = minute < 30 ? 30 - minute : 60 - minute
        return cal.date(byAdding: .minute, value: add, to: self)!.addingTimeInterval(-Double(cal.component(.second, from: self)))
    }
}

// MARK: - Place picker

struct PlacePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Place?
    @State private var query: String
    @State private var results: [Place] = []
    @State private var isSearching = false

    init(selection: Binding<Place?>, initialQuery: String = "") {
        _selection = selection
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section("Popular near you") {
                        ForEach(Place.presets) { row($0) }
                    }
                } else if isSearching && results.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if results.isEmpty {
                    Section {
                        Button {
                            choose(Place(name: query, address: "Davis, CA", latitude: Geo.home.latitude, longitude: Geo.home.longitude))
                        } label: {
                            Label("Use “\(query)”", systemImage: "plus.circle.fill")
                        }
                    } footer: {
                        Text("No matches found — you can still use this as a custom place.")
                    }
                } else {
                    Section("Results") {
                        ForEach(results) { row($0) }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search places")
            .task(id: query) { await search() }
            .navigationTitle("Choose a place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private func row(_ place: Place) -> some View {
        Button { choose(place) } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill").font(.title2).foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).foregroundStyle(.primary)
                    Text(place.address).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if selection?.id == place.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }

    private func choose(_ place: Place) {
        selection = place
        dismiss()
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; return }
        isSearching = true
        defer { isSearching = false }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let found = await Place.search(q)
        guard !Task.isCancelled else { return }
        results = found
    }
}


/// Rule-of-thirds lines and a white border over the crop area.
private struct CropGrid: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            Path { path in
                for i in 1...2 {
                    path.move(to: CGPoint(x: w * CGFloat(i) / 3, y: 0))
                    path.addLine(to: CGPoint(x: w * CGFloat(i) / 3, y: h))
                    path.move(to: CGPoint(x: 0, y: h * CGFloat(i) / 3))
                    path.addLine(to: CGPoint(x: w, y: h * CGFloat(i) / 3))
                }
            }
            .stroke(.white.opacity(0.35), lineWidth: 0.5)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white, lineWidth: 2)
        }
    }
}

private struct CropSource: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct CoverPhotoCropView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let onCrop: (Data) -> Void
    @State private var shape: CoverShape
    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var cropSize = CGSize(width: 16, height: 9)
    @State private var cropError = false

    init(image: UIImage, onCrop: @escaping (Data) -> Void) {
        self.image = image
        self.onCrop = onCrop
        // Flyers and other tall photos start as a poster, so only a sliver of the sides is trimmed.
        _shape = State(initialValue: image.size.height > image.size.width ? .poster : .wide)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let size = frameSize(in: geometry.size)
                ZStack {
                    Color.black
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: image.size.width * scale(for: size),
                               height: image.size.height * scale(for: size))
                        .offset(offset)
                    // The rest of the photo stays visible, dimmed, like cropping in Photos.
                    Rectangle()
                        .fill(.black.opacity(0.6))
                        .mask {
                            Rectangle().overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .frame(width: size.width, height: size.height)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                        }
                        .allowsHitTesting(false)
                    CropGrid()
                        .frame(width: size.width, height: size.height)
                        .allowsHitTesting(false)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = clamped(CGSize(width: dragStart.width + value.translation.width,
                                                    height: dragStart.height + value.translation.height), in: size)
                        }
                        .onEnded { _ in dragStart = offset }
                        .simultaneously(with: MagnifyGesture()
                            .onChanged { value in
                                zoom = min(4, max(1, zoomStart * value.magnification))
                                offset = clamped(offset, in: size)
                            }
                            .onEnded { _ in
                                zoomStart = zoom
                                dragStart = offset
                            })
                )
                .overlay(alignment: .bottom) {
                    VStack(spacing: 14) {
                        Picker("Shape", selection: $shape.animation(.snappy)) {
                            ForEach(CoverShape.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 280)
                        Text("Drag and pinch to frame your cover")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                        HStack {
                            Image(systemName: "minus.magnifyingglass")
                            Slider(value: $zoom, in: 1...4)
                                .accessibilityLabel("Photo zoom")
                                .onChange(of: zoom) {
                                    zoomStart = zoom
                                    offset = clamped(offset, in: size)
                                    dragStart = offset
                                }
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .foregroundStyle(.white)
                        .tint(.white)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Cover photo crop, \(shape.title)")
                .onAppear { cropSize = size }
                .onChange(of: geometry.size) { cropSize = frameSize(in: geometry.size) }
                .onChange(of: shape) {
                    cropSize = frameSize(in: geometry.size)
                    zoom = 1
                    zoomStart = 1
                    offset = .zero
                    dragStart = .zero
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .background(Color.black)
            .navigationTitle("Cover photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use photo") { crop(size: cropSize) }
                        .fontWeight(.semibold)
                }
            }
            .alert("Could not save photo", isPresented: $cropError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please try choosing another photo.")
            }
        }
    }

    /// The crop frame: full width for wide covers; for posters, as tall as fits above the controls.
    private func frameSize(in space: CGSize) -> CGSize {
        let width = max(1, space.width - 24)
        switch shape {
        case .wide:
            return CGSize(width: width, height: width * 9 / 16)
        case .poster:
            let height = max(1, min(space.height - 2 * 150, width * 4 / 3))
            return CGSize(width: height * 3 / 4, height: height)
        }
    }

    private func scale(for size: CGSize) -> CGFloat {
        max(size.width / image.size.width, size.height / image.size.height) * zoom
    }

    private func clamped(_ proposed: CGSize, in size: CGSize) -> CGSize {
        let scale = scale(for: size)
        let horizontal = max(0, (image.size.width * scale - size.width) / 2)
        let vertical = max(0, (image.size.height * scale - size.height) / 2)
        return CGSize(width: min(horizontal, max(-horizontal, proposed.width)),
                      height: min(vertical, max(-vertical, proposed.height)))
    }

    private func crop(size: CGSize) {
        let output = shape.output
        let factor = output.width / size.width
        let scale = scale(for: size) * factor
        let position = clamped(offset, in: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let cropped = UIGraphicsImageRenderer(size: output, format: format).image { _ in
            image.draw(in: CGRect(
                x: (output.width - image.size.width * scale) / 2 + position.width * factor,
                y: (output.height - image.size.height * scale) / 2 + position.height * factor,
                width: image.size.width * scale,
                height: image.size.height * scale
            ))
        }
        guard let data = cropped.jpegData(compressionQuality: 0.8) else {
            cropError = true
            return
        }
        onCrop(data)
        dismiss()
    }
}

/// The two cover shapes: wide for photos, a 3:4 poster for flyers.
enum CoverShape: CaseIterable {
    case wide, poster

    var title: String { self == .wide ? "Wide 16:9" : "Poster 3:4" }
    var output: CGSize { self == .wide ? CGSize(width: 1600, height: 900) : CGSize(width: 1200, height: 1600) }

    /// Whether a saved cover is a poster (taller than wide). Reads only the image header.
    static func isPoster(_ data: Data?) -> Bool {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
        // EXIF orientations 5–8 are rotated 90°.
        let rotated = ((properties[kCGImagePropertyOrientation] as? Int) ?? 1) >= 5
        return rotated ? width > height : height > width
    }
}


private final class PlanVoiceCapture: @unchecked Sendable {
    // The queue serializes audio engine and session changes off the UI thread.
    private static let audioQueue = DispatchQueue(label: "Swipe-n-Go.plan-voice")
    private let engine = AVAudioEngine()
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private let recognizer: SFSpeechRecognizer
    private var task: SFSpeechRecognitionTask?

    private enum CaptureError: Error { case unavailable }

    static func start(update: @escaping @MainActor @Sendable (String?, Bool, String?) -> Void) async throws -> PlanVoiceCapture {
        try await withCheckedThrowingContinuation { continuation in
            audioQueue.async {
                continuation.resume(with: Result { try PlanVoiceCapture(update: update) })
            }
        }
    }

    private init(update: @escaping @MainActor @Sendable (String?, Bool, String?) -> Void) throws {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw CaptureError.unavailable
        }
        self.recognizer = recognizer
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement)
        try audioSession.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            try? audioSession.setActive(false)
            throw CaptureError.unavailable
        }
        let request = request
        request.shouldReportPartialResults = true
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        do {
            try engine.start()
        } catch {
            tearDown()
            throw error
        }
        task = recognizer.recognitionTask(with: request) { result, error in
            let transcript = result?.bestTranscription.formattedString
            let finished = result?.isFinal == true || error != nil
            let failure = error.map { error in
                let underlying = error as NSError
                return "\(underlying.localizedDescription) (\(underlying.domain) \(underlying.code))"
            }
            Task { @MainActor in update(transcript, finished, failure) }
        }
    }

    func stop() {
        Self.audioQueue.async { self.tearDown() }
    }

    private func tearDown() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request.endAudio()
        task?.cancel()
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// The Host form's Free / Paid cost, as the text saved on the plan ("Free", "$12", "~$20").
enum PlanCost {
    /// "Free", or the amount with a "$" in front when it starts with a number.
    static func text(isFree: Bool, amount: String) -> String {
        let amount = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFree || amount.isEmpty { return "Free" }
        return amount.first?.isNumber == true ? "$" + amount : amount
    }

    /// Splits a saved or scanned cost ("Free", "$12", "Free w/ ARC", "~$20") into free or the amount typed.
    static func parse(_ text: String) -> (isFree: Bool, amount: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased().hasPrefix("free") { return (true, "") }
        return (false, trimmed.hasPrefix("$") ? String(trimmed.dropFirst()) : trimmed)
    }
}

// MARK: - Leaving the form

/// Every field of the Host form that the host can change, to tell real input from defaults.
struct PlanFormSnapshot: Equatable {
    var category: ActivityCategory
    var title: String
    var date: Date
    var duration: Int
    var placeID: String?
    var suggestedLocation: String
    var capacity: Int
    var level: ActivityLevel
    var requiresApproval: Bool
    var privateLocation: Bool
    var costIsFree: Bool
    var cost: String
    var details: String
    var coverPhotoData: Data?
    var repeats: Bool
    var frequency: EventRecurrence.Frequency
    var occurrenceCount: Int
    var schedulePost: Bool
    var publishAt: Date
    var instagram: String = ""
}

/// Decides whether closing a new plan offers "Save as Draft" or just throws it away.
/// Each change from the defaults earns points; at `threshold` the plan is worth keeping.
/// Tune the numbers here; nothing else in the app hard-codes them.
///
/// | Input                                   | Points |
/// |-----------------------------------------|--------|
/// | Description of 25+ characters, 4+ words | 3      |
/// | Shorter description                     | 1      |
/// | Location picked (or read from a flyer)  | 2      |
/// | Cover photo                             | 2      |
/// | Title of 3+ characters                  | 1      |
/// | Category changed                        | 1      |
/// | Date or time changed                    | 1      |
/// | Other settings changed (each)           | 1, at most 2 in all |
///
/// So a title, a category, or both, is not enough; a real description is; a location with a
/// time, or a photo with a title, is.
enum DraftEligibility {
    static let threshold = 3
    static let meaningfulDescriptionLength = 25
    static let meaningfulDescriptionWords = 4
    static let maxSettingsPoints = 2

    static func isWorthSaving(_ form: PlanFormSnapshot, comparedTo start: PlanFormSnapshot) -> Bool {
        score(form, comparedTo: start) >= threshold
    }

    static func score(_ form: PlanFormSnapshot, comparedTo start: PlanFormSnapshot) -> Int {
        var points = 0

        let details = trimmed(form.details)
        if details != trimmed(start.details), !details.isEmpty {
            let words = details.split(whereSeparator: { $0.isWhitespace }).count
            points += details.count >= meaningfulDescriptionLength && words >= meaningfulDescriptionWords ? 3 : 1
        }

        let hasPlace = form.placeID != nil || !trimmed(form.suggestedLocation).isEmpty
        if hasPlace, form.placeID != start.placeID || form.suggestedLocation != start.suggestedLocation {
            points += 2
        }
        if form.coverPhotoData != nil, form.coverPhotoData != start.coverPhotoData { points += 2 }

        let title = trimmed(form.title)
        if title.count >= 3, title != trimmed(start.title) { points += 1 }
        if form.category != start.category { points += 1 }
        if form.date != start.date { points += 1 }

        let settings = [
            form.duration != start.duration,
            form.capacity != start.capacity,
            form.level != start.level,
            form.requiresApproval != start.requiresApproval,
            form.privateLocation != start.privateLocation,
            !form.costIsFree && !trimmed(form.cost).isEmpty,
            form.repeats != start.repeats,
            form.schedulePost != start.schedulePost
        ].filter { $0 }.count
        points += min(settings, maxSettingsPoints)

        return points
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A flyer scan that failed, and what to tell the host.
struct FailedScan: Equatable {
    let data: Data
    let message: String

    init(data: Data, error: Error) {
        self.data = data
        if let error = error as? CocoaError, error.code == .fileReadCorruptFile {
            message = "This image couldn't be opened. Try another photo, or enter the details yourself."
        } else if error is URLError || error is EventServer.ServerError {
            message = "The connection dropped while reading it. Try again, or enter the details yourself."
        } else {
            message = "No event details were found. The photo may be blurry or not a flyer. Try a clearer photo, or enter the details yourself."
        }
    }
}

enum PlanExitChoice { case save, discard, keepEditing }

/// The bottom sheet shown when closing a plan worth keeping: save, discard, or keep going.
private struct PlanExitSheet: View {
    let isExistingDraft: Bool
    let pausesSchedule: Bool
    let canSave: Bool
    let choose: (PlanExitChoice) -> Void
    @State private var height: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(isExistingDraft ? "Save your changes?" : "Save this plan as a draft?")
                    .font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            .padding(.top, 30)
            .padding(.bottom, 18)

            VStack(spacing: 0) {
                Divider()
                row(isExistingDraft ? "Save Changes" : "Save as Draft", symbol: "square.and.arrow.down", choice: .save)
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.4)
                Divider().padding(.leading, 60)
                row(isExistingDraft ? "Discard Changes" : "Discard Post", symbol: "trash", choice: .discard, role: .destructive)
                Divider().padding(.leading, 60)
                row("Continue Editing", symbol: "pencil", choice: .keepEditing)
            }
            .padding(.bottom, 8)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
    }

    private var message: String {
        if isExistingDraft {
            return "Discarding keeps the draft as it was last saved."
        }
        return pausesSchedule
            ? "Find it in Plans → Host → Drafts. Scheduled publishing is paused until you schedule it again."
            : "Find it in Plans → Host → Drafts and pick up where you left off."
    }

    private func row(_ title: String, symbol: String, choice: PlanExitChoice, role: ButtonRole? = nil) -> some View {
        Button(role: role) { choose(choice) } label: {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 28)
                Text(title)
                    .font(.body.weight(choice == .keepEditing ? .regular : .semibold))
                Spacer()
            }
            .foregroundStyle(role == .destructive ? Color.red : Color.primary)
            .padding(.horizontal, 20)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
