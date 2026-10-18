import Foundation

/// Fails the whole test run with a message; shared by main.swift and the per-area test files.
func expect(_ ok: Bool, _ msg: String) { if !ok { print("FAIL: \(msg)"); exit(1) } }
