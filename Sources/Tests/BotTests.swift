import Foundation

func botTests() {
    let full = #"{"today":"2026-10-15","assignments":[],"recentlyDone":[],"sessions":[],"newField":{"x":1}}"#
    expect((try? JSONDecoder().decode(BotStudy.self, from: Data(full.utf8))) != nil, "bot: unknown fields are ignored")
    let thin = #"{"today":"2026-10-15"}"#
    let s = try? JSONDecoder().decode(BotStudy.self, from: Data(thin.utf8))
    expect(s?.assignments.isEmpty == true && s?.sessions.isEmpty == true, "bot: missing lists are empty")
    expect((try? JSONDecoder().decode(BotStudy.self, from: Data("[]".utf8))) == nil, "bot: non-object reply fails")
    let rich = #"{"today":"2026-10-16","exams":[{"id":"e1","course":{"id":"c","short":"Stats","title":"Statistics","aiPolicy":"banned"},"kind":"quiz","title":"Quiz 3","topic":null,"date":"2026-10-26","dateTo":null,"tentative":true,"notes":null}],"assignments":[{"id":"a","title":"HW","done":false,"details":"ch 3","dueNote":"in class","fromStudyAgent":true}]}"#
    let r = try? JSONDecoder().decode(BotStudy.self, from: Data(rich.utf8))
    expect(r?.exams?.first?.tentative == true && r?.exams?.first?.course?.aiPolicy == "banned" && r?.assignments.first?.details == "ch 3", "bot: exams and assignment details decode")
    expect(BotAPI.Err.unauthorized.message != BotAPI.Err.network.message && !BotAPI.Err.http(502).message.isEmpty, "bot: errors have distinct text")
    print("Bot tests OK")
}
