import SwiftUI

/// The one place that turns an `AppRoute` into "which tab, which part, which sheet". Cards, Feed messages, notifications
/// and widgets all call `Navigator.shared.go(...)`; the screens read their state from here.
@MainActor
final class Navigator: ObservableObject {
    static let shared = Navigator()

    enum Sheet: Identifiable, Hashable {
        case entry, cards, promises, account, focus(String?), exam(String)
        var id: String {
            switch self {
            case .entry: "entry"
            case .cards: "cards"
            case .promises: "promises"
            case .account: "account"
            case .focus(let c): "focus-\(c ?? "")"
            case .exam(let e): "exam-\(e)"
            }
        }
    }

    @Published var tab: RootView.TabID = .today
    @Published var studyPart: AppRoute.StudyPart = .deadlines
    @Published var lifePart: AppRoute.LifePart = .sleep
    /// Course pushed on the Study stack (nil = the list).
    @Published var courseID: String?
    @Published var sheet: Sheet?

    func go(_ route: AppRoute) {
        switch route {
        case .today: tab = .today
        case .feed: tab = .feed
        case .study(let p): tab = .study; studyPart = p; courseID = nil
        case .course(let id): tab = .study; studyPart = .courses; courseID = id
        case .exam(let id): tab = .study; studyPart = .exams; sheet = .exam(id)
        case .life(let p): tab = .life; lifePart = p
        case .focus(let c): sheet = .focus(c)
        case .cards: sheet = .cards
        case .promises: sheet = .promises
        case .account: sheet = .account
        }
    }
}

extension View {
    /// Makes any view a link to somewhere else in the app (a card on Today, a row, a chart).
    func linksTo(_ route: AppRoute) -> some View {
        Button { Navigator.shared.go(route) } label: { self.contentShape(Rectangle()) }.buttonStyle(.plain)
    }
}
