import SwiftUI
import Combine

@MainActor
final class FocusStyleStore: ObservableObject {
    static let shared = FocusStyleStore()
    @Published var style = FocusStyle.load() { didSet { style.save() } }
}
