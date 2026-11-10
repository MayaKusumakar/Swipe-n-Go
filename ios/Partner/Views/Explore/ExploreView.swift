import SwiftUI
import MapKit

struct ExploreView: View {
    @Environment(AppStore.self) private var store
    @State private var mode: Mode = .map
    @State private var query = ""
    @State private var category: ActivityCategory?
    @State private var selection: UUID?
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(center: Geo.home,
                                                                              span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
    @State private var path = NavigationPath()

    enum Mode: String, CaseIterable { case map = "Map", list = "List" }

    private var results: [Activity] {
        store.feedActivities
            .filter { !$0.isPast }
            .filter { category == nil || $0.category == category }
            .filter { a in
                guard !query.isEmpty else { return true }
                let q = query.lowercased()
                return a.title.lowercased().contains(q) || a.placeName.lowercased().contains(q)
                    || a.category.title.lowercased().contains(q) || a.tags.contains { $0.lowercased().contains(q) }
            }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch mode {
                case .map: mapView
                case .list: listView
                }
            }
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Runs, concerts, tacos…")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: $mode.animation(.snappy)) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
            .profileToolbarButton()
            .navigationDestination(for: Activity.self) { ActivityDetailView(activity: $0) }
        }
    }

    // MARK: Chips

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ActivityCategory.allCases) { cat in
                    CategoryChip(category: cat, isSelected: category == cat) {
                        withAnimation(.snappy) { category = category == cat ? nil : cat; selection = nil }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Map

    private var mapView: some View {
        Map(position: $camera, selection: $selection) {
            Annotation("You", coordinate: Geo.home) {
                ZStack {
                    Circle().fill(.blue.opacity(0.2)).frame(width: 34, height: 34)
                    Circle().fill(.blue).frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                }
            }
            .annotationTitles(.hidden)

            ForEach(results) { a in
                Annotation(a.title, coordinate: a.coordinate, anchor: .bottom) {
                    MapPin(activity: a, isSelected: selection == a.id)
                }
                .tag(a.id)
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .top) { chips }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.smooth) {
                            camera = .region(MKCoordinateRegion(center: Geo.home, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
                        }
                    } label: {
                        Image(systemName: "location.fill").font(.headline).frame(width: 46, height: 46)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Recenter")
                    Button {
                        withAnimation(.smooth) {
                            camera = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 38.62, longitude: -121.55),
                                                                span: MKCoordinateSpan(latitudeDelta: 0.6, longitudeDelta: 0.6)))
                        }
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.headline).frame(width: 46, height: 46)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Zoom out to region")
                }
                .padding(.horizontal, 16)

                if let id = selection, let a = store.activity(id) {
                    Button { path.append(a) } label: {
                        ActivityRow(activity: a, style: .floating)
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(a.id)
                } else {
                    Text("\(results.count) plans nearby")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .glassEffect(.regular, in: Capsule())
                        .transition(.opacity)
                }
            }
            .padding(.bottom, 8)
            .animation(.spring(duration: 0.35, bounce: 0.2), value: selection)
        }
        .onChange(of: selection) { _, new in
            if let new, let a = store.activity(new) {
                withAnimation(.smooth) {
                    camera = .region(MKCoordinateRegion(center: a.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)))
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    // MARK: List

    private var grouped: [(String, [Activity])] {
        let groups = Dictionary(grouping: results) { Calendar.current.startOfDay(for: $0.date) }
        return groups.keys.sorted().map { ($0.friendlyDay, groups[$0]!) }
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12, pinnedViews: .sectionHeaders) {
                chips.padding(.horizontal, -16)
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .padding(.top, 60)
                }
                ForEach(grouped, id: \.0) { day, items in
                    Section {
                        ForEach(items) { a in
                            NavigationLink(value: a) { ActivityRow(activity: a) }
                                .buttonStyle(PressableStyle())
                        }
                    } header: {
                        Text(day)
                            .font(.headline)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGroupedBackground))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await store.syncWithServer() }
    }
}

// MARK: - Map pin

private struct MapPin: View {
    let activity: Activity
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: activity.category.symbol)
                .font(.system(size: isSelected ? 20 : 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: isSelected ? 48 : 36, height: isSelected ? 48 : 36)
                .background(activity.category.gradient, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            Triangle()
                .fill(.white)
                .frame(width: 10, height: 6)
                .offset(y: -1)
        }
        .animation(.spring(duration: 0.3, bounce: 0.5), value: isSelected)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

// MARK: - Activity row (shared)

struct ActivityRow: View {
    @Environment(AppStore.self) private var store
    let activity: Activity
    var style: Style = .card

    enum Style { case card, floating }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                ActivityCover(category: activity.category, photoData: activity.coverPhotoData)
                Image(systemName: activity.category.symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(activity.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Label(activity.date.friendlyDateTime, systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    AvatarStack(people: store.attendees(of: activity), size: 22, max: 3)
                    Text("\(activity.placeName) · \(Geo.distanceText(to: activity.coordinate))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            status
        }
        .padding(12)
        .background {
            if style == .card {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.secondarySystemGroupedBackground))
            }
        }
        .modifier(FloatingGlass(enabled: style == .floating))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder private var status: some View {
        if store.isHost(activity) {
            badge("Hosting", "crown.fill", .orange)
        } else if store.isGoing(activity) {
            badge("Going", "checkmark", .green)
        } else if store.isPending(activity) {
            badge("Pending", "hourglass", .yellow)
        } else if activity.isFull {
            badge("Full", "person.fill.xmark", .gray)
        } else {
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
    }

    private func badge(_ text: String, _ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(color.gradient, in: Circle())
            .accessibilityLabel(text)
    }
}

private struct FloatingGlass: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            content
        }
    }
}
