import Foundation

func bridgeTests() {
    func ok(_ d: [String: Any]) -> BridgeRequest? { BridgeRequest.parse(d) }
    expect(ok(["method": "get", "path": "/today"]) == BridgeRequest(method: "GET", path: "/today", body: nil), "bridge: plain GET")
    expect(ok(["method": "POST", "path": "/supplements/12", "body": ["name": "x"]])?.body != nil, "bridge: JSON body kept")
    expect(ok(["method": "GET", "path": "/finance?month=2026-10&cur=USD"]) != nil, "bridge: query string")
    expect(ok(["method": "PATCH", "path": "/habits/3/log", "body": NSNull()])?.body == nil, "bridge: null body")
    for bad in ["today", "//evil.example/x", "/../x", "/a/../b", "https://evil.example", "/x@evil", "/x\\y", "/x#frag", "/a b", "/a\nb",
                "/\u{202E}x", String(repeating: "a", count: 2000),
                "/a/%2e%2e/b", "/a%2Fb", "/a%5Cb", "/auth/pairing-code", "/auth", "/AUTH/pair"] {
        expect(ok(["method": "GET", "path": bad]) == nil, "bridge: refuses path \(bad.prefix(20).debugDescription)")
    }
    for m in ["TRACE", "CONNECT", "", "get /x"] { expect(ok(["method": m, "path": "/x"]) == nil, "bridge: refuses method \(m)") }
    expect(ok(["method": "POST", "path": "/x", "body": String(repeating: "a", count: 1_100_000)]) == nil, "bridge: refuses a huge body")
    expect(BridgeRequest.parse("nonsense") == nil && BridgeRequest.parse(["method": "GET"]) == nil, "bridge: refuses malformed input")
    print("Bridge tests OK")
}
