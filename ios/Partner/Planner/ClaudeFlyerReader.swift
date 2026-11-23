import UIKit

/// Reads a flyer image with Claude through the team's server (`POST /api/flyers/read`, see docs/API.md).
/// The photo is shrunk and re-encoded first, which also drops its location metadata.
struct ClaudeFlyerReader {
    let baseURL: URL

    /// Claude reads images best around this size; bigger only costs upload time.
    static let maxPixels: CGFloat = 1568

    struct RequestBody: Encodable {
        var image: String          // base64 JPEG
        var mediaType: String
        var now: String
        var ocrText: String
    }

    struct Reading: Decodable, Equatable {
        var isEventFlyer: Bool
        var title: String
        var startTime: Date?
        var endTime: Date?
        var locationName: String
        var address: String
        var description: String
        var cost: String
        var category: String
        var missing: [String]
        /// The club or group hosting it, if printed. Newer servers only.
        var organizer: String? = nil
    }

    func read(_ image: CGImage, ocrText: String, now: Date = .now) async throws -> Reading {
        guard let jpeg = Self.uploadJPEG(image) else { throw CocoaError(.fileWriteUnknown) }
        let body = RequestBody(image: jpeg.base64EncodedString(), mediaType: "image/jpeg",
                               now: ClaudePlanner.localTime.format(now), ocrText: String(ocrText.prefix(4000)))
        return try await EventServer.post("api/flyers/read", body: body, baseURL: baseURL, timeout: 45)
    }

    /// A fresh JPEG at most `maxPixels` on the long side. Re-encoding keeps no EXIF/GPS data.
    static func uploadJPEG(_ image: CGImage) -> Data? {
        let size = CGSize(width: image.width, height: image.height)
        let scale = min(1, maxPixels / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}

extension ClaudeFlyerReader.Reading {
    private enum CodingKeys: String, CodingKey {
        case isEventFlyer, title, startTime, endTime, locationName, address, description, cost, category, missing, organizer
    }

    /// Forgiving on purpose: any field may be missing or `null`, and a time Claude wrote oddly
    /// (no UTC offset, or only a day) is still read. One bad field never throws away the rest.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String {
            (try? c.decodeIfPresent(String.self, forKey: key))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        func time(_ key: CodingKeys) -> FlyerTime {
            FlyerTime.parse(try? c.decodeIfPresent(String.self, forKey: key))
        }
        let start = time(.startTime)
        let end = time(.endTime)
        var missing = (try? c.decodeIfPresent([String].self, forKey: .missing)) ?? []
        if start.date == nil {
            missing += ["date", "time"]
        } else if !start.hasTime {
            missing.append("time")
        }
        self.init(
            isEventFlyer: (try? c.decodeIfPresent(Bool.self, forKey: .isEventFlyer)) ?? true,
            title: text(.title),
            startTime: start.date,
            // A bare day, or an end that isn't after the start, isn't an end time.
            endTime: end.hasTime ? end.date.flatMap { e in start.date.flatMap { e > $0 ? e : nil } } : nil,
            locationName: text(.locationName), address: text(.address), description: text(.description),
            cost: text(.cost), category: text(.category), missing: missing.uniqued(),
            organizer: text(.organizer).isEmpty ? nil : text(.organizer)
        )
    }

    func result(image: UIImage) -> FlyerScanResult {
        FlyerScanResult(
            title: title, date: startTime, endDate: endTime,
            location: locationName, address: address,
            details: description, cost: cost,
            category: ActivityCategory(rawValue: category),
            organizer: organizer ?? "",
            missing: missing, isEventFlyer: isEventFlyer, reader: .claude, image: image
        )
    }
}

/// A time from the server's JSON, read the way the flyer reader needs it.
struct FlyerTime: Equatable {
    var date: Date?
    /// False when only a day was given: the time is a placeholder (noon) for the host to set.
    var hasTime = false

    /// ISO-8601 with an offset (what the server sends), with or without fractional seconds.
    /// Without an offset the time is the phone's own; a bare "2026-11-23" is that day at noon.
    static func parse(_ string: String?, timeZone: TimeZone = .current) -> FlyerTime {
        guard let string = string?.trimmingCharacters(in: .whitespaces), !string.isEmpty else { return FlyerTime() }
        if let date = (try? Date(string, strategy: .iso8601))
            ?? (try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))) {
            return FlyerTime(date: date, hasTime: true)
        }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = timeZone
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            local.dateFormat = format
            if let date = local.date(from: string) { return FlyerTime(date: date, hasTime: true) }
        }
        local.dateFormat = "yyyy-MM-dd"
        if let day = local.date(from: string) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            return FlyerTime(date: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day), hasTime: false)
        }
        return FlyerTime()
    }
}

/// Reads a typed plan description ("pickup soccer sat 3-5pm at the ARC fields, free") with Claude
/// through the team's server. The text counterpart of `ClaudeFlyerReader`: same fields, same review screen.
/// Experimental on the server: it answers 404 unless started with EXPERIMENTS=event_parse (see docs/API.md).
struct ClaudeTextReader {
    let baseURL: URL

    static let path = "api/experimental/events/parse"
    /// The server refuses longer text.
    static let maxCharacters = 1000

    struct RequestBody: Encodable {
        var text: String
        var now: String
    }

    /// The flyer reader's fields, except `is_event` instead of `is_event_flyer`.
    struct Reading: Decodable, Equatable {
        var isEvent: Bool
        var title: String
        var startTime: Date?
        var endTime: Date?
        var locationName: String
        var address: String
        var description: String
        var cost: String
        var category: String
        var missing: [String]
    }

    func read(_ text: String, now: Date = .now) async throws -> Reading {
        let body = RequestBody(text: String(text.prefix(Self.maxCharacters)), now: ClaudePlanner.localTime.format(now))
        return try await EventServer.post(Self.path, body: body, baseURL: baseURL, timeout: 45)
    }
}

extension ClaudeTextReader.Reading {
    var result: FlyerScanResult {
        FlyerScanResult(
            title: title, date: startTime, endDate: endTime,
            location: locationName, address: address,
            details: description, cost: cost,
            category: ActivityCategory(rawValue: category),
            missing: missing, isEventFlyer: isEvent, reader: .claude, source: .text, image: nil
        )
    }
}
