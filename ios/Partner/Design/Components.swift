import SwiftUI

// MARK: - Brand

enum Brand {
    static let accent = Color(red: 1.0, green: 0.36, blue: 0.29)
    static let accent2 = Color(red: 1.0, green: 0.62, blue: 0.20)
    static let gradient = LinearGradient(colors: [Color(red: 1.0, green: 0.30, blue: 0.40), Color(red: 1.0, green: 0.60, blue: 0.22)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Avatar

struct AvatarView: View {
    let person: Person?
    var size: CGFloat = 44
    var showsRing = false

    var body: some View {
        ZStack {
            Circle().fill(person?.avatarGradient ?? LinearGradient(colors: [.gray, .secondary], startPoint: .top, endPoint: .bottom))
            if let person, !person.emoji.isEmpty {
                Text(person.emoji).font(.system(size: size * 0.48))
            } else {
                Text(person?.initials ?? "?")
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if showsRing { Circle().strokeBorder(.background, lineWidth: max(2, size * 0.05)) }
        }
        .accessibilityLabel(person?.name ?? "Unknown")
    }
}

struct AvatarStack: View {
    let people: [Person]
    var size: CGFloat = 28
    var max: Int = 4

    var body: some View {
        HStack(spacing: -size * 0.32) {
            ForEach(people.prefix(max)) { p in
                AvatarView(person: p, size: size, showsRing: true)
            }
            if people.count > max {
                Text("+\(people.count - max)")
                    .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                    .frame(width: size, height: size)
                    .background(.thinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.background, lineWidth: 2))
            }
        }
    }
}

// MARK: - Category visuals

struct CategoryIcon: View {
    let category: ActivityCategory
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(category.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct CategoryChip: View {
    let category: ActivityCategory
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(category.title, systemImage: category.symbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .foregroundStyle(isSelected ? .white : .primary)
                .background {
                    Capsule().fill(isSelected ? AnyShapeStyle(category.gradient) : AnyShapeStyle(.thinMaterial))
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .animation(.snappy, value: isSelected)
    }
}

struct TagPill: View {
    let text: String
    var tint: Color = .secondary
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

/// Animated mesh backdrop in a category's palette — used as the "photo" on cards.
struct CategoryBackdrop: View {
    let category: ActivityCategory
    var animated = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animated)) { context in
            let time = Float(context.date.timeIntervalSinceReferenceDate)
            let s = animated ? sin(time * 0.6) * 0.12 : 0
            let c = animated ? cos(time * 0.5) * 0.12 : 0
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5 + s, 0.45 + c], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1]
                ],
                colors: category.meshColors
            )
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: category.symbol)
                .font(.system(size: 170, weight: .bold))
                .foregroundStyle(.white.opacity(0.16))
                .rotationEffect(.degrees(-12))
                .offset(x: 40, y: 30)
        }
        .clipped()
    }
}

// MARK: - Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        for (i, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > maxWidth, !row.indices.isEmpty {
                let y = row.y + row.height + spacing
                rows.append(Row(indices: [i], y: y, width: size.width, height: size.height))
                continue
            }
            row.indices.append(i)
            row.width = needed
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var tint: AnyShapeStyle = AnyShapeStyle(Brand.gradient)
    var foreground: Color = .white
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(isEnabled ? tint : AnyShapeStyle(Color.gray.opacity(0.4)), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Banner

struct BannerView: View {
    let banner: InAppBanner

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: banner.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(banner.color.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title).font(.subheadline.weight(.semibold))
                Text(banner.subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 12)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.bold))
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Info row

struct InfoRow: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.weight(.medium))
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
    }
}

extension View {
    func cardStyle(radius: CGFloat = 24) -> some View {
        self
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}


/// Shared cover rendering for published plans and the posting preview.
struct ActivityCover: View {
    let category: ActivityCategory
    let photoData: Data?

    var body: some View {
        GeometryReader { geometry in
            if let photoData, let photo = UIImage(data: photoData) {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                CategoryBackdrop(category: category)
            }
        }
    }
}

// MARK: - Profile button (top-right of every tab)

struct ProfileButton: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Button { store.showProfile = true } label: {
            AvatarView(person: store.me, size: 34)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Profile")
    }
}

extension View {
    /// Adds the profile avatar to the top-right of a tab's navigation bar.
    func profileToolbarButton() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
                .sharedBackgroundVisibility(.hidden)
        }
    }
}
