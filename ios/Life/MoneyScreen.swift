import SwiftUI
import Charts

/// Money: the month at a glance, where it went, accounts, transactions, and a fast way to add an expense.
struct MoneyScreen: View {
    @State private var month: FinanceMonth?
    @State private var monthKey: String?
    @State private var currency = UserDefaults.standard.string(forKey: "money.currency") ?? "CNY"
    @AppStorage("money.hidden") private var hidden = false
    @State private var error: String?
    @State private var adding = false
    @State private var scrubDay: Date?
    @ScaledMetric(relativeTo: .caption) private var catRow: CGFloat = 32

    var body: some View {
        PageView(title: L("Money"), summary: month.map { Loc.monthTitle($0.month) }, trailing: {
            HStack(spacing: 6) {
                TodayChip()
                Button { hidden.toggle() } label: { Image(systemName: hidden ? "eye.slash" : "eye") }
                    .buttonStyle(QuietButton()).accessibilityLabel(hidden ? L("Show amounts") : L("Hide amounts"))
                Button { adding = true } label: { Label("Add", systemImage: "plus") }.buttonStyle(QuietButton())
            }
        }) {
            VStack(alignment: .leading, spacing: 20) {
                if let error { ErrorBanner(text: error) { self.error = nil } }
                Picker("", selection: $currency) { ForEach(FinanceLogic.currencies, id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                if let m = month { content(m) } else if error == nil { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            }
        }
        .refreshable { await load() }
        .task(id: "\(monthKey ?? "")|\(currency)") { UserDefaults.standard.set(currency, forKey: "money.currency"); await load() }
        .sheet(isPresented: $adding) {
            if let m = month { AddExpenseSheet(month: m, currency: currency) { Task { await load() } } }
        }
    }

    private func load() async {
        var q = "?currency=\(currency)"
        if let k = monthKey { q += "&month=\(k)" }
        let r: (status: Int, data: Data)
        do { r = try await BotAPI.raw("GET", "/finance\(q)") }
        catch is CancellationError { return }
        catch { self.error = L("No connection."); return }
        guard r.status == 200 else { error = L("Could not load money (\(r.status))."); return }
        guard let m = try? JSONDecoder().decode(FinanceMonth.self, from: r.data) else { error = L("The money data could not be read."); return }
        month = m; error = nil
    }

    private func amount(_ v: Double, signed: Bool = false) -> String { hidden ? "•••" : FinanceLogic.money(v, currency, signed: signed) }

    @ViewBuilder private func content(_ m: FinanceMonth) -> some View {
        HStack {
            Button { monthKey = m.prev } label: { Image(systemName: "chevron.left").frame(width: Touch.minSize, height: Touch.minSize) }.accessibilityLabel("Previous month")
            Spacer()
            Text(Loc.monthTitle(m.month)).font(.rowTitle).foregroundStyle(Theme.text)
            Spacer()
            Button { monthKey = m.next } label: { Image(systemName: "chevron.right").frame(width: Touch.minSize, height: Touch.minSize) }.disabled(m.next == nil).accessibilityLabel("Next month")
        }
        .padding(.horizontal, 4).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))

        HStack(alignment: .top, spacing: 12) {
            Stat(value: amount(m.expense), label: L("Expenses"))
            Stat(value: amount(m.income), label: L("Income"))
            Stat(value: amount(m.income - m.expense, signed: true), label: L("Net"), tone: m.income - m.expense >= 0 ? .good : .bad)
        }
        Section2(title: L("In accounts")) {
            Group2 { Rows(items: m.accounts.filter { !$0.isArchived }) { a in
                HStack {
                    Text(a.title).font(.rowTitle).foregroundStyle(Theme.text)
                    Spacer()
                    Text(hidden ? "•••" : FinanceLogic.money(a.balanceDisplay, currency)).font(.rowTitle).monospacedDigit().foregroundStyle(Theme.text)
                }.padding(.horizontal, 14).padding(.vertical, 10)
            } }
            Text("Total \(amount(m.total))").font(.meta).foregroundStyle(Theme.muted)
        }
        Section2(title: L("Where it went")) {
            if m.byCategory.isEmpty {
                Group2 { EmptyState(icon: "creditcard", title: L("No expenses this month")) }
            } else {
                categories(m)
            }
        }
        if !m.transactions.isEmpty { Section2(title: L("Spending by day")) { daily(m) } }
        Section2(title: L("Transactions"), count: m.transactions.isEmpty ? nil : m.transactions.count) {
            ForEach(FinanceLogic.byDay(m.transactions), id: \.date) { day in
                VStack(alignment: .leading, spacing: 6) {
                    Text(day.date).font(.chip).foregroundStyle(Theme.muted)
                    Group2 { Rows(items: day.items) { t in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.note?.isEmpty == false ? t.note! : (m.categories.first { $0.id == t.categoryId }?.title ?? "—")).font(.rowTitle).foregroundStyle(Theme.text).lineLimit(2)
                                if let c = m.categories.first(where: { $0.id == t.categoryId }) { Text(c.title).font(.meta).foregroundStyle(Theme.muted) }
                            }
                            Spacer()
                            Text(hidden ? "•••" : FinanceLogic.money(t.kind == "income" ? t.amount : -t.amount, t.currency, signed: true))
                                .font(.rowTitle).monospacedDigit().foregroundStyle(t.kind == "income" ? Theme.good : Theme.text)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10).accessibilityElement(children: .combine)
                        .contextMenu { Button("Delete", role: .destructive) { Task { await delete(t) } } }
                    } }
                }
            }
        }
    }

    /// The month's categories as horizontal bars, biggest first, the amount at the end of each bar.
    private func categories(_ m: FinanceMonth) -> some View {
        let cats = m.byCategory.sorted { $0.amount > $1.amount }
        let top = cats.first?.amount ?? 0
        return Chart {
            ForEach(cats, id: \.identity) { c in
                BarMark(x: .value("Amount", c.amount), y: .value("Category", c.title))
                    .foregroundStyle(Theme.money).cornerRadius(3)
                    .annotation(position: .trailing, spacing: 6) {
                        Text(amount(c.amount)).font(.chip).monospacedDigit().foregroundStyle(Theme.muted)
                    }
                    .accessibilityLabel(c.title)
                    .accessibilityValue(hidden ? L("Hidden") : "\(FinanceLogic.money(c.amount, currency)), \(Int((FinanceLogic.share(c.amount, of: m.expense) * 100).rounded()))%")
            }
        }
        .chartXScale(domain: 0...max(top * 1.3, 1))   // room for the amount labels
        .chartXAxis(.hidden)
        .chartYAxis { AxisMarks { _ in AxisValueLabel().font(.meta).foregroundStyle(Theme.text) } }
        .frame(height: CGFloat(cats.count) * catRow + 8)
    }

    /// Expenses per calendar day of the month; a finger on the chart shows that day's total.
    @ViewBuilder private func daily(_ m: FinanceMonth) -> some View {
        let days = Dictionary(grouping: m.transactions.filter { $0.kind == "expense" }, by: \.date)
            .compactMap { iso, txs in ChartFmt.date(iso).map { DaySpend(date: $0, total: txs.reduce(0) { $0 + $1.amountDisplay }) } }
            .sorted { $0.date < $1.date }
        let start = ChartFmt.date(m.month + "-01")
        let end = start.flatMap { Calendar.current.date(byAdding: .month, value: 1, to: $0) }
        let picked = scrubDay.flatMap { s in days.first { Calendar.current.isDate($0.date, inSameDayAs: s) } }
        Chart {
            ForEach(days) { d in
                BarMark(x: .value("Day", d.date, unit: .day), y: .value("Spent", d.total))
                    .foregroundStyle(Theme.money.opacity(picked == nil || picked == d ? 1 : 0.45)).cornerRadius(2)
                    .accessibilityLabel(ChartFmt.dayMonth(d.date))
                    .accessibilityValue(hidden ? L("Hidden") : FinanceLogic.money(d.total, currency))
            }
            if let p = picked {
                RuleMark(x: .value("Day", p.date, unit: .day)).foregroundStyle(Theme.muted.opacity(0.35))
                    .annotation(position: .top, spacing: 0, overflowResolution: .inside) {
                        ChartCallout(value: amount(p.total), caption: ChartFmt.dayMonth(p.date))
                    }
            }
        }
        .chartXScale(domain: (start ?? Date())...(end ?? Date()))
        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in
            AxisGridLine().foregroundStyle(Theme.line); AxisValueLabel(format: .dateTime.day()).font(.chip).foregroundStyle(Theme.muted) } }
        .chartYAxis(hidden ? .hidden : .automatic)
        .chartXSelection(value: $scrubDay)
        .frame(height: 160)
    }

    private struct DaySpend: Identifiable, Equatable { let date: Date; let total: Double; var id: Date { date } }

    private func delete(_ t: FinanceMonth.Tx) async {
        if let r = try? await BotAPI.raw("DELETE", "/transactions/\(t.id)"), r.status == 200 {
            Toasts.shared.show(L("Deleted"))
            await load()
        } else { error = L("Could not delete.") }
    }
}

/// A big amount, a category, a note: three taps to log an expense.
struct AddExpenseSheet: View {
    let month: FinanceMonth
    let currency: String
    var onSaved: () -> Void
    @State private var text = ""
    @State private var cur: String
    @State private var categoryId: String?
    @State private var note = ""
    @State private var accountId: String?
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    init(month: FinanceMonth, currency: String, onSaved: @escaping () -> Void) {
        self.month = month; self.currency = currency; self.onSaved = onSaved
        _cur = State(initialValue: currency)
        _accountId = State(initialValue: month.accounts.first(where: { $0.isDefault })?.id)
    }

    private var expenseCategories: [FinanceMonth.Category] { month.categories.filter { $0.kind == "expense" } }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("0", text: $text).keyboardType(.decimalPad).focused($focused)
                    .font(.system(size: 54, weight: .semibold, design: .rounded)).monospacedDigit().multilineTextAlignment(.center)
                    .padding(.vertical, 8).accessibilityLabel("Amount")
                Picker("", selection: $cur) { ForEach(FinanceLogic.currencies, id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                FlowChips { ForEach(expenseCategories) { c in FilterChip(title: c.title, on: categoryId == c.id) { categoryId = categoryId == c.id ? nil : c.id } } }
                TextField("Note (optional)", text: $note).padding(12).background(Theme.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                if month.accounts.filter({ !$0.isArchived }).count > 1 {
                    Picker("money.account", selection: $accountId) {
                        ForEach(month.accounts.filter { !$0.isArchived }) { Text($0.title).tag(Optional($0.id)) }
                    }
                }
                if let error { Text(error).font(.callout).foregroundStyle(.red) }
                Button(saving ? L("Saving…") : L("Save expense")) { Task { await save() } }
                    .buttonStyle(PrimaryButton()).frame(maxWidth: .infinity).disabled(saving || FinanceLogic.parseAmount(text) == nil)
                Spacer()
            }
            .padding(20)
            .navigationTitle("New expense").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { focused = true }
        }
        .presentationDetents([.large])
    }

    private func save() async {
        guard let amount = FinanceLogic.parseAmount(text) else { return }
        saving = true; error = nil; defer { saving = false }
        var body: [String: Any] = ["kind": "expense", "amount": amount, "currency": cur, "note": note.trimmingCharacters(in: .whitespacesAndNewlines)]
        if let categoryId { body["categoryId"] = categoryId }
        if let accountId { body["accountId"] = accountId }
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let r = try? await BotAPI.raw("POST", "/transactions", body: data) else { error = L("No connection."); return }
        if r.status == 200 { Toasts.shared.show(L("Saved \(FinanceLogic.money(amount, cur))")); onSaved(); dismiss() }
        else { error = L("The server refused it (\(r.status)).") }
    }
}
