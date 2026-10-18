import Foundation

func dateTests() {
    expect(DateFmt.days(from: "2026-10-09", to: "2026-10-12") == 3, "date: plain span")
    expect(DateFmt.days(from: "2026-03-28", to: "2026-03-30") == 2, "date: across a DST change")
    expect(DateFmt.days(from: "2026-12-31", to: "2027-01-01") == 1, "date: year boundary")
    expect(DateFmt.days(from: "2026-10-12", to: "2026-10-09") == -3, "date: negative")
    expect(DateFmt.days(from: "x", to: "2026-10-09") == nil && DateFmt.days(from: "2026-10-09", to: "") == nil, "date: malformed is nil")
    expect(Deadlines.bucket("2026-10-16", today: "2026-10-09") == .week && Deadlines.bucket("2026-10-17", today: "2026-10-09") == .later, "date: week boundary is day 7")
    expect(DateFmt.today().count == 10 && DateFmt.clock(Date()).count == 5, "date: formats")
    print("Date tests OK")
}
