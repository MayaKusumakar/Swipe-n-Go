import ImageIO
import Testing
import UIKit
@testable import Partner

@Suite("Flyer reader")
struct FlyerReaderTests {
    private func blankImage(width: Int, height: Int) -> CGImage {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height),
                                format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
            .image { ctx in UIColor.orange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height)) }
            .cgImage!
    }

    @Test func claudesReadingFillsTheForm() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let reading = ClaudeFlyerReader.Reading(
            isEventFlyer: true, title: "Fall Climbing Social", startTime: start, endTime: start.addingTimeInterval(7200),
            locationName: "ARC Climbing Wall", address: "ARC, UC Davis", description: "Free gear rental.",
            cost: "Free", category: "sports", missing: ["cost"]
        )
        let result = reading.result(image: UIImage())
        #expect(result.reader == .claude)
        #expect(result.title == "Fall Climbing Social")
        #expect(result.date == start)
        #expect(result.endDate == start.addingTimeInterval(7200))
        #expect(result.location == "ARC Climbing Wall")
        #expect(result.address == "ARC, UC Davis")
        #expect(result.category == .sports)
        #expect(result.missing == ["cost"])
        #expect(result.fallbackReason == nil)
    }

    @Test func unknownCategoryAndDuplicateAddressAreHandled() {
        let reading = ClaudeFlyerReader.Reading(
            isEventFlyer: true, title: "Open Mic", startTime: nil, endTime: nil, locationName: "Coffee House",
            address: "The Coffee House, Memorial Union", description: "", cost: "", category: "nightlife", missing: ["date"]
        )
        let result = reading.result(image: UIImage())
        #expect(result.category == nil)
        #expect(result.location == "Coffee House")
        #expect(FlyerLocation(venue: result.location, address: result.address).query == "The Coffee House, Memorial Union")
    }

    @Test func reviewedLocationKeepsTheRoomAndUsesTheSelectedCoordinates() {
        let location = FlyerLocation(venue: "Shields Library", address: "Room 205")
        let match = Place(name: "Peter J. Shields Library", address: "100 NW Quad", latitude: 38.54, longitude: -121.74)
        let place = location.pinned(to: match)
        #expect(place.name == "Shields Library")
        #expect(place.address == "Room 205")
        #expect(place.latitude == match.latitude)
        #expect(place.longitude == match.longitude)
    }

    @Test func reviewedEndTimeKeepsExactMinutesInHostPicker() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(FlyerFields.duration(from: start, to: start.addingTimeInterval(75 * 60)) == 75)
        #expect(CreateActivityView.durationOptions(including: 75).contains(75))
        #expect(FlyerFields.duration(from: start, to: start) == nil)
    }

    @Test func freeFoodIsNotTreatedAsFreeAdmission() {
        let fields = FlyerScanner.parse(lines: ["Film Night", "Free popcorn", "Admission: $8"])
        #expect(fields.cost == "$8")
        #expect(FlyerScanner.parse(lines: ["Film Night", "Free popcorn", "$5 parking"]).cost.isEmpty)
        #expect(FlyerScanner.parse(lines: ["Film Night", "Tickets $8"]).cost == "$8")
    }

    @Test func uploadIsShrunkAndHasNoLocationData() throws {
        let jpeg = try #require(ClaudeFlyerReader.uploadJPEG(blankImage(width: 3000, height: 2000)))
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 1568)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 1045)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(jpeg.starts(with: [0xFF, 0xD8, 0xFF]))
    }

    @Test func smallImagesAreNotEnlarged() throws {
        let jpeg = try #require(ClaudeFlyerReader.uploadJPEG(blankImage(width: 800, height: 600)))
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 800)
    }

    @Test func onDeviceReadingFlagsWhatItCouldNotFind() throws {
        let lines = ["FALL CLIMBING SOCIAL", "Bring a friend!", "Free"]
        let result = try #require(FlyerScanner.local(image: blankImage(width: 10, height: 10), lines: lines,
                                                     heading: "FALL CLIMBING SOCIAL"))
        #expect(result.reader == .onDevice)
        #expect(result.title == "FALL CLIMBING SOCIAL")
        #expect(result.cost == "Free")
        #expect(result.missing.contains("date") && result.missing.contains("location"))
        #expect(!result.missing.contains("cost"))
    }

    @Test func noTextMeansNoOnDeviceReading() {
        #expect(FlyerScanner.local(image: blankImage(width: 10, height: 10), lines: [], heading: nil) == nil)
    }

    @Test func fallbackExplainsWhy() {
        let reason = FlyerScanner.explain(EventServer.ServerError(message: "The server's Claude API key was rejected."))
        #expect(reason == "The server's Claude API key was rejected. This flyer was read on your iPhone instead.")
        #expect(FlyerScanner.explain(URLError(.cannotConnectToHost)).contains("Couldn't reach"))
    }
}

/// "Describe your plan" in Host a plan: typed text goes through the same review screen as a flyer.
@Suite("Describe your plan")
struct PlanDescriptionTests {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    @Test func claudesReadingFillsTheForm() throws {
        // The shape POST /api/experimental/events/parse answers with.
        let json = #"{"is_event":true,"title":"Pickup Soccer","start_time":"2026-11-15T15:00:00-08:00","#
            + #""end_time":"2026-11-15T17:00:00-08:00","location_name":"ARC fields","address":"","#
            + #""description":"Casual pickup game.","cost":"Free","category":"sports","missing":[],"#
            + #""model":"claude-opus-5-5"}"#
        let result = try decoder.decode(ClaudeTextReader.Reading.self, from: Data(json.utf8)).result
        #expect(result.source == .text)
        #expect(result.reader == .claude)
        #expect(result.image == nil)
        #expect(result.title == "Pickup Soccer")
        #expect(result.endDate?.timeIntervalSince(try #require(result.date)) == 7200)
        #expect(result.location == "ARC fields")
        #expect(result.category == .sports)
        #expect(result.missing.isEmpty)
        #expect(result.isEventFlyer)
    }

    @Test func textThatIsNotAPlanIsFlagged() throws {
        let json = #"{"is_event":false,"title":"","start_time":null,"end_time":null,"location_name":"","address":"","#
            + #""description":"","cost":"","category":"","missing":["title","date","time","location","cost"],"model":"m"}"#
        let result = try decoder.decode(ClaudeTextReader.Reading.self, from: Data(json.utf8)).result
        #expect(!result.isEventFlyer)
        #expect(result.category == nil)
    }

    @Test func onDeviceReadingSplitsTheSentence() throws {
        // The sentence from the first try on 2026-11-14, which used to come back with the whole text as the title.
        let result = FlyerScanner.local(text: "Pickup soccer 3-5PM Saturday at Hutchinson Field Davis CA")
        #expect(result.source == .text)
        #expect(result.reader == .onDevice)
        #expect(result.image == nil)
        #expect(result.title == "Pickup Soccer")
        #expect(result.location == "Hutchinson Field, Davis, CA")
        let start = try #require(result.date)
        #expect(Calendar.current.component(.weekday, from: start) == 7)   // Saturday
        #expect(Calendar.current.component(.hour, from: start) == 15)
        // The detector's dates carry fractions of a second, so compare to the second.
        #expect(abs(try #require(result.endDate).timeIntervalSince(start) - 2 * 3600) < 1)
        #expect(result.category == .sports)
        #expect(result.missing == ["cost"])
    }

    @Test func onDeviceReadingFillsEverythingFromOneLine() {
        let text = "pickup soccer sat 3-5pm at the ARC fields, free"
        let result = FlyerScanner.local(text: text)
        #expect(result.title == "Pickup Soccer")
        #expect(result.location == "ARC fields")
        #expect(result.cost == "Free")
        #expect(result.details == text)
        #expect(result.missing.isEmpty)
    }

    struct Sentence: Sendable, CustomTestStringConvertible {
        let text, title, location, cost: String
        var testDescription: String { text }
    }

    @Test(arguments: [
        Sentence(text: "Study session for ECS 150 at Shields Library tomorrow 7pm",
                 title: "Study Session for ECS 150", location: "Shields Library", cost: ""),
        Sentence(text: "Movie night friday 8pm at my apartment, $3", title: "Movie Night", location: "my apartment", cost: "$3"),
        Sentence(text: "Hike at Mt Diablo this Sunday morning, carpool from the MU", title: "Hike", location: "Mt Diablo", cost: ""),
        Sentence(text: "Saturday 10am farmers market @ Central Park", title: "Farmers Market", location: "Central Park", cost: ""),
        Sentence(text: "Board games at the CoHo from 6 to 9 pm on Thursday", title: "Board Games", location: "CoHo", cost: ""),
        Sentence(text: "Volleyball at 1 Shields Ave, Davis, CA 95616 on Sunday at noon",
                 title: "Volleyball", location: "1 Shields Ave, Davis, CA 95616", cost: ""),
        Sentence(text: "Let’s get boba at Teaspoon after class", title: "Boba", location: "Teaspoon", cost: ""),
        Sentence(text: "Anyone want to play tennis tomorrow at 5 at the courts by the ARC",
                 title: "Play Tennis", location: "courts by the ARC", cost: ""),
        Sentence(text: "Yoga in the Arboretum Sunday 9am, bring a mat", title: "Yoga", location: "Arboretum", cost: ""),
        Sentence(text: "I'm hosting a potluck dinner at my place Friday at 7, bring a dish",
                 title: "Potluck Dinner", location: "my place", cost: ""),
        Sentence(text: "Karaoke night @The Graduate thursday 9pm $5 cover", title: "Karaoke Night", location: "The Graduate", cost: "$5"),
    ])
    func onDeviceReadingFindsTitlePlaceAndPrice(_ sentence: Sentence) {
        let plan = PlanSentence.read(sentence.text)
        #expect(plan.title == sentence.title)
        #expect(plan.location == sentence.location)
        #expect(plan.cost == sentence.cost)
        #expect(!plan.titleIsGuess)
    }

    @Test func aTimeAlreadyPastTodayMeansTomorrow() throws {
        let plan = PlanSentence.read("Boba run at 4pm")
        #expect(try #require(plan.date) > .now)
        #expect(plan.title == "Boba Run")
        #expect(plan.location.isEmpty)
        #expect(plan.category == .social)    // the first word that names a category wins
    }

    @Test func aDayWithoutATimeAsksForTheTime() {
        let result = FlyerScanner.local(text: "soccer saturday at the ARC")
        #expect(result.date != nil)
        #expect(result.missing.contains("time"))
        #expect(!result.missing.contains("date"))
        #expect(result.location == "ARC")
    }

    @Test func withNoNameTheTitleIsLeftForTheHost() {
        let result = FlyerScanner.local(text: "Saturday 3pm at the ARC")
        #expect(result.title.isEmpty)
        #expect(result.missing.contains("title"))
        #expect(result.location == "ARC")
    }

    @Test func labeledLinesStillWork() {
        let result = FlyerScanner.local(text: "Event: Trivia Night\nWhere: CoHo\nWhen: Thursday 8pm")
        #expect(result.title == "Trivia Night")
        #expect(result.location == "CoHo")
        #expect(!result.missing.contains("title"))
    }

    @Test func longTextMakesAShortTitleCutBetweenWords() {
        let title = FlyerScanner.shortTitle("Sunset hike up the Stebbins Cold Canyon trail with snacks after and a group photo at the top")
        #expect(title.count <= 60)
        #expect(title == "Sunset hike up the Stebbins Cold Canyon trail with snacks")
    }

    @Test func withoutAServerThePhoneReadsItAndSaysWhy() async throws {
        let result = try await FlyerScanner.read(text: "trivia tonight 8pm, free", serverURL: nil)
        #expect(result.reader == .onDevice)
        #expect(result.fallbackReason?.contains("Profile → Server") == true)
    }

    @Test func unreachableServerFallsBackToThePhone() async throws {
        // Nothing listens on port 9 here, so the connection is refused at once.
        let result = try await FlyerScanner.read(text: "trivia tonight 8pm, free", serverURL: URL(string: "http://127.0.0.1:9")!)
        #expect(result.reader == .onDevice)
        #expect(result.fallbackReason?.contains("Couldn't reach") == true)
        #expect(result.fallbackReason?.contains("description") == true)
    }

    @Test func fallbackExplainsWhyInTermsOfTheDescription() {
        let off = FlyerScanner.explain(EventServer.ServerError(message: "Not Found", status: 404), subject: "description")
        #expect(off == "Your team's server doesn't have this turned on yet, so this description was read on your iPhone.")
        let noKey = FlyerScanner.explain(
            EventServer.ServerError(message: "The AI features aren't set up on this server yet (no ANTHROPIC_API_KEY).", status: 503),
            subject: "description")
        #expect(noKey.hasSuffix("This description was read on your iPhone instead."))
    }
}

/// The scanner bug: a flyer's date and time were read but didn't reach the right fields.
/// Sample answers from POST /api/flyers/read (complete, partial, empty, malformed), and the
/// phone's own reading when the day and the time are printed on different lines.
@Suite("Flyer scan: date, time and sample AI answers")
struct FlyerScanNormalizationTests {
    /// Decodes the way the app does (snake_case keys); `Reading` reads its own times.
    private func reading(_ json: String) throws -> ClaudeFlyerReader.Reading {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ClaudeFlyerReader.Reading.self, from: Data(json.utf8))
    }

    private let pacific = TimeZone(identifier: "America/Los_Angeles")!

    // MARK: Sample AI answers

    @Test func completeAnswerFillsEveryField() throws {
        let r = try reading(#"""
        {"is_event_flyer": true, "title": "Fall Climbing Social", "start_time": "2026-11-14T19:00:00-08:00",
         "end_time": "2026-11-14T21:00:00-08:00", "location_name": "ARC Climbing Wall", "address": "ARC, UC Davis",
         "description": "Climbing night.", "cost": "Free", "category": "sports", "organizer": "Davis Climbing Club",
         "missing": [], "model": "claude-opus-5-5"}
        """#)
        let result = r.result(image: UIImage())
        #expect(result.date == Date(timeIntervalSince1970: 1_794_711_600))     // 7 PM Pacific
        #expect(result.endDate?.timeIntervalSince(try #require(result.date)) == 7200)
        #expect(result.title == "Fall Climbing Social")
        #expect(result.organizer == "Davis Climbing Club")
        #expect(result.missing.isEmpty)
    }

    @Test func partialAnswerWithNullsKeepsWhatWasFound() throws {
        let r = try reading(#"""
        {"is_event_flyer": true, "title": "Open Mic", "start_time": null, "end_time": null, "location_name": null,
         "address": "", "description": "Bring a song.", "cost": null, "category": "music", "missing": ["location"]}
        """#)
        #expect(r.title == "Open Mic")
        #expect(r.startTime == nil)
        #expect(r.locationName == "" && r.cost == "")
        #expect(r.organizer == nil)
        #expect(r.missing == ["location", "date", "time"])
        #expect(r.result(image: UIImage()).category == .music)
    }

    @Test func emptyAnswerFlagsEverythingInsteadOfFailing() throws {
        let r = try reading("{}")
        #expect(r.isEventFlyer)
        #expect(r.title.isEmpty && r.startTime == nil && r.endTime == nil)
        #expect(r.missing == ["date", "time"])
    }

    @Test func malformedJSONThrowsSoThePhoneReadsTheFlyerInstead() {
        #expect(throws: (any Error).self) { try reading("<html>Bad Gateway</html>") }
        #expect(throws: (any Error).self) { try reading(#"["not", "an", "object"]"#) }
        // FlyerScanner.scan turns any such error into the on-device reading, with a reason.
        #expect(FlyerScanner.explain(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "")))
                == "Something went wrong with Claude, so this flyer was read on your iPhone.")
    }

    @Test func oddTimesAreStillRead() throws {
        // A time Claude can't be trusted with is dropped and flagged, not fatal to the whole answer.
        let words = try reading(#"{"title": "Trivia", "start_time": "next friday 8pm", "end_time": "9pm"}"#)
        #expect(words.title == "Trivia" && words.startTime == nil && words.endTime == nil)
        #expect(words.missing == ["date", "time"])

        // No UTC offset: the phone's own time zone.
        let naive = FlyerTime.parse("2026-11-23T18:00:00", timeZone: pacific)
        #expect(naive == FlyerTime(date: Date(timeIntervalSince1970: 1_795_485_600), hasTime: true))
        #expect(FlyerTime.parse("2026-11-23T18:00", timeZone: pacific).date == naive.date)
        #expect(FlyerTime.parse("2026-11-24T02:00:00.000000+00:00").date == naive.date)

        // Only a day: kept at noon, with the time flagged for the host.
        let day = FlyerTime.parse("2026-11-23", timeZone: pacific)
        #expect(day.hasTime == false)
        #expect(day.date == Date(timeIntervalSince1970: 1_795_464_000))
        #expect(FlyerTime.parse(nil) == FlyerTime())
        #expect(FlyerTime.parse("  ") == FlyerTime())
    }

    @Test func dayOnlyAnswerAsksForTheTimeAndDropsTheEnd() throws {
        let r = try reading(#"{"title": "Club Fair", "start_time": "2026-12-03", "end_time": "2026-12-03", "missing": []}"#)
        #expect(r.startTime != nil)
        #expect(r.endTime == nil)
        #expect(r.missing == ["time"])
    }

    @Test func endBeforeStartIsDropped() throws {
        let r = try reading(#"{"start_time": "2026-11-14T19:00:00-08:00", "end_time": "2026-11-14T18:00:00-08:00"}"#)
        #expect(r.startTime != nil && r.endTime == nil)
    }

    // MARK: On the phone (no server)

    private let now: Date = {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9))!
    }()

    private func parts(_ date: Date?) -> DateComponents? {
        date.map { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
    }

    @Test func dayAndTimeOnSeparateLinesAreCombined() {
        // Before the fix this came back as Nov 23 at 12:00 PM, no end time, and the time not flagged.
        let fields = FlyerScanner.parse(lines: ["Film Night", "Nov 23", "6-8 PM", "Room 205"], now: now)
        #expect(parts(fields.date) == DateComponents(year: 2026, month: 11, day: 23, hour: 18, minute: 0))
        #expect(parts(fields.endDate) == DateComponents(year: 2026, month: 11, day: 23, hour: 20, minute: 0))
        #expect(fields.hasDay && fields.hasTime)
    }

    @Test func dayAndTimeRangeOnOneLine() {
        let fields = FlyerScanner.parse(lines: ["Film Night", "Friday 12/4 · 7pm - 9pm"], now: now)
        #expect(parts(fields.date) == DateComponents(year: 2026, month: 12, day: 4, hour: 19, minute: 0))
        #expect(fields.endDate.map { $0.timeIntervalSince(fields.date!) } == 7200)
    }

    @Test func dayWithoutATimeIsFlagged() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }.cgImage!
        let result = try #require(FlyerScanner.local(image: image, lines: ["Club Fair", "Dec 3", "Quad"], heading: nil))
        #expect(result.date != nil)
        #expect(result.missing.contains("time"))
        #expect(!result.missing.contains("date"))
    }

    @Test func timeWithoutADayIsFlagged() {
        let fields = FlyerScanner.parse(lines: ["Trivia", "8pm"], now: now)
        #expect(fields.hasTime && !fields.hasDay)
        #expect(Calendar.current.component(.hour, from: fields.date!) == 20)
    }

    @Test func aDateWithoutAYearMeansTheNextOne() {
        let fields = FlyerScanner.parse(lines: ["Winter Kickoff", "Jan 10", "5pm"], now: now)
        #expect(parts(fields.date)?.year == 2027)
        #expect(parts(fields.date)?.month == 1)
        let printedYear = FlyerScanner.parse(lines: ["Reunion", "Jan 10, 2026", "5pm"], now: now)
        #expect(parts(printedYear.date)?.year == 2026)
    }

    @Test func nothingDatelikeMeansNoDate() {
        let fields = FlyerScanner.parse(lines: ["Free pizza", "Bring a friend"], now: now)
        #expect(fields.date == nil && !fields.hasDay && !fields.hasTime)
    }

    // MARK: Review screen → Host form

    @Test func organizerGoesAtTheTopOfTheDescriptionOnce() {
        #expect(FlyerFields.details("Climbing night.", organizer: "Davis Climbing Club")
                == "Hosted by Davis Climbing Club.\n\nClimbing night.")
        #expect(FlyerFields.details("", organizer: "Davis Climbing Club") == "Hosted by Davis Climbing Club.")
        #expect(FlyerFields.details("Davis Climbing Club's social.", organizer: "davis climbing club")
                == "Davis Climbing Club's social.")
        #expect(FlyerFields.details("  Climbing night. ", organizer: "  ") == "Climbing night.")
    }

    @Test func failedScansExplainWhatToDo() {
        #expect(FailedScan(data: Data(), error: CocoaError(.fileReadCorruptFile)).message.contains("couldn't be opened"))
        #expect(FailedScan(data: Data(), error: URLError(.timedOut)).message.contains("connection"))
        #expect(FailedScan(data: Data(), error: CocoaError(.fileReadUnknown)).message.contains("blurry"))
    }
}
