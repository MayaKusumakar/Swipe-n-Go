import Foundation

/// Seed content so the prototype feels alive on first launch: UC Davis club events.
/// Club names are generic examples, not real organizations. Everything is around campus.
enum SampleData {
    struct Seed {
        var people: [Person]
        var activities: [Activity]
        var conversations: [Conversation]
        var requests: [JoinRequest]
    }

    static func make(for me: Person) -> Seed {
        // Club officers and members. Club names are generic examples, not real organizations.
        let people: [Person] = [
            p("Maya Chen", 21, "she/her", "Running Club captain 🏃‍♀️ Sunrise loops, post-run bagels, all paces welcome.", [.sports, .social, .outdoors], 0.02, "🏃‍♀️", true, 4.9, 42),
            p("Jordan Patel", 23, "he/him", "Music Collective organizer. Runs open mics at the MU every other Friday.", [.music, .arts, .social], 0.75, "🎧", true, 4.8, 31),
            p("Sofia Ramirez", 20, "she/her", "Volunteer coordinator for the campus pantry. Always looking for helping hands.", [.service, .cultural, .social], 0.92, "🌮", false, 4.7, 18),
            p("Liam O'Connor", 22, "he/him", "Chapter recruitment chair. Ask me anything about Greek life at Davis.", [.greek, .sports, .social], 0.58, "🏛️", true, 4.9, 56),
            p("Aisha Bello", 24, "she/her", "Developer Club president. Weekend hiker, weekday coder.", [.tech, .outdoors, .career], 0.38, "💻", true, 5.0, 64),
            p("Noah Kim", 19, "he/him", "Esports Club officer. Smash, board games and late-night ramen.", [.gaming, .tech, .social], 0.65, "🎮", false, 4.6, 12),
            p("Emma Larsen", 21, "she/her", "Film Society + improv team. Art history major with a film camera.", [.arts, .service, .music], 0.85, "🎬", true, 4.8, 23),
            p("Diego Alvarez", 25, "he/him", "Cycling Club ride leader. 40 miles is a warm-up; coffee stops are mandatory.", [.outdoors, .sports, .wellness], 0.12, "🚴", true, 4.9, 77),
            p("Priya Nair", 22, "she/her", "South Asian student association + pre-med study group lead.", [.cultural, .academic, .wellness], 0.48, "🪔", false, 4.7, 15),
            p("Ethan Brooks", 23, "he/him", "Club volleyball setter and ASUCD event volunteer.", [.sports, .social, .career], 0.08, "🏐", true, 4.5, 29),
            p("Hana Sato", 20, "she/her", "Yoga & Mindfulness Club. International student from Osaka 🍵", [.wellness, .cultural, .faith], 0.30, "🧘‍♀️", true, 4.9, 37),
            p("Marcus Green", 24, "he/him", "Business society VP. Will review your resume, honestly.", [.career, .academic, .social], 0.70, "💼", false, 4.6, 20),
            p("Zoe Martin", 21, "she/her", "Outdoors Club trip leader. If it has a trailhead, count me in.", [.outdoors, .service, .music], 0.55, "⛰️", true, 4.8, 33),
            p("Omar Haddad", 22, "he/him", "Interfaith council rep and amateur barista.", [.faith, .cultural, .social], 0.15, "☕️", false, 4.7, 19)
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
            a("Running Club: Sunrise Arboretum 5K", .sports, person("Maya"), at(days: 1, hour: 6, minute: 30), 45,
              "UC Davis Arboretum", "Garrod Dr, Davis, CA", 38.5372, -121.7531, 20, [person("Diego"), person("Ethan")],
              "Weekly club run around the Arboretum loop at a conversational pace. New members welcome, no sign-up needed. Bagels after!",
              ["Running Club", "All paces", "New members"], .beginner, false, "Free"),
            a("Fall Club Showcase on the Quad", .social, person("Ethan"), at(days: 2, hour: 11), 180,
              "The Quad", "UC Davis Quad, Davis, CA", 38.5422, -121.7495, 300, [person("Maya"), person("Noah"), person("Zoe")],
              "Meet dozens of student organizations in one afternoon: sports, cultural, service, tech and more. Free snacks and swag.",
              ["Club fair", "Free food", "Meet clubs"], .anyone, false, "Free"),
            a("Developer Club: Intro to iOS Workshop", .tech, person("Aisha"), at(days: 3, hour: 18), 90,
              "Kemper Hall", "Kemper Hall, UC Davis", 38.5375, -121.7546, 40, [person("Noah")],
              "Build your first SwiftUI app in 90 minutes. Bring a Mac if you have one; we'll pair up if not.",
              ["Workshop", "Beginner friendly", "Bring a laptop"], .beginner, false, "Free"),
            a("Hackathon Team Mixer", .tech, person("Aisha"), at(days: 6, hour: 19), 120,
              "Memorial Union", "Memorial Union, UC Davis", 38.5424, -121.7494, 60, [],
              "Find teammates before this quarter's hackathon. Quick intros, idea board, pizza.",
              ["Hackathon", "Teammates", "Pizza"], .anyone, false, "Free"),
            a("Diwali Night Potluck", .cultural, person("Priya"), at(days: 4, hour: 18, minute: 30), 150,
              "Student Community Center", "Student Community Center, UC Davis", 38.5398, -121.7540, 80, [person("Hana"), person("Omar")],
              "Hosted by the South Asian student association. Bring a dish or just bring yourself. Rangoli and diyas provided.",
              ["Culture night", "Potluck", "Everyone welcome"], .anyone, false, "Free"),
            a("International Coffee Hour", .cultural, person("Hana"), at(days: 1, hour: 16), 60,
              "International Center", "International Center, UC Davis", 38.5419, -121.7598, 50, [person("Priya")],
              "Practice languages, meet students from 30+ countries, and try snacks from around the world.",
              ["Language exchange", "Coffee", "Meet people"], .anyone, false, "Free"),
            a("Resume Review Night", .career, person("Marcus"), at(days: 2, hour: 17, minute: 30), 120,
              "Student Community Center", "Student Community Center, UC Davis", 38.5398, -121.7545, 30, [person("Ethan")],
              "Business society officers and alumni review resumes 1:1 before internship season. Bring a printed copy.",
              ["Career", "Internships", "1:1 feedback"], .anyone, true, "Free"),
            a("Arboretum Restoration Volunteer Day", .service, person("Sofia"), at(days: 5, hour: 9), 180,
              "UC Davis Arboretum", "Putah Creek, UC Davis", 38.5332, -121.7566, 25, [person("Emma"), person("Zoe")],
              "Plant natives and clear invasive weeds along Putah Creek. Gloves and tools provided; counts toward service hours.",
              ["Volunteer", "Outdoors", "Service hours"], .anyone, false, "Free"),
            a("Campus Pantry Packing Shift", .service, person("Sofia"), at(days: 3, hour: 14), 120,
              "Memorial Union", "Memorial Union, UC Davis", 38.5426, -121.7490, 12, [],
              "Help pack grocery bags for students. Two-hour shift, training on the spot.",
              ["Volunteer", "Food security", "Training provided"], .anyone, true, "Free"),
            a("Outdoors Club: Stebbins Cold Canyon Hike", .outdoors, person("Zoe"), at(days: 6, hour: 8), 240,
              "Stebbins Cold Canyon", "Hwy 128, Winters, CA", 38.5076, -122.0966, 15, [person("Aisha"), person("Hana")],
              "5.5 mi loop with ~1,500 ft gain and views of Lake Berryessa. Club carpools leave the ARC at 7:30.",
              ["Club trip", "Carpool", "Moderate"], .intermediate, true, "Gas split"),
            a("Cycling Club: Winters Loop Ride", .outdoors, person("Diego"), at(days: 7, hour: 7, minute: 30), 180,
              "Putah Creek Bike Path", "Old Davis Rd, Davis, CA", 38.5320, -121.7560, 20, [person("Maya")],
              "No-drop club ride, about 17 mph average. Coffee stop in Winters. Helmets required.",
              ["No-drop", "Road bike", "Coffee stop"], .intermediate, false, "Free"),
            a("Sunset Yoga on the Quad", .wellness, person("Hana"), at(days: 2, hour: 17, minute: 30), 60,
              "The Quad", "UC Davis Quad, Davis, CA", 38.5418, -121.7500, 40, [person("Priya"), person("Emma")],
              "Yoga & Mindfulness Club's weekly flow. All levels; bring a mat or towel.",
              ["All levels", "Outdoors", "Weekly"], .beginner, false, "Free"),
            a("Music Collective Open Mic", .music, person("Jordan"), at(days: 4, hour: 20), 150,
              "The Coffee House (MU)", "Memorial Union, UC Davis", 38.5425, -121.7490, 80, [person("Emma"), person("Zoe")],
              "Sign up at the door to play, sing or read. Supportive crowd, free coffee for performers.",
              ["Open mic", "Perform", "Free coffee"], .anyone, false, "Free"),
            a("Film Society Screening + Discussion", .arts, person("Emma"), at(days: 3, hour: 19, minute: 30), 150,
              "Wellman Hall", "Wellman Hall, UC Davis", 38.5411, -121.7505, 120, [person("Marcus")],
              "This week: a classic sci-fi double feature, then a short discussion. Popcorn on us.",
              ["Film", "Discussion", "Popcorn"], .anyone, false, "Free"),
            a("Esports Club: Smash Tournament", .gaming, person("Noah"), at(days: 5, hour: 18), 240,
              "Memorial Union Games Area", "Memorial Union, UC Davis", 38.5427, -121.7496, 64, [person("Aisha")],
              "Bracket starts at 6:30. Bring your controller. Casual pools for first-timers.",
              ["Tournament", "Beginners pool", "Bring a controller"], .anyone, false, "$3 entry"),
            a("Pre-Med Midterm Study Group", .academic, person("Priya"), at(days: 1, hour: 19), 120,
              "Shields Library", "100 NW Quad, UC Davis", 38.5397, -121.7495, 15, [person("Omar")],
              "Group review for BIS 2A midterm. Practice problems and flashcards provided.",
              ["Study group", "Midterms", "Quiet"], .anyone, false, "Free"),
            a("Fall Recruitment Open House", .greek, person("Liam"), at(days: 4, hour: 17), 120,
              "Memorial Union", "Memorial Union, UC Davis", 38.5422, -121.7492, 100, [person("Ethan")],
              "Meet chapters from across the Greek councils and learn how recruitment works. No commitment.",
              ["Recruitment", "Info session", "No commitment"], .anyone, false, "Free"),
            a("Interfaith Dinner", .faith, person("Omar"), at(days: 6, hour: 18), 120,
              "Student Community Center", "Student Community Center, UC Davis", 38.5399, -121.7542, 40, [person("Hana")],
              "Students from many faith traditions share a meal and a guided conversation. Vegetarian and halal options.",
              ["Dinner", "Conversation", "Everyone welcome"], .anyone, true, "Free"),
            a("Club Volleyball Open Practice", .sports, person("Ethan"), at(days: 2, hour: 20), 90,
              "ARC Pavilion", "ARC, UC Davis", 38.5430, -121.7600, 24, [person("Liam")],
              "Try out drills with the club team. Intermediate players, come see if club volleyball is for you.",
              ["Club sports", "Open practice", "Tryouts soon"], .intermediate, false, "Free w/ ARC"),
            a("Business Society Networking Mixer", .career, person("Marcus"), at(days: 8, hour: 18), 120,
              "Activities & Recreation Center", "ARC Ballroom, UC Davis", 38.5426, -121.7597, 90, [],
              "Meet recruiters from local companies and alumni. Business casual.",
              ["Networking", "Recruiters", "Business casual"], .anyone, true, "Free")
        ]
        activities.sort { $0.date < $1.date }

        // A couple of warm conversations so Chats isn't empty.
        let maya = person("Maya"), hana = person("Hana")
        let conversations: [Conversation] = [
            Conversation(
                id: UUID(), activityID: nil, participantIDs: [me.id, maya],
                messages: [
                    Message(senderID: maya, text: "Hey! Saw you checked out Running Club 👋", date: .now.addingTimeInterval(-7200)),
                    Message(senderID: me.id, text: "Yes! Trying to get back into it", date: .now.addingTimeInterval(-7000)),
                    Message(senderID: maya, text: "Club run is tomorrow morning at the Arboretum if you want to join — super chill pace", date: .now.addingTimeInterval(-6800))
                ],
                unreadCount: 1
            ),
            Conversation(
                id: UUID(), activityID: nil, participantIDs: [me.id, hana],
                messages: [
                    Message(senderID: hana, text: "Thanks for coming to Sunset Yoga last week!", date: .now.addingTimeInterval(-90_000)),
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
