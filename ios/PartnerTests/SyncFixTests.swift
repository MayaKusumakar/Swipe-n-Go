import Foundation
import Testing
@testable import Partner

/// Decoding of the new server replies (the server's side is covered by backend/tests).
struct AccountSyncTests {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    @Test func profileNameChosenOnAnotherDevice() throws {
        let json = #"{"id":"1","email":"ak@ucdavis.edu","name":"AK","picture_url":null,"display_name":"AK"}"#
        let user = try decoder.decode(EventServer.SignedInUser.self, from: Data(json.utf8))
        #expect(user.displayName == "AK")
    }

    @Test func olderServersWithoutDisplayNameStillDecode() throws {
        let json = #"{"id":"1","email":"ak@ucdavis.edu","name":"Anant"}"#
        let user = try decoder.decode(EventServer.SignedInUser.self, from: Data(json.utf8))
        #expect(user.displayName == nil)
        #expect(user.name == "Anant")
    }
}

struct FlyerPlaceTests {
    @Test func reviewCanCarryAPickedPlace() {
        let place = Place.presets[0]
        let fields = FlyerFields(title: "Run", date: .now, endDate: nil, location: place.name, place: place,
                                 details: "", cost: "", category: nil, cover: nil)
        #expect(fields.place == place)
    }
}
