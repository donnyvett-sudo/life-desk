import Foundation

/// The bot's /food day: macros against targets and the meals of the day.
struct FoodDay: Decodable {
    struct Macros: Decodable, Equatable { var kcal: Double; var protein: Double; var fat: Double; var carbs: Double }
    struct Item: Decodable, Equatable, Identifiable { var name: String; var grams: Double; var kcal: Double
        var id: String { name + "\(grams)" } }
    struct Meal: Decodable, Identifiable, Equatable {
        var id: String; var time: String; var title: String
        var kcal: Double; var protein: Double; var fat: Double; var carbs: Double
        var items: [Item]; var status: String; var source: String?
    }
    var date: String
    var today: String
    var targets: Macros
    var totals: Macros
    var meals: [Meal]
}

struct FoodHistory: Decodable {
    struct Day: Decodable, Equatable, Identifiable { var date: String; var kcal: Double; var protein: Double; var meals: Int; var id: String { date } }
    var targets: FoodDay.Macros
    var series: [Day]
}

enum FoodLogic {
    /// 0...1+ share of a target; a missing target counts as 0.
    static func share(_ value: Double, of target: Double) -> Double { target > 0 ? value / target : 0 }

    /// "2,543 of 2,250 kcal" style label: the part that matters (remaining or over).
    static func remaining(_ t: FoodDay) -> (text: String, over: Bool) {
        let d = t.targets.kcal - t.totals.kcal
        return d >= 0 ? ("\(Int(d.rounded())) kcal left", false) : ("\(Int((-d).rounded())) kcal over", true)
    }

    static func selfTest() -> [String] {
        var f: [String] = []
        let j = Data(#"{"date":"2026-10-16","today":"2026-10-16","targets":{"kcal":2250,"protein":150,"fat":66,"carbs":262},"totals":{"kcal":2543,"protein":92,"fat":131,"carbs":255},"meals":[{"id":"m1","time":"12:15","title":"Canteen lunch","kcal":943,"protein":45,"fat":56,"carbs":58,"items":[{"name":"rice","grams":200,"kcal":260}],"status":"confirmed","source":"photo","confidence":0.8,"corrected":false}]}"#.utf8)
        guard let d = try? JSONDecoder().decode(FoodDay.self, from: j) else { return ["decode"] }
        if d.meals.count != 1 || d.meals[0].items.first?.name != "rice" { f.append("meals") }
        if remaining(d) != ("293 kcal over", true) { f.append("remaining \(remaining(d))") }
        if share(75, of: 150) != 0.5 || share(10, of: 0) != 0 { f.append("share") }
        return f
    }
}
