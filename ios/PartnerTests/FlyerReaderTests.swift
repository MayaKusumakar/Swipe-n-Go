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
