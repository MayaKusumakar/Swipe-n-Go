import Foundation

/// Seed content so the prototype feels alive on first launch.
/// Everything is centered around Davis, CA.
enum SampleData {
    struct Seed {
        var people: [Person]
        var activities: [Activity]
        var conversations: [Conversation]
        var requests: [JoinRequest]
    }

    static func make(for me: Person) -> Seed {
        let people: [Person] = [
            p("Maya Chen", 21, "she/her", "Marathon in training 🏃‍♀️ Always down for a sunrise loop and a post-run bagel.", [.run, .coffee, .hike], 0.02, "🏃‍♀️", true, 4.9, 42),
            p("Jordan Patel", 23, "he/him", "Grad student, part-time DJ. Will drag you to every show in Sac.", [.concert, .drinks, .food], 0.75, "🎧", true, 4.8, 31),
            p("Sofia Ramirez", 20, "she/her", "Plant-based foodie hunting the best tacos in Yolo County 🌮", [.food, .coffee, .art], 0.92, "🌮", false, 4.7, 18),
            p("Liam O'Connor", 22, "he/him", "Lifting 5x a week. Looking for a spotter who won't flake.", [.gym, .sports, .run], 0.58, "💪", true, 4.9, 56),
            p("Aisha Bello", 24, "she/her", "Weekend hiker, weekday coder. Show me a trail I haven't done.", [.hike, .cycling, .explore], 0.38, "⛰️", true, 5.0, 64),
            p("Noah Kim", 19, "he/him", "Board games, Smash, and late-night ramen. Competitive but friendly.", [.games, .food, .movies], 0.65, "🎮", false, 4.6, 12),
            p("Emma Larsen", 21, "she/her", "Art history major. Museums, film photography and slow mornings.", [.art, .coffee, .movies], 0.85, "🎨", true, 4.8, 23),
            p("Diego Alvarez", 25, "he/him", "Road cyclist. 40 miles is a warm-up. Coffee stops are mandatory.", [.cycling, .coffee, .run], 0.12, "🚴", true, 4.9, 77),
            p("Priya Nair", 22, "she/her", "Finals season survivor. Study buddy with snacks + a Pomodoro timer.", [.study, .coffee, .yoga], 0.48, "📚", false, 4.7, 15),
            p("Ethan Brooks", 23, "he/him", "Pickup basketball, Kings games, and the occasional karaoke night.", [.sports, .drinks, .concert], 0.08, "🏀", true, 4.5, 29),
            p("Hana Sato", 20, "she/her", "Yoga in the park and matcha after. Calm vibes only 🍵", [.yoga, .coffee, .hike], 0.30, "🧘‍♀️", true, 4.9, 37),
            p("Marcus Green", 24, "he/him", "Movie buff with Letterboxd opinions. Popcorn is on me.", [.movies, .food, .games], 0.70, "🍿", false, 4.6, 20),
            p("Zoe Martin", 21, "she/her", "Spontaneous road-tripper. If it's an adventure, count me in.", [.explore, .hike, .concert], 0.55, "🚗", true, 4.8, 33),
            p("Omar Haddad", 22, "he/him", "Coffee snob + amateur barista. Let's find the best pour-over.", [.coffee, .study, .art], 0.15, "☕️", false, 4.7, 19)
        ]

        func person(_ first: String) -> UUID { people.first { $0.firstName == first }!.id }
        func at(days: Int, hour: Int, minute: Int = 0) -> Date {
            let cal = Calendar.current
            let base = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: .now))!
            var d = cal.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
            if d < .now.addingTimeInterval(1800) { d = d.addingTimeInterval(86_400) }
            return d
        }

        var activities: [Activity] = [
            a("Sunrise Arboretum 5K", .run, person("Maya"), at(days: 1, hour: 6, minute: 30), 45,
              "UC Davis Arboretum", "Garrod Dr, Davis, CA", 38.5372, -121.7531, 6, [person("Diego")],
              "Easy conversational pace (~9:30/mi) around the Arboretum loop. We finish at Mishka's for coffee if anyone's in!",
              ["Conversational pace", "Coffee after", "Early bird"], .beginner, false, "Free"),
            a("Kings vs. Warriors — need 2 more!", .sports, person("Ethan"), at(days: 3, hour: 19), 180,
              "Golden 1 Center", "500 David J Stern Walk, Sacramento", 38.5802, -121.4997, 4, [person("Liam")],
              "Got 4 seats in section 214. Carpooling from Davis at 5:45. Venmo for the ticket ($38).",
              ["Carpool", "Tickets sorted", "Loud fans"], .anyone, true, "$38 ticket"),
            a("Taco crawl downtown", .food, person("Sofia"), at(days: 2, hour: 18, minute: 30), 150,
              "Downtown Davis", "G St & 2nd St, Davis, CA", 38.5446, -121.7395, 6, [person("Noah"), person("Marcus")],
              "Three spots, three tacos each, one champion. Ratings card provided. Vegetarian-friendly route.",
              ["Foodie", "Vegetarian ok", "Walking"], .anyone, false, "~$20"),
            a("Indie night at Torch Club", .concert, person("Jordan"), at(days: 4, hour: 21), 180,
              "Torch Club", "904 15th St, Sacramento", 38.5776, -121.4890, 5, [person("Zoe")],
              "Local indie lineup — three bands. I've got a car with 3 open seats. Let's grab food before.",
              ["Live music", "Carpool", "21+"], .anyone, true, "$15 cover"),
            a("Leg day spotter needed", .gym, person("Liam"), at(days: 1, hour: 17), 75,
              "Activities & Recreation Center", "ARC, UC Davis", 38.5426, -121.7597, 2, [],
              "Squats + RDLs. Looking for someone consistent to train with 2–3x a week. All levels okay, I'll show you the ropes.",
              ["Strength", "Accountability", "Recurring"], .intermediate, false, "Free w/ ARC"),
            a("Stebbins Cold Canyon hike", .hike, person("Aisha"), at(days: 5, hour: 8), 240,
              "Stebbins Cold Canyon", "Hwy 128, Winters, CA", 38.5076, -122.0966, 6, [person("Hana"), person("Zoe")],
              "5.5 mi loop with ~1,500 ft gain. Amazing views of Lake Berryessa at the top. Bring 2L water.",
              ["Moderate", "Carpool", "Great views"], .intermediate, true, "Gas split"),
            a("Board game night 🎲", .games, person("Noah"), at(days: 2, hour: 19, minute: 30), 180,
              "Davis Commons", "500 1st St, Davis, CA", 38.5428, -121.7375, 6, [person("Priya")],
              "Catan, Codenames, Wingspan. Bring snacks or a game. Newbies very welcome — I'll teach.",
              ["Chill", "Snacks", "Teaching"], .beginner, false, "Free"),
            a("Saturday farmers market + brunch", .explore, person("Emma"), at(days: 6, hour: 9), 150,
              "Davis Farmers Market", "Central Park, Davis, CA", 38.5452, -121.7445, 4, [],
              "Wander the market, grab pastries, then brunch at Burgers & Brew patio. Film camera may appear 📸",
              ["Slow morning", "Photography", "Brunch"], .anyone, false, "Pay your own"),
            a("40mi Winters loop ride", .cycling, person("Diego"), at(days: 6, hour: 7, minute: 30), 180,
              "Davis Bike Loop — Putah Creek", "Old Davis Rd, Davis, CA", 38.5320, -121.7560, 8, [person("Aisha"), person("Maya")],
              "No-drop ride, avg 17mph. Regroup at the Winters Steady Eddy's for a coffee stop.",
              ["No-drop", "Road bike", "Coffee stop"], .intermediate, false, "Free"),
            a("Finals cram session", .study, person("Priya"), at(days: 1, hour: 14), 180,
              "Shields Library", "100 NW Quad, UC Davis", 38.5397, -121.7495, 5, [person("Omar")],
              "Quiet-ish group studying on the 2nd floor. 50/10 Pomodoro. I bring the snacks, you bring the focus.",
              ["Pomodoro", "Snacks", "Quiet"], .anyone, false, "Free"),
            a("Sunset yoga in Central Park", .yoga, person("Hana"), at(days: 2, hour: 17, minute: 30), 60,
              "Central Park", "4th & C St, Davis, CA", 38.5455, -121.7442, 10, [person("Maya"), person("Priya"), person("Emma")],
              "Gentle vinyasa flow as the sun goes down. Bring a mat or towel. Matcha afterwards for whoever's in.",
              ["All levels", "Outdoors", "Matcha after"], .beginner, false, "Free"),
            a("Dune: Part Three — IMAX", .movies, person("Marcus"), at(days: 3, hour: 20), 180,
              "Regal Natomas Marketplace IMAX", "3561 Truxel Rd, Sacramento", 38.6400, -121.5050, 4, [person("Noah")],
              "Booking seats in the middle of row J. Lmk before Wednesday and I'll grab yours.",
              ["IMAX", "Sci‑fi", "Carpool"], .anyone, true, "$24 ticket"),
            a("Lake Tahoe day trip", .explore, person("Zoe"), at(days: 8, hour: 6), 720,
              "South Lake Tahoe", "South Lake Tahoe, CA", 38.9399, -119.9772, 4, [person("Aisha")],
              "Leaving Davis at 6am. Kayak at Zephyr Cove, lunch on the beach, back by 7pm. Playlist collab required.",
              ["Road trip", "Kayaking", "Full day"], .anyone, true, "~$35 gas + rental"),
            a("Pour-over tasting crawl", .coffee, person("Omar"), at(days: 1, hour: 10), 120,
              "Mishka's Café", "610 2nd St, Davis, CA", 38.5440, -121.7407, 4, [],
              "Hitting Mishka's, Temple, and Philz. We'll compare single-origins and rank them. Nerd-level optional.",
              ["Coffee nerds", "Walking", "Morning"], .anyone, false, "~$15"),
            a("Crocker Art Museum + dim sum", .art, person("Emma"), at(days: 7, hour: 11), 240,
              "Crocker Art Museum", "216 O St, Sacramento", 38.5773, -121.5080, 4, [person("Sofia")],
              "Free first Sunday! Wander the galleries then dim sum at New Canton. Train from Davis.",
              ["Museum", "Dim sum", "Amtrak"], .anyone, false, "Free + food"),
            a("Pickup basketball 3v3", .sports, person("Ethan"), at(days: 1, hour: 18), 90,
              "ARC Courts", "ARC, UC Davis", 38.5430, -121.7600, 6, [person("Liam"), person("Noah")],
              "Running 3v3s, winners stay on. Casual but we do keep score 😤",
              ["Casual", "Indoor", "Score kept"], .intermediate, false, "Free"),
            a("Karaoke night", .drinks, person("Jordan"), at(days: 5, hour: 21), 150,
              "Sudwerk Brewing", "2001 2nd St, Davis, CA", 38.5481, -121.7290, 8, [person("Ethan"), person("Zoe"), person("Sofia")],
              "Booked a private room. Duets strongly encouraged. Bad singing extremely welcome.",
              ["21+", "Duets", "Silly"], .anyone, false, "$10 room split"),
            a("Morning tempo run", .run, person("Diego"), at(days: 3, hour: 7), 50,
              "Davis Greenbelt", "Village Homes, Davis, CA", 38.5520, -121.7750, 4, [],
              "4 x 1 mile at tempo pace with jog recovery. Great for 10K / half training.",
              ["Workout", "Tempo", "Training"], .advanced, false, "Free")
        ]
        activities.sort { $0.date < $1.date }

        // A couple of warm conversations so Chats isn't empty.
        let maya = person("Maya"), hana = person("Hana")
        let conversations: [Conversation] = [
            Conversation(
                id: UUID(), activityID: nil, participantIDs: [me.id, maya],
                messages: [
                    Message(senderID: maya, text: "Hey! Saw you're into running too 👋", date: .now.addingTimeInterval(-7200)),
                    Message(senderID: me.id, text: "Yes! Trying to get back into it", date: .now.addingTimeInterval(-7000)),
                    Message(senderID: maya, text: "I'm doing the Arboretum loop tomorrow morning if you want to join — super chill pace", date: .now.addingTimeInterval(-6800))
                ],
                unreadCount: 1
            ),
            Conversation(
                id: UUID(), activityID: nil, participantIDs: [me.id, hana],
                messages: [
                    Message(senderID: hana, text: "Thanks for coming to yoga last week!", date: .now.addingTimeInterval(-90_000)),
                    Message(senderID: me.id, text: "It was so good, I slept like a baby 😴", date: .now.addingTimeInterval(-88_000)),
                    Message(senderID: hana, text: "Haha that's the goal. Same time this week 🌅", date: .now.addingTimeInterval(-87_000))
                ]
            )
        ]

        return Seed(people: people, activities: activities, conversations: conversations, requests: [])
    }

    // MARK: Builders

    private static func p(_ name: String, _ age: Int, _ pronouns: String, _ bio: String, _ interests: [ActivityCategory],
                          _ hue: Double, _ emoji: String, _ verified: Bool, _ rating: Double, _ done: Int) -> Person {
        Person(id: UUID(), name: name, age: age, bio: bio, pronouns: pronouns, interests: interests, hue: hue,
               emoji: emoji, isVerified: verified, rating: rating, activitiesDone: done, school: "UC Davis")
    }

    private static func a(_ title: String, _ category: ActivityCategory, _ host: UUID, _ date: Date, _ duration: Int,
                          _ place: String, _ address: String, _ lat: Double, _ lon: Double, _ capacity: Int,
                          _ attendees: [UUID], _ details: String, _ tags: [String], _ level: ActivityLevel,
                          _ approval: Bool, _ cost: String) -> Activity {
        Activity(id: UUID(), title: title, category: category, hostID: host, date: date, durationMinutes: duration,
                 placeName: place, address: address, latitude: lat, longitude: lon, capacity: capacity,
                 attendeeIDs: attendees, details: details, tags: tags, level: level, requiresApproval: approval,
                 costNote: cost)
    }

    /// Lines other people "say" in the prototype's simulated chat.
    static let replies: [String] = [
        "Sounds great! 🙌", "I'm in, see you there!", "Should we meet 5 min early?",
        "Haha love that", "Perfect, I'll bring water 💧", "Can't wait!", "Omw 🚶",
        "Let me know if plans change", "Wait this is going to be so fun", "👍",
        "Anyone want to carpool?", "I'll text when I'm close"
    ]

    static let requestNotes: [String] = [
        "Hey! This looks fun, would love to join 😊",
        "I've been wanting to do this for ages — count me in?",
        "New to Davis and trying to meet people. Can I join?",
        "I'm free that day! Mind if I tag along?"
    ]
}
