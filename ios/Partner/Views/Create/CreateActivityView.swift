import SwiftUI
import MapKit
import PhotosUI
import ImageIO

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
    @State private var schedulePost = false
    @State private var publishAt = Date.now.addingTimeInterval(3600)
    @State private var showCloseOptions = false

    init(draft: ActivityDraft? = nil) {
        self.draft = draft
    }

    @State private var category: ActivityCategory = .run
    @State private var title = ""
    @State private var date = Calendar.current.date(byAdding: .hour, value: 3, to: .now)!.roundedToHalfHour
    @State private var duration = 90
    @State private var place: Place?
    @State private var capacity = 4
    @State private var level: ActivityLevel = .anyone
    @State private var requiresApproval = false
    @State private var cost = "Free"
    @State private var details = ""
    @State private var showPlacePicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var coverPhotoData: Data?
    @State private var cropSource: CropSource?
    @State private var photoError: String?
    @State private var isLoadingPhoto = false
    @State private var published = false
    @FocusState private var focus: Field?

    enum Field { case title, details, cost }

    private var canPublish: Bool {
        !isLoadingPhoto && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && place != nil && date > .now
            && (!schedulePost || (publishAt > .now && publishAt < date))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    preview
                    coverPhotoSection
                    categorySection
                    titleSection
                    whenSection
                    whereSection
                    groupSection
                    detailsSection
                    publishingSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Host a plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { showCloseOptions = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(schedulePost ? "Schedule" : "Post", systemImage: "checkmark") { publish() }
                        .disabled(!canPublish)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: publish) {
                    Label(schedulePost ? "Schedule post" : "Post plan", systemImage: schedulePost ? "clock" : "paperplane.fill")
                }
                .buttonStyle(PrimaryButtonStyle(tint: AnyShapeStyle(category.gradient)))
                .disabled(!canPublish)
                .padding(.horizontal, 20)
                .padding(.top, 8)
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
                cost = draft.cost
                details = draft.details
                coverPhotoData = draft.coverPhotoData
                schedulePost = draft.scheduledAt != nil
                publishAt = draft.scheduledAt ?? .now.addingTimeInterval(3600)
            }
            .confirmationDialog("Keep this post?", isPresented: $showCloseOptions, titleVisibility: .visible) {
                Button("Save draft and close") { saveDraftAndClose() }
                    .disabled(isLoadingPhoto)
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("Saving as a draft pauses any scheduled publishing until you schedule it again.")
            }
            .sheet(isPresented: $showPlacePicker) {
                PlacePickerView(selection: $place)
            }
            .sheet(item: $cropSource, onDismiss: { selectedPhoto = nil }) { source in
                CoverPhotoCropView(image: source.image) { data in
                    coverPhotoData = data
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
        ZStack(alignment: .bottomLeading) {
            ActivityCover(category: category, photoData: coverPhotoData)
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Text(title.isEmpty ? "Your plan title" : title)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                    .opacity(title.isEmpty ? 0.6 : 1)
                Text("\(date.friendlyDateTime)\(place.map { " · \($0.name)" } ?? "")")
                    .font(.subheadline.weight(.medium))
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
            .padding(18)
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .animation(.smooth, value: category)
        .padding(.top, 8)
    }

    // MARK: Sections

    private var publishingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("Publishing")
            Toggle("Schedule for later", isOn: $schedulePost)
            if schedulePost {
                DatePicker("Publish on", selection: $publishAt, in: Date.now...)
                Text("Choose a publishing time before the event starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Posts publish on this device while the app is open, or when you reopen it. If the event has already started, the post returns to drafts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Save draft and close", systemImage: "square.and.arrow.down") {
                saveDraftAndClose()
            }
            .disabled(isLoadingPhoto)
        }
    }

    private func currentDraft(scheduledAt: Date? = nil) -> ActivityDraft {
        ActivityDraft(
            id: draftID, category: category, title: title, date: date,
            duration: duration, place: place, capacity: capacity, level: level,
            requiresApproval: requiresApproval, cost: cost, details: details,
            coverPhotoData: coverPhotoData, scheduledAt: scheduledAt, updatedAt: .now
        )
    }

    private func saveDraftAndClose() {
        guard store.saveDraft(currentDraft()) else {
            photoError = "Your draft could not be saved. Please try again."
            return
        }
        dismiss()
    }

    private var coverPhotoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("Cover photo")
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label(coverPhotoData == nil ? "Choose a photo" : "Replace photo",
                      systemImage: "photo.on.rectangle")
            }
            .disabled(isLoadingPhoto)
            if isLoadingPhoto {
                ProgressView("Loading photo")
            }
            if coverPhotoData != nil {
                Button("Remove photo", role: .destructive) {
                    coverPhotoData = nil
                    selectedPhoto = nil
                }
            }
            Text("Choose a photo, then drag and zoom to crop it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("What kind of plan?")
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
                                    .lineLimit(1)
                            }
                            .frame(width: 70)
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
            label("Give it a name")
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
            label("When?")
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
                    ForEach([30, 45, 60, 90, 120, 180, 240, 480], id: \.self) { m in
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
            label("Where?")
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
        }
    }

    private var groupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("Who can come?")
            VStack(spacing: 0) {
                HStack {
                    Label("Group size", systemImage: "person.2.fill")
                    Spacer()
                    Text("\(capacity) people")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(capacity)))
                    Stepper("Group size", value: $capacity.animation(.snappy), in: 2...30).labelsHidden()
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
                Toggle(isOn: $requiresApproval) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Approve requests", systemImage: "hand.raised.fill")
                        Text("Review people before they join").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                Divider().padding(.leading, 14)
                HStack {
                    Label("Cost", systemImage: "creditcard.fill")
                    TextField("Free", text: $cost)
                        .multilineTextAlignment(.trailing)
                        .focused($focus, equals: .cost)
                }
                .padding(14)
            }
            .cardStyle(radius: 18)
            .tint(category.color)
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("Details")
            TextField("What's the vibe? What should people bring?", text: $details, axis: .vertical)
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
        case .run: ["Easy morning 5K", "Sunset run", "Track intervals"]
        case .gym: ["Push day partner", "Leg day spotter", "Morning lift"]
        case .hike: ["Weekend hike", "Sunrise summit", "Trail day trip"]
        case .cycling: ["Coffee ride", "Bike loop tour", "Long ride Sunday"]
        case .sports: ["Pickup basketball", "Tennis doubles", "Spikeball in the park"]
        case .yoga: ["Park yoga flow", "Sunrise stretch", "Beginner yoga"]
        case .food: ["Try a new restaurant", "Ramen night", "Brunch crew"]
        case .coffee: ["Coffee & chat", "Café hopping", "Study + latte"]
        case .drinks: ["Happy hour", "Trivia night", "Rooftop drinks"]
        case .concert: ["Concert buddy needed", "Live jazz night", "Open mic"]
        case .movies: ["Movie night", "Opening night!", "Indie film screening"]
        case .art: ["Museum day", "Gallery walk", "Sketch in the park"]
        case .study: ["Library grind", "Midterm prep", "Silent study session"]
        case .games: ["Board game night", "Smash tournament", "Poker night"]
        case .explore: ["Day trip", "Farmers market stroll", "Explore a new town"]
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
            title: schedulePost ? "Your post is scheduled" : "Your plan is live!",
            subtitle: schedulePost ? "Manage it in Plans → Scheduled." : "People can now find your plan.",
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
    @State private var query = ""
    @State private var results: [Place] = []
    @State private var isSearching = false

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

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        request.region = MKCoordinateRegion(center: Geo.home, span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6))
        let local = Place.presets.filter { $0.name.localizedCaseInsensitiveContains(q) }
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            let found = response.mapItems.prefix(12).map { item in
                Place(name: item.name ?? q,
                      address: item.address?.shortAddress ?? item.address?.fullAddress ?? "",
                      latitude: item.location.coordinate.latitude,
                      longitude: item.location.coordinate.longitude)
            }
            results = local + found
        } catch {
            results = local
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
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var cropError = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let width = max(1, geometry.size.width - 40)
                let size = CGSize(width: width, height: width * 9 / 16)
                VStack(spacing: 24) {
                    Spacer()
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: image.size.width * scale(for: size),
                               height: image.size.height * scale(for: size))
                        .offset(offset)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .overlay(Rectangle().stroke(.white, lineWidth: 2))
                        .contentShape(Rectangle())
                        .gesture(DragGesture()
                            .onChanged { value in
                                offset = clamped(CGSize(
                                    width: dragStart.width + value.translation.width,
                                    height: dragStart.height + value.translation.height
                                ), in: size)
                            }
                            .onEnded { _ in dragStart = offset })
                        .accessibilityLabel("Cover photo crop preview")
                    Text("Drag to position your photo")
                        .foregroundStyle(.secondary)
                    HStack {
                        Image(systemName: "minus.magnifyingglass")
                        Slider(value: $zoom, in: 1...4)
                            .accessibilityLabel("Photo zoom")
                            .onChange(of: zoom) {
                                offset = clamped(offset, in: size)
                                dragStart = offset
                            }
                        Image(systemName: "plus.magnifyingglass")
                    }
                    Spacer()
                    Button("Use photo") { crop(size: size) }
                        .buttonStyle(.borderedProminent)
                }
                .padding(20)
            }
            .navigationTitle("Crop cover photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Could not save photo", isPresented: $cropError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please try choosing another photo.")
            }
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
        let output = CGSize(width: 1600, height: 900)
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
