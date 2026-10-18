import SwiftUI
import CoreImage.CIFilterBuiltins

/// Settings section: pair a new iPhone with a one-time code and manage paired devices.
struct PairingSection: View {
    @State private var code: Devices.Code?
    @State private var devices: [Devices.Device] = []
    @State private var busy = false
    @State private var message: String?
    @State private var now = Date()
    @State private var inviteLink: String?
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Section("iPhone") {
            if let c = code, c.expiresAt > now {
                HStack(alignment: .center, spacing: 16) {
                    if let qr = Self.qr(c.code) { Image(nsImage: qr).interpolation(.none).resizable().frame(width: 96, height: 96) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.code).font(.system(size: 28, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                        Text("Enter it in the Life app on your iPhone. Valid for \(Int(c.expiresAt.timeIntervalSince(now)) / 60 + 1) min, works once.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Pair the iPhone app with a one-time code instead of copying a token.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(busy ? "Working…" : "Show pairing code") { Task { await makeCode() } }.disabled(busy)
                Button("Refresh devices") { Task { await load() } }.disabled(busy)
            }
            HStack {
                Button("Invite a friend (web app)") { Task { await makeInvite() } }.disabled(busy)
            }
            if let l = inviteLink {
                Text(l).font(.caption).textSelection(.enabled)
                Text("Copied. One person, works once, valid for a few days. They open it on their phone and add it to the Home Screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message { Text(message).font(.caption).foregroundStyle(.orange) }
            ForEach(devices) { d in
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(d.name) · \(d.platform)")
                        Text(d.lastSeen.map { "last seen \(SyncInfo.relative($0))" } ?? "added " + (d.createdAt.map { SyncInfo.relative($0) } ?? "—"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Remove", role: .destructive) { Task { await remove(d) } }
                }
            }
        }
        .onReceive(tick) { now = $0 }
        .task { await load() }
    }

    private func makeCode() async {
        busy = true; message = nil; defer { busy = false }
        do { code = try await Devices.createCode(); await load() }
        catch BotAPI.Err.http(403) { message = "This token cannot pair devices: use a full-access token." }
        catch BotAPI.Err.http(let s) where s == 404 { message = "The server does not support pairing yet." }
        catch { message = (error as? BotAPI.Err)?.message ?? "Could not get a code." }
    }

    private func makeInvite() async {
        busy = true; message = nil; defer { busy = false }
        guard let r = try? await BotAPI.raw("POST", "/invites", body: Data("{}".utf8)) else { message = "No connection."; return }
        guard r.status == 200, let j = try? JSONSerialization.jsonObject(with: r.data) as? [String: Any], let link = j["link"] as? String else {
            message = r.status == 403 ? "This token cannot invite: use the owner's full-access token." : r.status == 404 ? "The server does not support invites yet." : "Could not make an invite."
            return
        }
        inviteLink = link
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(link, forType: .string)
    }

    private func load() async {
        if let list = try? await Devices.list() { devices = list }
    }

    private func remove(_ d: Devices.Device) async {
        do { try await Devices.remove(d.id); await load() } catch { message = "Could not remove the device." }
    }

    static func qr(_ text: String) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}
