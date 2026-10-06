import Foundation
import Testing

@testable import LudeumCore

@Suite struct JSONValueTests {
    @Test func aRecordIsReadWithEveryKindOfValueKept() throws {
        let json =
            #"{"id": 1070, "name": "Super Mario World", "rating": 94.5, "remake": false, "bundle": true, "parent": null,"#
            + #" "genres": [{"id": 8, "name": "Platform"}], "tags": [1, 2.5, "x", null, true]}"#

        let record = try JSONValue.decode(Data(json.utf8))

        #expect(
            record
                == .object([
                    "id": .number(1070), "name": .string("Super Mario World"), "rating": .number(94.5), "remake": .bool(false),
                    "bundle": .bool(true), "parent": .null,
                    "genres": .array([.object(["id": .number(8), "name": .string("Platform")])]),
                    "tags": .array([.number(1), .number(2.5), .string("x"), .null, .bool(true)]),
                ]))
    }

    @Test func aValueOnItsOwnIsRead() throws {
        #expect(try JSONValue.decode(Data("null".utf8)) == .null)
        #expect(try JSONValue.decode(Data("[1, 2]".utf8)) == .array([.number(1), .number(2)]))
        #expect(try JSONValue.decode(Data("0".utf8)) == .number(0))
        #expect(try JSONValue.decode(Data("1".utf8)) == .number(1))
    }

    @Test func whatIsWrittenIsReadBackTheSame() throws {
        let record = JSONValue.object(["name": .string("Einhänder \"1\""), "ids": .array([.number(1), .bool(false), .null])])

        #expect(try JSONValue.decode(try record.encoded()) == record)
    }

    @Test func somethingThatIsntJSONIsRefused() {
        #expect(throws: (any Error).self) { try JSONValue.decode(Data("<html>".utf8)) }
        #expect(throws: (any Error).self) { try JSONValue.decode(Data()) }
    }
}
