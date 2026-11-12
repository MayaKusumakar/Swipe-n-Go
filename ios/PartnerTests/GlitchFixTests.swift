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

    @Test func notAnImageGivesNothing() {
        #expect(AppStore.coverJPEG(Data("hello".utf8)) == nil)
    }
}
