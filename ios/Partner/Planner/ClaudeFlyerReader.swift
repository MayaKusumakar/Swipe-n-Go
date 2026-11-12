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
    func result(image: UIImage) -> FlyerScanResult {
        let place = [locationName, address].filter { !$0.isEmpty }
        return FlyerScanResult(
            title: title, date: startTime, endDate: endTime,
            location: place.count == 2 && !address.localizedCaseInsensitiveContains(locationName)
                ? "\(locationName), \(address)" : (place.first ?? ""),
            details: description, cost: cost,
            category: ActivityCategory(rawValue: category),
            missing: missing, isEventFlyer: isEventFlyer, reader: .claude, image: image
        )
    }
}
