import SwiftUI
import Vision
import AVFoundation
import ImageIO

struct FlyerScanResult: Identifiable {
    enum Reader: Equatable {
        /// Claude read the flyer image through the team's server (POST /api/flyers/read).
        case claude
        /// Apple's on-device text recognition plus simple rules (the fallback).
        case onDevice
    }

    let id = UUID()
    var title: String
    var date: Date?
    var endDate: Date? = nil
    var location: String
    var address = ""
    var details: String
    var cost: String
    var category: ActivityCategory? = nil
    /// The club or group hosting it, if the flyer names one.
    var organizer = ""
    /// Fields the reader couldn't find or wasn't sure about: title, date, time, location, cost.
    var missing: [String] = []
    var isEventFlyer = true
    var reader: Reader = .onDevice
    /// Why Claude wasn't used, when the phone read the flyer itself.
    var fallbackReason: String? = nil
    /// A flyer photo, or a plan the host typed ("Describe your plan" in Host a plan).
    enum Source: Equatable { case flyer, text }
    var source: Source = .flyer
    /// The flyer photo; nil for typed text.
    var image: UIImage?
}

enum FlyerScanner {
    /// Reads a flyer: Claude when the server can, otherwise on the phone.
    static func scan(_ data: Data, serverURL: URL?) async throws -> FlyerScanResult {
        let (image, lines, heading) = try await recognize(data)
        let onDevice = local(image: image, lines: lines, heading: heading)

        guard let serverURL else {
            guard var result = onDevice else { throw CocoaError(.fileReadUnknown) }
            result.fallbackReason = "Connect to your team's server in Profile → Server to read flyers with Claude."
            return result
        }
        do {
            let reading = try await ClaudeFlyerReader(baseURL: serverURL).read(image, ocrText: lines.joined(separator: "\n"))
            return reading.result(image: UIImage(cgImage: image))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // No text on the phone either: nothing to show.
            guard var result = onDevice else { throw error }
            result.fallbackReason = explain(error)
            return result
        }
    }

    /// Reads a typed plan description: Claude when the server can, otherwise on the phone.
    /// Never fails for lack of a server: the phone can always read the text itself.
    static func read(text: String, serverURL: URL?) async throws -> FlyerScanResult {
        var onDevice = local(text: text)
        guard let serverURL else {
            onDevice.fallbackReason = "Connect to your team's server in Profile → Server to read descriptions with Claude."
            return onDevice
        }
        do {
            return try await ClaudeTextReader(baseURL: serverURL).read(text).result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            onDevice.fallbackReason = explain(error, subject: "description")
            return onDevice
        }
    }

    /// Why Claude didn't read the flyer (or description), in words a host understands.
    static func explain(_ error: Error, subject: String = "flyer") -> String {
        if let serverError = error as? EventServer.ServerError {
            if serverError.status == 404 {
                // The server is older than this feature, or it's turned off there (EXPERIMENTS).
                return "Your team's server doesn't have this turned on yet, so this \(subject) was read on your iPhone."
            }
            let message = serverError.message.trimmingCharacters(in: .whitespacesAndNewlines)
            return (message.hasSuffix(".") ? message : message + ".") + " This \(subject) was read on your iPhone instead."
        }
        if error is URLError {
            return "Couldn't reach your team's server, so this \(subject) was read on your iPhone."
        }
        return "Something went wrong with Claude, so this \(subject) was read on your iPhone."
    }

    /// Decodes the image (upright, at most 2400 px) and runs Apple's text recognition.
    /// Returns the lines in reading order and the biggest plain-text line (usually the event name).
    static func recognize(_ data: Data) async throws -> (CGImage, [String], String?) {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2400
                  ] as CFDictionary) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image).perform([request])
            let observations = (request.results ?? []).sorted {
                if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.02 {
                    return $0.boundingBox.midY > $1.boundingBox.midY
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
            let heading = observations
                .filter { observation in
                    guard let line = observation.topCandidates(1).first?.string else { return false }
                    return !line.contains("@") && !line.lowercased().contains("http")
                        && line.rangeOfCharacter(from: .letters) != nil
                }
                .max { $0.boundingBox.height < $1.boundingBox.height }?
                .topCandidates(1).first?.string
            return (image, observations.compactMap { $0.topCandidates(1).first?.string }, heading)
        }.value
    }

    /// The on-device reading, or nil when no text was found.
    static func local(image: CGImage, lines: [String], heading: String?) -> FlyerScanResult? {
        guard !lines.isEmpty else { return nil }
        let fields = parse(lines: lines)
        var missing: [String] = []
        if !fields.hasDay { missing.append("date") }
        if !fields.hasTime { missing.append("time") }
        if fields.location.isEmpty && fields.address.isEmpty { missing.append("location") }
        if fields.cost.isEmpty { missing.append("cost") }
        return FlyerScanResult(
            title: fields.title.isEmpty ? (heading ?? lines[0]) : fields.title,
            date: fields.date, endDate: fields.endDate, location: fields.location, address: fields.address,
            details: lines.joined(separator: "\n"),
            cost: fields.cost, missing: missing, reader: .onDevice, image: UIImage(cgImage: image)
        )
    }

    /// The on-device reading of a typed description: the sentence rules in `PlanSentence`, plus a
    /// flyer's labeled lines ("Where: ARC") for anyone who types it that way.
    static func local(text: String) -> FlyerScanResult {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let labeled = parse(lines: lines)
        let plan = PlanSentence.read(text)
        let title = labeled.title.isEmpty ? plan.title : labeled.title
        let location = labeled.location.isEmpty ? plan.location : labeled.location
        let address = labeled.location.isEmpty && !location.isEmpty ? "" : labeled.address
        let cost = plan.cost.isEmpty ? labeled.cost : plan.cost
        var missing: [String] = []
        if title.isEmpty || (labeled.title.isEmpty && plan.titleIsGuess) { missing.append("title") }
        if plan.date == nil { missing += ["date", "time"] } else if !plan.hasTime { missing.append("time") }
        if location.isEmpty && address.isEmpty { missing.append("location") }
        if cost.isEmpty { missing.append("cost") }
        return FlyerScanResult(
            title: title, date: plan.date, endDate: plan.endDate, location: location, address: address,
            details: text.trimmingCharacters(in: .whitespacesAndNewlines), cost: cost, category: plan.category,
            missing: missing, reader: .onDevice, source: .text, image: nil
        )
    }

    /// The start of a sentence as a title: at most `limit` characters, cut between words.
    static func shortTitle(_ line: String, limit: Int = 60) -> String {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.count > limit else { return line }
        let cut = line.prefix(limit)
        return String(cut[..<(cut.lastIndex(of: " ") ?? cut.endIndex)])
    }

    /// Kept separate from recognition so extraction can be checked with sample flyer text.
    static func parse(lines: [String], now: Date = .now)
        -> (title: String, date: Date?, endDate: Date?, hasDay: Bool, hasTime: Bool, location: String, address: String, cost: String) {
        func labeled(_ labels: [String]) -> String? {
            for line in lines {
                for label in labels {
                    let prefix = label + ":"
                    if line.lowercased().hasPrefix(prefix) {
                        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                    }
                }
            }
            return nil
        }
        let text = lines.joined(separator: "\n")
        let dateText = [labeled(["date", "when"]), labeled(["time"])].compactMap { $0 }.joined(separator: " ")
        let when = FlyerDateTime.read(dateText.isEmpty ? text : dateText, now: now)
        let location = labeled(["location", "where", "venue"]) ?? ""
        var address = labeled(["address", "room"]) ?? ""
        if address.isEmpty, location.isEmpty,
           let addresses = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue),
           let match = addresses.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range, in: text) {
            address = String(text[range])
        }
        var cost = labeled(["cost", "price", "admission"]) ?? ""
        if cost.isEmpty {
            if lines.contains(where: {
                $0.range(of: #"^\s*(?:free(?:\s+(?:entry|admission))?|(?:entry|admission)\s+(?:is\s+)?free)\s*[!.]?\s*$"#,
                         options: [.regularExpression, .caseInsensitive]) != nil
            }) {
                cost = "Free"
            } else if let priceLine = lines.first(where: {
                $0.range(of: #"^\s*(?:(?:tickets?|entry|admission)\s+)?\$\s*\d+(?:\.\d{2})?(?:\s+(?:entry|admission|per person))?\s*[!.]?\s*$"#,
                         options: [.regularExpression, .caseInsensitive]) != nil
            }), let range = priceLine.range(of: #"\$\s*\d+(?:\.\d{2})?"#, options: .regularExpression) {
                cost = String(priceLine[range])
            }
        }
        return (labeled(["event", "title"]) ?? "", when.start, when.end, when.hasDay, when.hasTime, location, address, cost)
    }
}

/// Finds a flyer's day and time even when they're printed apart ("Nov 23" on one line, "6-8 PM" on the
/// next). Apple's detector returns those as two matches: the day at noon, and the time on today's date.
/// The reader used to keep only the first match, so the event landed at noon with no end time and the
/// time wasn't even flagged. This puts the day and the time (and its end) back together.
enum FlyerDateTime {
    struct Reading: Equatable {
        var start: Date?
        var end: Date?
        /// The text named a day ("Nov 23", "Friday", "12/5").
        var hasDay = false
        /// The text named a time of day ("6pm", "18:30", "noon").
        var hasTime = false
    }

    static func read(_ text: String, now: Date = .now, calendar: Calendar = .current) -> Reading {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return Reading() }
        let ns = text as NSString
        let matches = detector.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            match.date.map { (date: $0, duration: match.duration, said: ns.substring(with: match.range)) }
        }
        let day = matches.first { names($0.said, dayPattern) }
        let clock = matches.first { names($0.said, timePattern) }
        guard let base = day ?? clock else { return Reading() }

        var start = base.date
        if let clock {
            let time = calendar.dateComponents([.hour, .minute], from: clock.date)
            start = calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: base.date) ?? start
        }
        // No year printed means the next one: "Jan 10" read in November is next January.
        if let day, !names(day.said, #"\b20\d{2}\b"#), start < calendar.startOfDay(for: now),
           let next = calendar.date(byAdding: .year, value: 1, to: start) {
            start = next
        }
        let duration = clock?.duration ?? 0
        return Reading(start: start, end: duration > 0 ? start.addingTimeInterval(duration) : nil,
                       hasDay: day != nil, hasTime: clock != nil)
    }

    private static let dayPattern = #"(?i)\b(?:today|tonight|tomorrow|mon|tue|wed|thu|fri|sat|sun|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)|\d{1,2}/\d{1,2}|\d{4}-\d{2}-\d{2}"#
    private static let timePattern = #"(?i)\d\s*(?:a\.?m\b|p\.?m\b)|\b\d{1,2}:\d{2}\b|\bnoon\b|\bmidnight\b"#

    private static func names(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}

/// Reads a plan typed as one sentence, the way people text it: "Pickup soccer 3-5PM Saturday at
/// Hutchinson Field Davis CA" → "Pickup Soccer", Saturday 3–5 PM, "Hutchinson Field, Davis, CA".
/// The on-device fallback for "Describe your plan" when Claude isn't available. Apple's detector finds
/// the date, the time range and street addresses; the place is what follows "at", "@" or "in the";
/// the title is what comes before all of that, minus filler like "let's" or "anyone want to".
enum PlanSentence {
    struct Reading: Equatable {
        var title = ""
        /// No short name stood out, so the title is only a guess for the host to check.
        var titleIsGuess = false
        var date: Date?
        var endDate: Date?
        /// False for a day with no time ("soccer saturday"): the detector picks noon, which is a guess.
        var hasTime = false
        var location = ""
        var cost = ""
        var category: ActivityCategory?
    }

    /// Stands in for each date, address or price taken out, so the rest splits into pieces around it.
    private static let gap = "\u{1F}"

    static func read(_ text: String, now: Date = .now) -> Reading {
        var reading = Reading()
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
        let ns = line as NSString
        var taken: [NSRange] = []
        var address = ""

        // Dates, time ranges ("3-5pm" comes with a duration) and street addresses.
        let types: NSTextCheckingResult.CheckingType = [.date, .address]
        let found = (try? NSDataDetector(types: types.rawValue))?
            .matches(in: line, range: NSRange(location: 0, length: ns.length)) ?? []
        for match in found {
            var range = match.range
            if match.resultType == .date, reading.date == nil, let date = match.date {
                // "Movie night friday 8pm": the detector counts "night" as part of the date, but it's the name's.
                let words = ns.substring(with: range).split(separator: " ", maxSplits: 1)
                if range.location > 0, words.count == 2, partsOfDay.contains(words[0].lowercased()) {
                    let skip = words[0].utf16.count + 1
                    range = NSRange(location: range.location + skip, length: range.length - skip)
                }
                let said = ns.substring(with: range)
                reading.hasTime = said.range(of: #"\d|noon|midnight|morning|afternoon|evening|night"#,
                                             options: [.regularExpression, .caseInsensitive]) != nil
                var start = date
                // "Boba at 4pm" typed at 6pm means tomorrow.
                if start < now, said.range(of: dayWords, options: [.regularExpression, .caseInsensitive]) == nil {
                    start = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
                }
                reading.date = start
                if match.duration > 0 { reading.endDate = start.addingTimeInterval(match.duration) }
            } else if match.resultType == .address, address.isEmpty {
                address = ns.substring(with: range)
            }
            taken.append(range)
        }

        // The price: "free", "$5", "it's $3".
        let prices = try? NSRegularExpression(
            pattern: #"(?i)(?:\b(?:it['’]?s|for|entry is|costs?)\s+)?(?:\bfree\b|\$\s*\d+(?:\.\d{2})?)"#)
        for match in prices?.matches(in: line, range: NSRange(location: 0, length: ns.length)) ?? [] {
            let said = ns.substring(with: match.range)
            if reading.cost.isEmpty {
                if let dollars = said.range(of: #"\$\s*\d+(?:\.\d{2})?"#, options: .regularExpression) {
                    reading.cost = said[dollars].replacingOccurrences(of: " ", with: "")
                } else {
                    reading.cost = "Free"
                }
            }
            taken.append(match.range)
        }

        // What's left, with a gap where each piece was taken out.
        var rest = ""
        var position = 0
        for range in taken.sorted(by: { $0.location < $1.location }) where range.location >= position {
            rest += ns.substring(with: NSRange(location: position, length: range.location - position)) + " \(gap) "
            position = range.location + range.length
        }
        rest += ns.substring(from: position)

        // The place: after "at", "@" or "in the …", up to the next gap, clause or joining word.
        var titlePart = rest
        let restNS = rest as NSString
        let markers = try? NSRegularExpression(pattern: #"(?:(?<=\s)|^)(?i:at)\s+|@\s*|(?<=\s)in\s+(?=the\s|[A-Z])"#)
        for marker in markers?.matches(in: rest, range: NSRange(location: 0, length: restNS.length)) ?? [] {
            let after = restNS.substring(from: marker.range.location + marker.range.length)
            let end = after.range(of: placeEnd, options: .regularExpression)?.lowerBound ?? after.endIndex
            let place = cleanPlace(String(after[..<end]))
            guard !place.isEmpty else { continue }
            reading.location = place
            let placeLength = after[..<end].utf16.count
            titlePart = restNS.replacingCharacters(
                in: NSRange(location: marker.range.location, length: marker.range.length + placeLength), with: " \(gap) ")
            break
        }
        if reading.location.isEmpty {
            reading.location = address
        } else if !address.isEmpty {
            reading.location = "\(reading.location), \(address)"
        }

        // The title: the first piece that still says something once the filler is gone.
        let pieces = titlePart.components(separatedBy: gap)
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",;!?()")) }
            .flatMap { $0.components(separatedBy: ". ") }
        if let title = pieces.lazy.map(cleanTitle).first(where: { !$0.isEmpty }) {
            let words = title.split(separator: " ").count
            reading.titleIsGuess = words > 6
            reading.title = titleCase(words > 6 ? FlyerScanner.shortTitle(title, limit: 40) : title)
        } else {
            reading.titleIsGuess = true
        }
        reading.category = category(in: reading.title) ?? category(in: line)
        return reading
    }

    private static let partsOfDay: Set = ["night", "morning", "afternoon", "evening"]
    /// Words that name the day, so a time already past today isn't moved to tomorrow.
    private static let dayWords = #"\b(?:today|tonight|tomorrow|mon|tue|wed|thu|fri|sat|sun|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)|\d{1,2}/\d{1,2}"#
    /// Where a place name stops: a gap, the end of a clause, or a joining word. Lowercase only, so a
    /// capitalized word inside a name doesn't end it.
    private static let placeEnd = "\u{1F}" + #"|[.!?;:)](?:\s|$)|\(|,\s+(?=[a-z])|\s[-–—]\s|\s(?:for|with|to|from|on|and|then|bring|if|so|but|starting|until|till|after|before|around|this|next)\s"#
    private static let leadingFiller = #"(?i)^(?:let['’]?s|let us|(?:any(?:one|body|1)|who['’]?s|who is|who) (?:wants? to|wanna|down(?: to| for)?|in for|free (?:to|for))|wanna|want to|i['’]?m|we['’]?re|i am|we are|i['’]?ll be|we['’]?ll be|hosting|having|throwing|organizing|join (?:us|me)(?: for| at)?|come (?:join us(?: for)?|to|for)|come|going to|gonna|go|get|grab|a|an|some|our|my)\b[\s,]*"#
    private static let trailingFiller = #"(?i)(?:\s+(?:at|on|from|this|next|in|the|for|and|to|around|starting|by|with|is|will be))+\s*$|[\s,.;:!?\-–—@]+$"#

    private static func cleanPlace(_ text: String) -> String {
        var place = text.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",.;:-–—")))
        if place.hasPrefix("the ") { place = String(place.dropFirst(4)) }
        guard place.rangeOfCharacter(from: .letters) != nil else { return "" }
        // "Hutchinson Field Davis CA" → "Hutchinson Field, Davis, CA".
        if !place.contains(","), let city = place.range(of: #"\s+[A-Z][a-z]+\s+[A-Z]{2}$"#, options: .regularExpression) {
            let parts = place[city].split(separator: " ")
            place = place[..<city.lowerBound] + ", \(parts[0]), \(parts[1])"
        }
        return FlyerScanner.shortTitle(place, limit: 60)
    }

    private static func cleanTitle(_ piece: String) -> String {
        var title = piece.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",.;:-–—@")))
        for pattern in [leadingFiller, trailingFiller] {
            while let range = title.range(of: pattern, options: .regularExpression), !range.isEmpty {
                title.removeSubrange(range)
                title = title.trimmingCharacters(in: .whitespaces)
            }
        }
        return title.rangeOfCharacter(from: .letters) == nil ? "" : title
    }

    /// "pickup soccer" → "Pickup Soccer". Words already capitalized (ECS, ARC, CoHo) stay as typed.
    private static func titleCase(_ title: String) -> String {
        let small: Set = ["a", "an", "the", "and", "or", "for", "of", "at", "in", "on", "to", "with", "vs"]
        return title.split(separator: " ").enumerated().map { index, word in
            if word.contains(where: \.isUppercase) || (index > 0 && small.contains(String(word))) { return String(word) }
            return word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    /// The category of the first word that names one ("boba run" is food & social, "morning run" is club sports),
    /// with the planner's word lists.
    private static func category(in text: String) -> ActivityCategory? {
        for word in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            if let match = KeywordParser.categoryWords.first(where: { $0.1.contains(String(word)) }) { return match.0 }
        }
        return nil
    }
}

/// What the host confirmed on the review screen.
struct FlyerFields {
    var title: String
    var date: Date
    var duration: Int?
    var location: FlyerLocation
    /// The map place explicitly picked in the review, if any.
    var place: Place? = nil
    var details: String
    var cost: String
    var category: ActivityCategory?
    var cover: UIImage?

    static func duration(from start: Date, to end: Date) -> Int? {
        let minutes = Int((end.timeIntervalSince(start) / 60).rounded())
        return minutes > 0 ? minutes : nil
    }

    /// The Host form has no organizer field, so the club goes at the top of the description
    /// ("Hosted by Davis Climbing Club."), unless the description already names it.
    static func details(_ details: String, organizer: String) -> String {
        let details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let organizer = organizer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !organizer.isEmpty, !details.localizedCaseInsensitiveContains(organizer) else { return details }
        let line = "Hosted by \(organizer)" + (organizer.hasSuffix(".") ? "" : ".")
        return details.isEmpty ? line : "\(line)\n\n\(details)"
    }
}

struct FlyerLocation: Codable, Equatable {
    var venue: String
    var address: String

    var query: String {
        let name = venue.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || detail.localizedCaseInsensitiveContains(name) { return detail }
        return detail.isEmpty ? name : "\(name), \(detail)"
    }

    func pinned(to match: Place) -> Place {
        var place = match
        let name = venue.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { place.name = name }
        if !detail.isEmpty { place.address = detail }
        return place
    }
}

struct FlyerReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let result: FlyerScanResult
    let onApply: (FlyerFields) -> Void
    @State private var title: String
    @State private var date: Date
    @State private var endDate: Date
    @State private var hasEndDate: Bool
    @State private var location: String
    @State private var address: String
    @State private var pickedPlace: Place?
    @State private var suggestions: [Place] = []
    @State private var details: String
    @State private var cost: String
    @State private var category: ActivityCategory?
    @State private var organizer: String
    @State private var confirmedDate = false
    /// The host changed the date or time, so a "not detected" date no longer needs pointing out.
    @State private var dateEdited = false
    @State private var useCover = true

    init(result: FlyerScanResult, onApply: @escaping (FlyerFields) -> Void) {
        self.result = result
        self.onApply = onApply
        _title = State(initialValue: result.title)
        let start = result.date ?? .now.addingTimeInterval(3600)
        _date = State(initialValue: start)
        _endDate = State(initialValue: result.endDate ?? start.addingTimeInterval(5400))
        _hasEndDate = State(initialValue: result.endDate != nil)
        _location = State(initialValue: result.location)
        _address = State(initialValue: result.address)
        _details = State(initialValue: result.details)
        _cost = State(initialValue: result.cost)
        _category = State(initialValue: result.category)
        _organizer = State(initialValue: result.organizer)
    }

    private var reviewedLocation: FlyerLocation { FlyerLocation(venue: location, address: address) }

    private func isMissing(_ field: String) -> Bool { result.missing.contains(field) }

    private func isBlank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // What wasn't detected and is still empty. Each highlight clears as soon as the host fills it in.
    private var needsTitle: Bool { isBlank(title) }
    private var needsCategory: Bool { category == nil }
    private var needsDate: Bool { (isMissing("date") || isMissing("time")) && !dateEdited && !confirmedDate }
    private var needsLocation: Bool { reviewedLocation.query.isEmpty }
    private var needsDetails: Bool { isBlank(details) }
    private var needsCost: Bool { isBlank(cost) }

    private var dateHelp: String? {
        if date <= .now { return "This date has already passed. Pick the right date and time." }
        guard needsDate else { return nil }
        if result.date == nil { return "We couldn't detect the date, please fill it in." }
        return isMissing("date") ? "We couldn't detect the date, please check it."
                                 : "We couldn't detect the time, please set it."
    }

    /// What still blocks "Apply details", in form order, so the host knows why it's greyed out.
    private var stillNeeded: [String] {
        var needed: [String] = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { needed.append("enter the event name") }
        if date <= .now { needed.append("pick a start time in the future") }
        if hasEndDate && FlyerFields.duration(from: date, to: endDate) == nil { needed.append("pick an end time after the start") }
        if !confirmedDate { needed.append("turn on \"I checked the date and time\"") }
        if reviewedLocation.query.isEmpty { needed.append("enter the location") }
        return needed
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let image = result.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .frame(maxWidth: .infinity)
                    }
                    Label(result.reader == .claude ? "Read by Claude" : "Read on your iPhone",
                          systemImage: result.reader == .claude ? "sparkles" : "iphone")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(result.reader == .claude ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(.secondary))
                    if let reason = result.fallbackReason {
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .symbolRenderingMode(.multicolor)
                    }
                    if !result.isEventFlyer {
                        Label(result.source == .text
                              ? "This doesn't sound like a plan. You can still fill in the details yourself."
                              : "This doesn't look like an event flyer, or the photo is too blurry to read. Cancel and try a clearer photo, or fill in the details yourself.",
                              systemImage: "questionmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    Text("Check the details. Fields outlined in orange weren't \(result.source == .text ? "in the description" : "on the flyer") or weren't clear, so fill them in before posting.")
                        .font(.subheadline)
                    if !stillNeeded.isEmpty {
                        Label("To apply: \(stillNeeded.joined(separator: ", ")).", systemImage: "info.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    TextField("Enter event name", text: $title)
                        .needsInput(needsTitle)
                } header: {
                    reviewHeader("Event name", missing: isMissing("title") && !needsTitle)
                } footer: {
                    notDetected(needsTitle)
                }
                Section {
                    Picker("Category", selection: $category) {
                        Text("Choose…").tag(ActivityCategory?.none)
                        ForEach(ActivityCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag(Optional($0)) }
                    }
                    .needsInput(needsCategory)
                } header: {
                    Text("Category")
                } footer: {
                    notDetected(needsCategory)
                }
                Section {
                    DatePicker("Starts", selection: $date, in: Date.now...)
                        .needsInput(dateHelp != nil)
                        .onChange(of: date) { confirmedDate = false; dateEdited = true }
                    Toggle("Set end time", isOn: $hasEndDate)
                        .onChange(of: hasEndDate) {
                            if hasEndDate && endDate <= date { endDate = date.addingTimeInterval(5400) }
                            confirmedDate = false
                        }
                    if hasEndDate {
                        DatePicker("Ends", selection: $endDate)
                            .onChange(of: endDate) { confirmedDate = false; dateEdited = true }
                    }
                    Toggle("I checked the date and time", isOn: $confirmedDate)
                } header: {
                    reviewHeader("Date and time", missing: (isMissing("date") || isMissing("time")) && dateHelp == nil && !confirmedDate)
                } footer: {
                    if let dateHelp { helper(dateHelp) }
                }
                Section {
                    TextField("Venue", text: $location)
                        .needsInput(needsLocation)
                    TextField("Address or room", text: $address)
                        .textContentType(.fullStreetAddress)
                        .needsInput(needsLocation)
                    if let pickedPlace {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pickedPlace.name).font(.subheadline.weight(.semibold))
                                if !pickedPlace.address.isEmpty {
                                    Text(pickedPlace.address).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(.green)
                        }
                        .accessibilityLabel("Pinned on the map: \(pickedPlace.name)")
                        Button("Clear map match") { self.pickedPlace = nil }
                    } else {
                        ForEach(suggestions.prefix(4)) { place in
                            Button {
                                pickedPlace = place
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name).foregroundStyle(.primary)
                                    if !place.address.isEmpty {
                                        Text(place.address).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        Text("Pick a map match here or in the Host form.")
                            .font(.caption)
                    }
                } header: {
                    reviewHeader("Location", missing: isMissing("location") && !needsLocation)
                } footer: {
                    notDetected(needsLocation)
                }
                .onChange(of: reviewedLocation) { pickedPlace = nil }
                .task(id: reviewedLocation.query) {
                    let query = reviewedLocation.query
                    suggestions = []
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    var found = await Place.search(query)
                    if found.isEmpty, !location.isEmpty, location != query, !Task.isCancelled {
                        found = await Place.search(location)
                    }
                    if !Task.isCancelled { suggestions = found }
                }
                Section {
                    TextField("Club or organization (optional)", text: $organizer)
                } header: {
                    Text("Hosted by")
                } footer: {
                    Text("Added to the top of the description.")
                }
                Section {
                    TextField("Description", text: $details, axis: .vertical)
                        .lineLimit(4...10)
                        .needsInput(needsDetails)
                } header: {
                    Text("Description")
                } footer: {
                    notDetected(needsDetails)
                }
                Section {
                    TextField("Enter cost or Free", text: $cost)
                        .needsInput(needsCost)
                } header: {
                    reviewHeader("Cost", missing: isMissing("cost") && !needsCost)
                } footer: {
                    notDetected(needsCost)
                }
                if result.image != nil {
                    Section {
                        Toggle("Use flyer as cover photo", isOn: $useCover)
                    }
                }
            }
            .navigationTitle(result.source == .text ? "Review plan" : "Review scanned flyer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply details") {
                        let duration = hasEndDate ? FlyerFields.duration(from: date, to: endDate) : nil
                        onApply(FlyerFields(title: title, date: date, duration: duration, location: reviewedLocation,
                                            place: pickedPlace.map(reviewedLocation.pinned(to:)),
                                            details: FlyerFields.details(details, organizer: organizer),
                                            cost: cost, category: category,
                                            cover: useCover ? result.image : nil))
                        dismiss()
                    }
                    .disabled(!stillNeeded.isEmpty)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder private func notDetected(_ show: Bool) -> some View {
        if show { helper("We couldn't detect this, please fill it in.") }
    }

    private func helper(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
    }

    /// Claude found a value but wasn't sure of it: worth a look, not empty.
    private func reviewHeader(_ text: String, missing: Bool) -> some View {
        HStack(spacing: 6) {
            Text(text)
            if missing {
                Label("Check this", systemImage: "exclamationmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.orange)
            }
        }
    }
}

private extension View {
    /// An orange outline on a review row that still needs the host's input.
    func needsInput(_ active: Bool) -> some View {
        listRowBackground(active ? RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.orange, lineWidth: 2))
            : nil)
    }
}

struct FlyerCameraView: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: FlyerCameraView
        init(parent: FlyerCameraView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.9) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
