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
        #expect(result.location == "ARC Climbing Wall, ARC, UC Davis")
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
        #expect(result.location == "Coffee House")      // address already includes the venue
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
