// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Darwin

/// Gatekeeper runs a quarantined bundle through App Translocation: the app executes from a
/// read-only nullfs shadow mount under /private/var/folders/.../AppTranslocation/ and the process
/// stays untrusted. On 2026-09-05, macOS 26.6.2 (25G83) panicked while a translocated build of
/// this app was serving screen frames — `vnode_vid` on a NULL vnode, reached through the
/// AppleSystemPolicy and Sandbox MAC hooks that run whenever a new inbound network flow is
/// evaluated. Installing into /Applications takes the app off the shadow mount, so it offers to
/// copy itself there and relaunch before it starts listening.
@MainActor enum Relocator {
    private static let declinedKey = "relocationDeclined"
    /// Set by the app model: startup that was held back while the prompt was up, run if it is abandoned.
    static var resume: (() -> Void)?

    /// The app stays where it is, so whatever startup was waiting on the prompt must still happen.
    private static func abandon() {
        relocating = false
        let pending = resume; resume = nil; pending?()
    }
    private static let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)

    /// True from the moment the prompt appears until it is declined, so an autostarting instance does
    /// not bind the port and start capturing behind a modal the user may leave open.
    private(set) static var relocating = false

    static var isTranslocated: Bool { Bundle.main.bundleURL.path.contains("/AppTranslocation/") }

    /// True when the running bundle is a real .app outside any Applications folder. A `swift run`
    /// build has no .app wrapper and is left alone.
    static var canInstall: Bool {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else { return false }
        let path = bundle.path
        return !path.hasPrefix("/Applications/") && !path.hasPrefix("\(NSHomeDirectory())/Applications/")
    }

    /// Offers to install into /Applications and relaunch from there. `force` comes from the button
    /// in the control window and ignores a previous "do not ask again".
    @discardableResult
    static func offerInstall(force: Bool = false) -> Bool {
        guard canInstall, !relocating, !CommandLine.arguments.contains("--no-relocate") else { return false }
        guard force || !UserDefaults.standard.bool(forKey: declinedKey) else { return false }
        relocating = true
        guard confirmInstall() else { abandon(); return false }

        let source = Bundle.main.bundleURL
        let destination = applications.appendingPathComponent(source.lastPathComponent)
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) {
            switch resolveExisting() {
            case .replace:
                // Never delete outright: the copy the user already has goes to the Trash.
                do {
                    var trashed: NSURL?
                    try manager.trashItem(at: destination, resultingItemURL: &trashed)
                } catch { abandon(); report(error); return false }
            case .useExisting:
                relaunch(at: destination); return true
            case .cancel:
                abandon(); return false
            }
        }
        do { try manager.copyItem(at: source, to: destination) } catch { abandon(); report(error); return false }
        clearQuarantine(destination)
        relaunch(at: destination)
        return true
    }

    private static func confirmInstall() -> Bool {
        let alert = NSAlert()
        alert.messageText = "安裝到「應用程式」？"
        alert.informativeText = isTranslocated
            ? """
              目前執行的是 macOS 為隔離檔案建立的唯讀副本（App Translocation）。在這個狀態下分享螢幕，曾在 macOS 26.6.2 觸發核心崩潰並重新開機。

              按下後會複製一份到「應用程式」並從那裡重新開啟，原本的那一份會保留。移動位置後，需要在「系統設定 → 隱私權與安全性 → 螢幕錄製」重新允許一次。
              """
            : """
              目前不是從「應用程式」執行。安裝過去可以避免 macOS 之後以唯讀隔離副本執行，權限與更新也比較穩定。

              按下後會複製一份到「應用程式」並從那裡重新開啟，原本的那一份會保留。移動位置後，需要在「系統設定 → 隱私權與安全性 → 螢幕錄製」重新允許一次。
              """
        alert.addButton(withTitle: "安裝並重新開啟")
        alert.addButton(withTitle: "先不要")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "不要再提醒我"
        guard alert.runModal() == .alertFirstButtonReturn else {
            if alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: declinedKey) }
            return false
        }
        return true
    }

    private enum Existing { case replace, useExisting, cancel }

    private static func resolveExisting() -> Existing {
        let alert = NSAlert()
        alert.messageText = "「應用程式」裡已經有 ScreenTask Mac"
        alert.informativeText = "可以把現有的那一份移到垃圾桶換成這一份，或直接改開現有的版本。"
        alert.addButton(withTitle: "取代並移到垃圾桶")
        alert.addButton(withTitle: "改開現有版本")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .replace
        case .alertSecondButtonReturn: return .useExisting
        default: return .cancel
        }
    }

    /// A copy made from the quarantined original inherits com.apple.quarantine, which is exactly
    /// what sends the next launch back through App Translocation.
    private static func clearQuarantine(_ url: URL) {
        var paths = [url.path]
        if let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case let item as URL in walker { paths.append(item.path) }
        }
        for path in paths {
            _ = path.withCString { target in
                "com.apple.quarantine".withCString { name in removexattr(target, name, XATTR_NOFOLLOW) }
            }
        }
    }

    private static func relaunch(at destination: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, error in
            Task { @MainActor in
                guard error == nil else { abandon(); report(error!); return }
                NSApp.terminate(nil)
            }
        }
    }

    private static func report(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "無法安裝到「應用程式」"
        alert.informativeText = "\(error.localizedDescription)\n\n請手動把 ScreenTask Mac 拖到「應用程式」再開啟。若這台電腦不是管理者帳號，改放到個人的「應用程式」資料夾也可以。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
