import Foundation
import Testing
import UIKit
@testable import Partner

struct ChatMuteTests {
    @Test func chatsSavedBeforeMutingExistedStillLoad() throws {
        let json = #"{"id":"\#(UUID().uuidString)","participantIDs":[],"messages":[],"unreadCount":2}"#
        let chat = try JSONDecoder().decode(Conversation.self, from: Data(json.utf8))
        #expect(chat.isMuted == nil)
        #expect(chat.muted == false)
        #expect(chat.unreadCount == 2)
    }

    @Test func muteSurvivesSaving() throws {
        var chat = Conversation(id: UUID(), activityID: nil, participantIDs: [], messages: [])
        chat.isMuted = true
        let decoded = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(chat))
        #expect(decoded.muted)
    }
}

@MainActor
struct CoverUploadTests {
    private func photo(_ size: CGSize, noisy: Bool) -> Data {
        UIGraphicsImageRenderer(size: size).image { context in
            for x in stride(from: 0, to: Int(size.width), by: noisy ? 4 : Int(size.width)) {
                for y in stride(from: 0, to: Int(size.height), by: noisy ? 4 : Int(size.height)) {
                    UIColor(hue: .random(in: 0...1), saturation: 1, brightness: .random(in: 0...1), alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: noisy ? 4 : Int(size.width), height: noisy ? 4 : Int(size.height)))
                }
            }
        }.pngData()!
    }

    @Test func coverIsAJPEGUnderTheServerLimit() throws {
        let jpeg = try #require(AppStore.coverJPEG(photo(CGSize(width: 1600, height: 900), noisy: true)))
        #expect(jpeg.starts(with: [0xFF, 0xD8, 0xFF]))
        #expect(jpeg.count <= 900 * 1024)
    }

    @Test func bigPhotosAreShrunkToCoverSize() throws {
        let jpeg = try #require(AppStore.coverJPEG(photo(CGSize(width: 4000, height: 3000), noisy: false)))
        let image = try #require(UIImage(data: jpeg))
        #expect(max(image.size.width * image.scale, image.size.height * image.scale) <= 1600)
        #expect(jpeg.count <= 900 * 1024)
    }

    @Test func posterCoversAreTallAndStillUpload() throws {
        let poster = try #require(UIImage(data: photo(CGSize(width: 1200, height: 1600), noisy: false))?
            .jpegData(compressionQuality: 0.8))
        #expect(CoverShape.isPoster(poster))
        let jpeg = try #require(AppStore.coverJPEG(poster))
        #expect(CoverShape.isPoster(jpeg))
        #expect(jpeg.count <= 900 * 1024)
        #expect(!CoverShape.isPoster(photo(CGSize(width: 1600, height: 900), noisy: false)))
        #expect(!CoverShape.isPoster(nil))
    }

    @Test func notAnImageGivesNothing() {
        #expect(AppStore.coverJPEG(Data("hello".utf8)) == nil)
    }
}

// MARK: - Draft eligibility (closing the Host form)

@Suite("Draft eligibility")
struct DraftEligibilityTests {
    private let start = PlanFormSnapshot(
        category: .social, title: "", date: Date(timeIntervalSince1970: 1_800_000_000), duration: 90,
        placeID: nil, suggestedLocation: "", capacity: 4, level: .anyone, requiresApproval: false,
        privateLocation: false, costIsFree: true, cost: "", details: "", coverPhotoData: nil,
        repeats: false, frequency: .weekly, occurrenceCount: 6, schedulePost: false,
        publishAt: Date(timeIntervalSince1970: 1_799_000_000)
    )

    private func worth(_ change: (inout PlanFormSnapshot) -> Void) -> Bool {
        var form = start
        change(&form)
        return DraftEligibility.isWorthSaving(form, comparedTo: start)
    }

    @Test func nothingEnteredIsNotWorthSaving() { #expect(!worth { _ in }) }
    @Test func titleOnly() { #expect(!worth { $0.title = "Board games night" }) }
    @Test func categoryOnly() { #expect(!worth { $0.category = .gaming }) }
    @Test func titleAndCategory() { #expect(!worth { $0.title = "Board games"; $0.category = .gaming }) }
    @Test func whitespaceDoesNotCount() { #expect(!worth { $0.title = "   "; $0.details = "  \n " }) }
    @Test func settingsAloneDoNotCount() {
        #expect(!worth { $0.capacity = 8; $0.duration = 60; $0.level = .beginner; $0.requiresApproval = true })
    }
    @Test func meaningfulDescription() {
        #expect(worth { $0.details = "Bring your favorite games, snacks provided by us." })
    }
    @Test func shortDescriptionAlone() { #expect(!worth { $0.details = "fun" }) }
    @Test func locationAndTime() {
        #expect(worth { $0.placeID = "Mishka's"; $0.date = start.date.addingTimeInterval(3600) })
    }
    @Test func photoAndTitle() { #expect(worth { $0.coverPhotoData = Data([1, 2, 3]); $0.title = "Picnic" }) }
    @Test func photoAlone() { #expect(!worth { $0.coverPhotoData = Data([1, 2, 3]) }) }
    @Test func severalDetails() {
        #expect(worth { $0.title = "Hike"; $0.date = start.date.addingTimeInterval(7200); $0.capacity = 10 })
    }
}
