import Testing

@testable import LudeumCore

@Suite struct PlaythroughTests {
    let h: LudeumHarness
    let game: GameID

    init() throws {
        h = try LudeumHarness()
        game = try h.addGame()
    }

    private func date(_ text: String) -> PartialDate { PartialDate(text)! }

    @Test func keepsEveryFieldAcrossARelaunch() throws {
        let draft = PlaythroughDraft(
            start: date("2024-03"), end: date("2024-04-02"), outcome: .finished,
            notes: "100% items", version: "(Japan, USA)", playedVia: "OpenEmu")
        let id = try h.journal.addPlaythrough(game, draft)
        try h.reopen()

        #expect(try h.journal.playthroughs(game) == [Playthrough(id: id, draft)])
    }

    @Test func everyFieldButTheStartIsOptional() throws {
        _ = try h.journal.addPlaythrough(game, PlaythroughDraft(start: date("2026")))

        #expect(try h.journal.playthroughs(game).count == 1)
    }

    @Test func refusesAnEndBeforeTheStart() throws {
        #expect(throws: LudeumError.endBeforeStart) {
            try h.journal.addPlaythrough(game, PlaythroughDraft(start: date("2024-03"), end: date("2023"), outcome: .finished))
        }
        #expect(throws: LudeumError.endBeforeStart) {
            try h.journal.addPlaythrough(game, PlaythroughDraft(start: date("2024-03-10"), end: date("2024-03-09"), outcome: .finished))
        }
    }

    @Test func allowsALessPreciseDateThatContainsTheOther() throws {
        _ = try h.journal.addPlaythrough(game, PlaythroughDraft(start: date("2024-03"), end: date("2024"), outcome: .finished))
        _ = try h.journal.addPlaythrough(game, PlaythroughDraft(start: date("2024"), end: date("2024-01"), outcome: .finished))

        #expect(try h.journal.playthroughs(game).count == 2)
    }

    @Test func canBeEditedAndDeleted() throws {
        let id = try h.journal.addPlaythrough(game, PlaythroughDraft(start: date("2026-09")))
        let finished = PlaythroughDraft(start: date("2026-09"), end: date("2026-10"), outcome: .finished)

        try h.journal.updatePlaythrough(id, finished)
        #expect(try h.journal.playthroughs(game) == [Playthrough(id: id, finished)])

        try h.journal.deletePlaythrough(id)
        #expect(try h.journal.playthroughs(game).isEmpty)
    }
}
