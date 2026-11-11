import Foundation

/// The planner that runs entirely on the phone: reads the request with keywords,
/// then finds and ranks events. It's the fallback when Claude isn't reachable,
/// so it has to give sensible answers on its own.
enum OnDevicePlanner {
    static func plan(_ text: String, activities: [Activity], context: PlannerContext,
                     now: Date = .now, fallbackReason: String? = nil) -> PlanResult {
        let request = KeywordParser.parse(text, now: now)
        let pool = context.candidates(from: activities, now: now)
        let (picked, note) = pick(from: pool, for: request, context: context, now: now)
        let picks = picked.map {
            PlanPick(activity: $0, reason: reason(for: $0, request: request, interests: context.interests,
                                                  showsDistance: context.canSeeLocation($0)))
        }
        return PlanResult(understood: describe(request, now: now), picks: picks, note: note,
                          engine: .onDevice, fallbackReason: fallbackReason)
    }

    // MARK: Matching

    /// Exact matches first; if there are none, widen step by step so there's always something to show.
    static func pick(from pool: [Activity], for r: PlanRequest, context: PlannerContext,
                     now: Date) -> ([Activity], String?) {
        let cal = Calendar.current
        let dayStart = max(cal.startOfDay(for: r.start), now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: r.end.addingTimeInterval(-1)))!
        let week = cal.date(byAdding: .day, value: 7, to: now)!

        let attempts: [(categories: Bool, extras: Bool, start: Date, end: Date, note: String?)] = [
            (true, true, r.start, r.end, nil),
            (true, false, r.start, r.end, "Nothing matched every detail, so here's the closest fit for that time."),
            (false, false, r.start, r.end, "Nothing of that kind then, but here's what else fits your time."),
            (true, false, dayStart, dayEnd, "Nothing in that exact window. Here's the rest of that day."),
            (false, false, now, week, "Nothing fits that time. Here's what's coming up this week."),
        ]
        for attempt in attempts {
            let found = pool.filter { a in
                guard a.date >= attempt.start, a.date < attempt.end else { return false }
                if attempt.categories, !r.categories.isEmpty, !r.categories.contains(a.category) { return false }
                if attempt.extras, r.cheap, !isCheap(a) { return false }
                if attempt.extras, r.beginnerFriendly, ![.anyone, .beginner].contains(a.level) { return false }
                return true
            }
            if !found.isEmpty {
                let ranked = found.sorted { score($0, r, context) > score($1, r, context) }
                return (Array(ranked.prefix(5)), attempt.note)
            }
        }
        return ([], nil)
    }

    static func score(_ a: Activity, _ r: PlanRequest, _ context: PlannerContext) -> Double {
        var s = 0.0
        if r.categories.contains(a.category) { s += 4 }
        if context.interests.contains(a.category) { s += 2 }
        if r.cheap, isCheap(a) { s += 1.5 }
        if r.beginnerFriendly, [.anyone, .beginner].contains(a.level) { s += 1.5 }
        if r.wantsCompany { s += min(Double(a.attendeeIDs.count), 3) * 0.5 + (a.requiresApproval ? 0 : 0.5) }
        // Closer is better; a hidden place counts as middling, so it neither helps nor gives itself away.
        s -= (context.canSeeLocation(a) ? min(Geo.miles(to: a.coordinate), 30) : 5) * 0.05
        s -= a.date.timeIntervalSince(r.start) / 86_400 * 0.3      // sooner is better
        return s
    }

    static func isCheap(_ a: Activity) -> Bool {
        let cost = a.costNote.lowercased()
        if cost.contains("free") { return true }
        let numbers = cost.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return (numbers.max() ?? 0) <= 10
    }

    // MARK: Wording

    static func reason(for a: Activity, request: PlanRequest, interests: [ActivityCategory],
                       showsDistance: Bool = true) -> String {
        var parts: [String] = []
        if interests.contains(a.category) {
            parts.append("You're into \(a.category.title.lowercased())")
        } else if request.categories.contains(a.category) {
            let askedForActive = Set(ActivityCategory.active).isSubset(of: Set(request.categories))
            parts.append(askedForActive ? "Gets you moving" : "\(a.category.title) like you asked")
        }
        parts.append("starts \(a.date.friendlyTime)")
        if request.beginnerFriendly, [.anyone, .beginner].contains(a.level) { parts.append("beginner friendly") }
        if request.wantsCompany, !a.attendeeIDs.isEmpty { parts.append("\(a.attendeeIDs.count + 1) people already going") }
        if isCheap(a) { parts.append(a.costNote.lowercased() == "free" ? "free" : "cheap") }
        if showsDistance { parts.append("\(Geo.distanceText(to: a.coordinate)) away") }
        let sentence = parts.prefix(4).joined(separator: ", ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst() + "."
    }

    /// The pill at the top of the results, e.g. "Tomorrow after 5:00 PM · something active · meet people".
    static func describe(_ r: PlanRequest, now: Date) -> String {
        let cal = Calendar.current
        let span = r.end.timeIntervalSince(r.start)
        let startsNow = abs(r.start.timeIntervalSince(now)) < 120
        let endsAtMidnight = cal.component(.hour, from: r.end) == 0 && cal.component(.minute, from: r.end) == 0
        let when: String
        if span > 86_400 * 2.5 {
            when = "This week"
        } else if span > 86_400 {
            when = "This weekend"
        } else if startsNow {
            when = endsAtMidnight ? "Rest of today" : "Now until \(r.end.friendlyTime)"
        } else if endsAtMidnight {
            when = "\(r.start.friendlyDay) after \(r.start.friendlyTime)"
        } else {
            when = "\(r.start.friendlyDay) \(r.start.friendlyTime)–\(r.end.friendlyTime)"
        }
        var parts = [when]
        if r.categories.isEmpty {
            parts.append("anything fun")
        } else if Set(ActivityCategory.active).isSubset(of: Set(r.categories)) {
            parts.append("something active")
        } else {
            parts.append(r.categories.prefix(2).map { $0.title.lowercased() }.joined(separator: " or "))
        }
        if r.beginnerFriendly { parts.append("beginner-friendly") }
        if r.cheap { parts.append("free or cheap") }
        if r.wantsCompany { parts.append("meet people") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Reading the request

enum KeywordParser {
    private static let categoryWords: [(ActivityCategory, [String])] = [
        (.run, ["run", "running", "jog", "jogging", "5k", "10k"]),
        (.gym, ["gym", "lift", "lifting", "workout", "weights"]),
        (.hike, ["hike", "hiking", "trail", "trails", "nature"]),
        (.cycling, ["bike", "biking", "cycling", "ride"]),
        (.sports, ["sport", "sports", "basketball", "soccer", "tennis", "volleyball", "pickup"]),
        (.yoga, ["yoga", "stretch", "pilates"]),
        (.food, ["food", "eat", "dinner", "lunch", "brunch", "tacos", "restaurant"]),
        (.coffee, ["coffee", "cafe", "café", "boba", "matcha"]),
        (.drinks, ["drinks", "bar", "beer", "karaoke"]),
        (.concert, ["concert", "music", "show", "gig", "band", "live"]),
        (.movies, ["movie", "movies", "film", "cinema"]),
        (.art, ["art", "museum", "gallery", "paint", "painting"]),
        (.study, ["study", "library", "homework", "studying"]),
        (.games, ["game", "games", "board", "trivia", "gaming"]),
        (.explore, ["explore", "trip", "market", "adventure"]),
    ]
    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    static func parse(_ text: String, now: Date) -> PlanRequest {
        let t = " " + text.lowercased() + " "
        let words = Set(t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let cal = Calendar.current

        var dayOffset: Int?
        var weekend = false
        if words.contains("today") || words.contains("tonight") { dayOffset = 0 }
        if words.contains("tomorrow") { dayOffset = 1 }
        if words.contains("weekend") { weekend = true }
        if let name = weekdays.first(where: { words.contains($0) }) {
            let target = weekdays.firstIndex(of: name)! + 1
            dayOffset = (target - cal.component(.weekday, from: now) + 7) % 7
        }

        var fromHour: Int?
        var toHour: Int?
        if words.contains("morning") { (fromHour, toHour) = (6, 12) }
        if words.contains("afternoon") { (fromHour, toHour) = (12, 17) }
        if words.contains("evening") || words.contains("tonight") { (fromHour, toHour) = (17, 24) }
        if let hour = hour(after: "after", in: t) {
            fromHour = hour
            if let to = toHour, to <= hour { toHour = nil }
        }
        if let hour = hour(after: "before", in: t) ?? hour(after: "until", in: t) { toHour = hour }

        var categories = categoryWords
            .filter { _, keys in keys.contains { words.contains($0) } }
            .map(\.0)
        if ["active", "exercise", "sweat", "fitness", "move", "moving"].contains(where: { words.contains($0) }) {
            categories += ActivityCategory.active
        }

        // "I'm free tomorrow" means available, so only cost words count as asking for cheap.
        let cheap = ["cheap", "broke", "budget", "inexpensive"].contains { words.contains($0) }
            || ["for free", "free event", "free stuff", "free things", "no money", "low cost", "not expensive"].contains { t.contains($0) }
        let beginner = ["beginner", "never", "new", "first", "nervous", "start", "starting", "learn"].contains { words.contains($0) }
        let company = ["alone", "anyone", "nobody", "myself", "buddy", "friends", "people", "company", "lonely"].contains { words.contains($0) }

        let (start, end) = window(dayOffset: dayOffset, weekend: weekend, fromHour: fromHour, toHour: toHour, now: now)
        var unique: [ActivityCategory] = []
        for c in categories where !unique.contains(c) { unique.append(c) }
        return PlanRequest(start: start, end: end, categories: unique, cheap: cheap,
                           beginnerFriendly: beginner, wantsCompany: company)
    }

    static func window(dayOffset: Int?, weekend: Bool, fromHour: Int?, toHour: Int?, now: Date) -> (Date, Date) {
        let cal = Calendar.current
        var dayStart: Date
        var dayCount = 1
        if weekend {
            let weekday = cal.component(.weekday, from: now)              // 1 = Sunday, 7 = Saturday
            let toSaturday = weekday == 1 ? -1 : (7 - weekday)
            dayStart = cal.startOfDay(for: cal.date(byAdding: .day, value: toSaturday, to: now)!)
            dayCount = 2
        } else if let dayOffset {
            dayStart = cal.startOfDay(for: cal.date(byAdding: .day, value: dayOffset, to: now)!)
        } else if fromHour != nil || toHour != nil {
            // A time but no day: today, or tomorrow if that time is already over.
            dayStart = cal.startOfDay(for: now)
            if cal.component(.hour, from: now) >= (toHour ?? 24) - 1 {
                dayStart = cal.date(byAdding: .day, value: 1, to: dayStart)!
            }
        } else {
            dayStart = cal.startOfDay(for: now)
            dayCount = 7
        }
        let from = fromHour.map { min(max($0, 0), 23) } ?? 0
        let to = toHour.flatMap { $0 > from ? min($0, 24) : nil } ?? 24
        let lastDay = cal.date(byAdding: .day, value: dayCount - 1, to: dayStart)!
        let start = max(cal.date(byAdding: .hour, value: from, to: dayStart)!, now)
        let end = cal.date(byAdding: .hour, value: to, to: lastDay)!
        return (start, max(end, start))
    }

    /// "after 5", "after 5pm", "after 17:00" → 17
    private static func hour(after keyword: String, in text: String) -> Int? {
        guard let match = text.firstMatch(of: try! Regex(keyword + #"\s+(\d{1,2})(?::\d{2})?\s*(am|pm)?"#)),
              let hourText = match.output[1].substring, var hour = Int(hourText), hour <= 24 else { return nil }
        let suffix = match.output[2].substring.map(String.init)
        if suffix == "pm", hour < 12 { hour += 12 }
        if suffix == nil, (1...7).contains(hour) { hour += 12 }     // "after 5" means 5 PM
        return hour
    }
}
