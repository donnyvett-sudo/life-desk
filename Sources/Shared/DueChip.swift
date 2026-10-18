import SwiftUI

/// Due chip: "Overdue 3 d" (bad) / "Today", "Tomorrow" (accent) / "in 5 d"; "No date" when undated.
struct DueChip: View {
    let date: String?
    let today: String
    var body: some View {
        if let d = date.flatMap({ Deadlines.days(from: today, to: $0) }) {
            let l = Deadlines.dueLabel(d)
            Chip(text: l.text, tone: l.urgent == 2 ? .bad : l.urgent == 1 ? .accent : .neutral)
        } else {
            Chip(text: "No date")
        }
    }
}
