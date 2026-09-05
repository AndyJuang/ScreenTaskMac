// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import AppKit
import ScreenTaskCore

/// Offers the move to /Applications once AppKit is up, before the app starts listening.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = MainActor.assumeIsolated { Relocator.offerInstall() }
    }
}

@main struct ScreenTaskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    init() {
        if CommandLine.arguments.contains("--smoke-server") { SmokeServer.run() }
    }
    var body: some Scene {
        Window("ScreenTask Mac", id: "main") {
            ContentView(model: model).task { await model.initialize() }
        }.defaultSize(width: 660, height: 760)
        MenuBarExtra(model.running ? "正在分享螢幕" : "ScreenTask Mac", systemImage: model.running ? "rectangle.on.rectangle.circle.fill" : "rectangle.on.rectangle") {
            MenuContent(model: model)
        }
    }
}
struct MenuContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.status)
        Button("顯示控制視窗") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true); NSApp.windows.first(where: { $0.title == "ScreenTask Mac" })?.deminiaturize(nil) }
        Button(model.running ? "停止分享" : "開始分享") { Task { if model.running { await model.stop() } else { await model.start() } } }.disabled(model.busy)
        Button("複製觀看網址") { model.copyURL() }.disabled(!model.running)
        Divider()
        Button("結束 ScreenTask Mac") { Task { await model.stop(); NSApp.terminate(nil) } }.keyboardShortcut("q")
    }
}
struct ContentView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.on.rectangle").font(.system(size: 32)).foregroundStyle(.teal)
                VStack(alignment: .leading) {
                    Text("ScreenTask Mac").font(.largeTitle.bold())
                    Text("同一個網路，打開瀏覽器就能看。") .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Apple Silicon").font(.caption).padding(7).background(.quaternary, in: Capsule())
            }
            Form {
                Section("分享來源") {
                    Picker("螢幕", selection: $model.settings.displayID) {
                        if model.displays.isEmpty { Text("請先允許螢幕錄製").tag(UInt32(0)) }
                        ForEach(model.displays, id: \.displayID) { display in
                            Text("螢幕 \(display.displayID) · \(display.width) × \(display.height)").tag(display.displayID)
                        }
                    }
                    Picker("網路介面", selection: $model.settings.address) {
                        ForEach(model.addresses) { item in Text("\(item.name) · \(item.address)").tag(item.address) }
                    }
                    TextField("連接埠（1024–65535）", value: $model.settings.port, format: .number.grouping(.never))
                    HStack {
                        Button("重新整理") { model.refreshNetwork(); Task { await model.refreshDisplays() } }
                        Button("螢幕錄製權限") { model.openPermissions() }
                    }
                }
                Section("畫面") {
                    TextField("擷取間隔（50–10000 毫秒）", value: $model.settings.interval, format: .number.grouping(.never))
                    HStack { Text("JPEG 品質"); Slider(value: $model.settings.quality, in: 10...100, step: 1); Text("\(Int(model.settings.quality))%") }
                    Picker("最大寬度", selection: $model.settings.maxWidth) {
                        Text("1280 px · 省頻寬").tag(1280)
                        Text("1920 px · 建議").tag(1920)
                        Text("3840 px · 高解析度").tag(3840)
                        Text("原始尺寸（最高 7680 px）").tag(7680)
                    }
                    Toggle("顯示滑鼠游標", isOn: $model.settings.cursor)
                }
                if Relocator.canInstall {
                    Section("安裝位置") {
                        Text(Relocator.isTranslocated
                             ? "目前執行的是 macOS 的唯讀隔離副本（App Translocation），建議安裝到「應用程式」再使用。"
                             : "目前不是從「應用程式」執行，建議安裝到「應用程式」再使用。")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("安裝到「應用程式」並重新開啟") { Relocator.offerInstall(force: true) }
                    }
                }
                Section("存取與啟動") {
                    Toggle("私人分享（帳號與密碼）", isOn: $model.settings.privateSession)
                    if model.settings.privateSession {
                        TextField("帳號", text: $model.settings.username)
                        SecureField("密碼", text: $model.password)
                        HStack {
                            Toggle("開始分享時存入鑰匙圈", isOn: $model.rememberPassword)
                            Button("讀取已存密碼") { model.password = PasswordStore.load() }
                        }
                        Text("HTTP Basic 帳密與畫面未加密，僅供可信任的網路使用。").font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("允許其他子網路連線", isOn: $model.settings.publicAccess)
                    Toggle("開啟程式時自動開始分享", isOn: $model.settings.autoStart)
                    Toggle("開啟程式時最小化", isOn: $model.settings.startMinimized)
                }
            }.formStyle(.grouped).disabled(model.running || model.busy)
            HStack {
                Circle().fill(model.running ? Color.green : Color.secondary).frame(width: 8, height: 8)
                Text(model.status).font(.callout).textSelection(.enabled)
                Spacer()
                if model.running { Text("\(model.frameCount) 畫格").font(.caption).monospacedDigit() }
            }
            HStack {
                Button(model.running ? "停止分享" : "開始分享", systemImage: model.running ? "stop.fill" : "play.fill") {
                    Task { if model.running { await model.stop() } else { await model.start() } }
                }.buttonStyle(.borderedProminent).tint(model.running ? .red : .teal).disabled(model.busy)
                Button("複製網址") { model.copyURL() }.disabled(!model.running)
                Button("開啟觀看頁") { model.openViewer() }.disabled(!model.running)
                Spacer()
                Button("版本與更新") { NSWorkspace.shared.open(URL(string: "https://github.com/AndyJuang/ScreenTaskMac/releases")!) }
            }
            DisclosureGroup("執行紀錄") {
                ScrollView { Text(model.logs.joined(separator: "\n")).font(.system(.caption, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.frame(height: 80)
            }
        }.padding(22).frame(minWidth: 620, minHeight: 720)
    }
}

enum SmokeServer {
    /// Explicit test-only mode: serves an artificial JPEG, never captures a screen.
    static func run() -> Never {
        let args = CommandLine.arguments
        let port = args.firstIndex(of: "--port").flatMap { $0 + 1 < args.count ? UInt16(args[$0 + 1]) : nil } ?? 17070
        let html = (try? Data(contentsOf: ViewerResource.url)) ?? Data()
        let privateMode = args.contains("--private")
        let server = HTTPServer(address: "127.0.0.1", mask: "255.0.0.0", publicAccess: false, router: Router(html: html, username: privateMode ? "tester" : nil, password: privateMode ? "test-only" : nil))
        // Two visibly different frames, so a viewer test can tell a live stream from a stuck image.
        let frames = [NSColor(deviceRed: 0.2, green: 0.7, blue: 0.6, alpha: 1), NSColor(deviceRed: 0.9, green: 0.4, blue: 0.1, alpha: 1)].map { color -> Data in
            let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 24, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            for y in 0..<24 { for x in 0..<32 { image.setColor(color, atX: x, y: y) } }
            return image.representation(using: .jpeg, properties: [:])!
        }
        server.publish(frames[0])
        // Republish so the multipart stream emits successive parts, as a live capture would.
        let ticker = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "ScreenTask.smoke"))
        var tick = 0
        ticker.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        ticker.setEventHandler { tick += 1; server.publish(frames[tick % frames.count]) }
        ticker.resume()
        Task {
            do { try await server.start(port: port); print("SMOKE READY") }
            catch { fputs("Smoke listener failed\n", stderr); exit(1) }
        }
        withExtendedLifetime((server, ticker)) { dispatchMain() }
    }
}
