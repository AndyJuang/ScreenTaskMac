// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ScreenCaptureKit
import ScreenTaskCore

@MainActor final class AppModel: ObservableObject {
    @Published var settings = Settings.load() { didSet { settings.save() } }
    @Published var password = ""
    @Published var rememberPassword = false
    @Published var addresses: [NetworkAddress] = []
    @Published var displays: [SCDisplay] = []
    @Published var running = false
    @Published var busy = false
    @Published var status = "準備分享"
    @Published var logs: [String] = []
    @Published var frameCount = 0
    private var initialized = false
    private var capture: Capture?
    private var server: HTTPServer?
    var url: String { "http://\(settings.address):\(settings.port)/" }
    func log(_ text: String) {
        status = text
        logs.append("\(Date().formatted(date: .omitted, time: .standard))  \(text)")
        if logs.count > 100 { logs.removeFirst(logs.count - 100) }
    }
    func initialize() async {
        guard !initialized else { return }; initialized = true
        refreshNetwork()
        // Query displays only after permission is already granted; first launch stays quiet.
        if CGPreflightScreenCaptureAccess() { await refreshDisplays() }
        // The install prompt is up or a relaunch from /Applications is under way. Autostarting now
        // would bind the port and capture from the bundle this release exists to move away from.
        guard !Relocator.relocating else {
            Relocator.resume = { [weak self] in Task { @MainActor in await self?.autoStart() } }
            return
        }
        await autoStart()
    }
    /// Autostart and minimize, once nothing is waiting on the install prompt.
    private func autoStart() async {
        if settings.autoStart {
            password = PasswordStore.load()
            await start()
        }
        if settings.startMinimized { NSApp.windows.first(where: { $0.title == "ScreenTask Mac" })?.miniaturize(nil) }
    }
    func refreshNetwork() {
        addresses = NetworkAddress.list()
        if !addresses.contains(where: { $0.address == settings.address }) { settings.address = addresses.first?.address ?? "127.0.0.1" }
    }
    func refreshDisplays() async {
        do {
            displays = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true).displays
            if !displays.contains(where: { $0.displayID == settings.displayID }) { settings.displayID = displays.first?.displayID ?? 0 }
        } catch { log("無法讀取螢幕，請在系統設定允許螢幕錄製。\(error.localizedDescription)") }
    }
    func start() async {
        guard !running, !busy else { return }
        busy = true; defer { busy = false }
        guard (1024...65535).contains(settings.port), (50...10000).contains(settings.interval), (10...100).contains(settings.quality), (640...7680).contains(settings.maxWidth) else {
            log("請檢查連接埠、更新間隔與畫質範圍。"); return
        }
        guard !settings.privateSession || (!settings.username.isEmpty && !settings.username.contains(":") && !password.isEmpty) else {
            log("私人分享需要帳號與密碼，帳號不可含冒號。"); return
        }
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            log("請允許螢幕錄製，再結束並重新開啟程式。"); return
        }
        await refreshDisplays()
        guard let display = displays.first(where: { $0.displayID == settings.displayID }),
              let address = addresses.first(where: { $0.address == settings.address }) else { log("找不到指定螢幕或網路介面，請重新整理。"); return }
        do {
            if rememberPassword && settings.privateSession { try PasswordStore.save(password) }
            let html = try Data(contentsOf: ViewerResource.url)
            let server = HTTPServer(address: address.address, mask: address.mask, publicAccess: settings.publicAccess,
                                    router: Router(html: html, username: settings.privateSession ? settings.username : nil, password: settings.privateSession ? password : nil),
                                    onFailure: { [weak self] error in Task { @MainActor in await self?.failed(error) } })
            self.server = server
            try await server.start(port: UInt16(settings.port))
            let capture = Capture(quality: settings.quality / 100, output: { [weak self, weak server] jpeg in
                server?.publish(jpeg)
                Task { @MainActor in self?.frameCount += 1 }
            }, failure: { [weak self] error in Task { @MainActor in await self?.failed(error) } })
            self.capture = capture
            frameCount = 0
            try await capture.start(display: display, interval: settings.interval, cursor: settings.cursor, maxWidth: settings.maxWidth)
            running = true; log("正在分享 · \(url)")
        } catch { await stop(); log("啟動失敗：\(error.localizedDescription)。若連接埠已被使用，請更換連接埠。") }
    }
    func failed(_ error: Error) async { await stop(); log("分享已中斷：\(error.localizedDescription)") }
    func stop() async {
        busy = true; defer { busy = false }
        server?.stop(); server = nil
        let old = capture; capture = nil
        await old?.stop()
        running = false; log("已停止分享")
    }
    func openPermissions() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    func openViewer() { if running, let value = URL(string: url) { NSWorkspace.shared.open(value) } }
    func copyURL() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url, forType: .string) }
}
