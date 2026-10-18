import Foundation

/// The bot's /finance month: totals, categories, accounts and transactions (only what the phone shows).
struct FinanceMonth: Decodable {
    struct Account: Decodable, Identifiable, Equatable {
        var id: String; var title: String; var currency: String
        var balance: Double; var balanceDisplay: Double
        var isDefault: Bool; var isArchived: Bool; var inTotal: Bool
    }
    struct Category: Decodable, Identifiable, Equatable { var id: String; var kind: String; var title: String }
    struct Spend: Decodable, Identifiable, Equatable { var id: String?; var title: String; var amount: Double
        var key: String { id ?? title }
        var identity: String { key }
    }
    struct Tx: Decodable, Identifiable, Equatable {
        var id: String; var kind: String; var amount: Double; var currency: String
        var amountDisplay: Double; var note: String?; var categoryId: String?; var accountId: String?
        var date: String; var time: String?
    }
    var month: String
    var currency: String
    var prev: String
    var next: String?
    var expense: Double
    var income: Double
    var byCategory: [Spend]
    var accounts: [Account]
    var total: Double
    var categories: [Category]
    var transactions: [Tx]
}

enum FinanceLogic {
    static let currencies = ["CNY", "KZT", "USD"]
    static func symbol(_ c: String) -> String { ["CNY": "¥", "KZT": "₸", "USD": "$"][c] ?? c }

    /// "1,931 ¥" (no decimals above 100, two below, like the Mini App).
    static func money(_ v: Double, _ currency: String, signed: Bool = false) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = abs(v) >= 100 ? 0 : 2
        f.minimumFractionDigits = 0
        let s = f.string(from: NSNumber(value: abs(v))) ?? "\(abs(v))"
        let sign = v < 0 ? "−" : (signed && v > 0 ? "+" : "")
        return "\(sign)\(s) \(symbol(currency))"
    }

    /// Share of the month's spending, 0...1.
    static func share(_ amount: Double, of total: Double) -> Double { total > 0 ? min(1, max(0, amount / total)) : 0 }

    /// Parses what a person types: "35", "35.5", "1 200,50" → Double; nil for empty, zero, negative or absurd values.
    static func parseAmount(_ raw: String) -> Double? {
        let cleaned = raw.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
        guard let v = Double(cleaned), v > 0, v < 1e9 else { return nil }
        return (v * 100).rounded() / 100
    }

    /// Transactions grouped by date, newest day first, order inside a day kept.
    static func byDay(_ t: [FinanceMonth.Tx]) -> [(date: String, items: [FinanceMonth.Tx])] {
        let g = Dictionary(grouping: t, by: \.date)
        return g.keys.sorted(by: >).map { ($0, g[$0] ?? []) }
    }

    static func selfTest() -> [String] {
        var f: [String] = []
        if money(1000, "CNY") != "1,000 ¥" || money(-12.5, "USD") != "−12.5 $" || money(3000, "CNY", signed: true) != "+3,000 ¥" { f.append("money \(money(1000, "CNY")) \(money(-12.5, "USD"))") }
        if parseAmount("1 200,50") != 1200.5 || parseAmount("0") != nil || parseAmount("-3") != nil || parseAmount("abc") != nil || parseAmount("35") != 35 { f.append("parseAmount") }
        if share(25, of: 100) != 0.25 || share(5, of: 0) != 0 || share(200, of: 100) != 1 { f.append("share") }
        let j = Data(#"{"month":"2026-10","currency":"CNY","prev":"2026-09","next":null,"expense":1000,"income":3000,"byCategory":[{"id":"c1","title":"Cafe","amount":600},{"id":null,"title":"Other","amount":400}],"accounts":[{"id":"a1","title":"Card","currency":"CNY","balance":100,"balanceDisplay":100,"isDefault":true,"isArchived":false,"inTotal":true}],"total":100,"categories":[{"id":"c1","kind":"expense","title":"Cafe"}],"transactions":[{"id":"t1","kind":"expense","amount":35,"currency":"CNY","amountDisplay":35,"note":"lunch","categoryId":"c1","accountId":"a1","date":"2026-10-15","time":"12:30"},{"id":"t2","kind":"income","amount":100,"currency":"CNY","amountDisplay":100,"note":null,"categoryId":null,"accountId":null,"date":"2026-10-14","time":null}]}"#.utf8)
        guard let m = try? JSONDecoder().decode(FinanceMonth.self, from: j) else { return ["decode"] }
        if m.byCategory.count != 2 || m.accounts.first?.title != "Card" || m.next != nil { f.append("fields") }
        if byDay(m.transactions).map(\.date) != ["2026-10-15", "2026-10-14"] { f.append("byDay") }
        return f
    }
}
