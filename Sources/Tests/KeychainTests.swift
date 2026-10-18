import Foundation

func keychainTests() {
    let tok = String(repeating: "a", count: 48)
    let other = String(repeating: "b", count: 48)
    var stored: [String] = []
    // stable signature: Keychain wins; file is imported once when the Keychain is empty
    expect(Keychain.resolve(stable: true, file: { other }, keychain: { tok }, store: { stored.append($0) }) == tok && stored.isEmpty,
           "keychain: stable signature prefers the Keychain")
    expect(Keychain.resolve(stable: true, file: { other }, keychain: { nil }, store: { stored.append($0) }) == other && stored == [other],
           "keychain: file token is imported into the Keychain")
    expect(Keychain.resolve(stable: true, file: { nil }, keychain: { nil }, store: { _ in expect(false, "nothing to store") }) == nil, "keychain: nothing found")
    // ad-hoc signature: file first (no password prompts), Keychain only as fallback, nothing is written
    stored = []
    expect(Keychain.resolve(stable: false, file: { other }, keychain: { tok }, store: { stored.append($0) }) == other && stored.isEmpty,
           "keychain: ad-hoc build reads the file first")
    expect(Keychain.resolve(stable: false, file: { nil }, keychain: { tok }, store: { _ in }) == tok, "keychain: ad-hoc build falls back to the Keychain")
    // short or blank values are not tokens
    expect(Keychain.resolve(stable: false, file: { "  short \n" }, keychain: { "" }, store: { _ in }) == nil, "keychain: short values are ignored")
    print("Keychain tests OK")
}
