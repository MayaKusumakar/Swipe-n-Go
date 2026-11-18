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
    @State private var showCloseOptions = false

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
    @State private var showPlacePicker = false
    @State private var flyerPhoto: PhotosPickerItem?
    @State private var flyerData: Data?
    @State private var capturedFlyerData: Data?
    @State private var scanResult: FlyerScanResult?
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
    @State private var findingPlace = false
    /// The place was matched from the flyer's text, so the host should glance at it.
    @State private var placeFromFlyer = false
    @State private var pendingFlyerCover: UIImage?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var coverPhotoData: Data?
    @State private var cropSource: CropSource?
    @State private var photoError: String?
    @State private var isLoadingPhoto = false
    @State private var published = false
    @FocusState private var focus: Field?

    enum Field { case title, details, cost, planDescription }

    /// The Duration picker's options, in minutes.
    static let durations = [30, 45, 60, 90, 120, 180, 240, 480]

    /// Something worth keeping: swiping the sheet down asks before throwing it away.
    private var hasChanges: Bool {
        draft != nil || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || place != nil || coverPhotoData != nil || !scannedLocation.isEmpty
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
                    Button("Close", systemImage: "xmark") { showCloseOptions = true }
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
                coverPhotoData = draft.coverPhotoData
                scannedLocation = draft.suggestedLocation ?? ""
                if place == nil, !scannedLocation.isEmpty { Task { await findScannedPlace() } }
                repeats = draft.recurrence != nil
                frequency = draft.recurrence?.frequency ?? .weekly
                occurrenceCount = draft.recurrence?.count ?? 6
                recurrenceTimeZoneID = draft.recurrence?.timeZoneID ?? TimeZone.current.identifier
                schedulePost = draft.scheduledAt != nil
                publishAt = draft.scheduledAt ?? .now.addingTimeInterval(3600)
            }
            .interactiveDismissDisabled(hasChanges)
            .onDismissAttempt { showCloseOptions = true }
            .confirmationDialog("Keep this post?", isPresented: $showCloseOptions, titleVisibility: .visible) {
                Button("Save draft and close") { saveDraftAndClose() }
                    .disabled(isLoadingPhoto || scanning)
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("Saving as a draft pauses any scheduled publishing until you schedule it again.")
            }
            .sheet(isPresented: $showPlacePicker) {
                PlacePickerView(selection: $place, initialQuery: scannedLocation)
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
                    // The location is entered once, in the review. Use the place picked there,
                    // or look the text up on the map; never ask for it again.
                    if let picked = fields.place {
                        place = picked
                        scannedLocation = ""
                        placeFromFlyer = false
                    } else {
                        scannedLocation = fields.location
                        place = nil
                        Task { await findScannedPlace() }
                    }
                    details = fields.details
                    setCost(fields.cost)
                    if let scanned = fields.category { category = scanned }
                    if let end = fields.endDate {
                        // Closest option in the Duration picker.
                        let minutes = Int(end.timeIntervalSince(fields.date) / 60)
                        duration = Self.durations.min { abs($0 - minutes) < abs($1 - minutes) } ?? duration
                    }
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
                    photoError = "No readable flyer text was found. Try a clearer photo or enter the details manually."
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
                    ForEach(Self.durations, id: \.self) { m in
                        Text(m < 60 ? "\(m) min" : m % 60 == 0 ? "\(m / 60) hr" : "\(m / 60)h \(m % 60)m").tag(m)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .cardStyle(radius: 18)
        }
    }

    /// Matches the flyer's location to a real place. If nothing matches, the place picker
    /// opens already searching for it.
    private func findScannedPlace() async {
        let query = scannedLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, place == nil else { return }
        findingPlace = true
        defer { findingPlace = false }
        if let match = await Place.search(query).first, place == nil {
            withAnimation(.snappy) { place = match }
            placeFromFlyer = true
        }
    }

    private var whereSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("Location")
            if findingPlace {
                Label("Finding “\(scannedLocation)” on the map…", systemImage: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if placeFromFlyer, let place {
                Label("Matched “\(scannedLocation)” to \(place.name). Tap it to choose a different spot.",
                      systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !scannedLocation.isEmpty && place == nil {
                Text("Couldn't find “\(scannedLocation)” on the map. Tap below to pick it; we've already searched for it.")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
            Button { placeFromFlyer = false; showPlacePicker = true } label: {
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
