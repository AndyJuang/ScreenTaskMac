# ScreenTask Mac

**讓 Apple Silicon Mac 在區域網路分享螢幕，觀看者只需瀏覽器。**

以 [EslaMx7/ScreenTask](https://github.com/EslaMx7/ScreenTask) Windows 版為功能參考的獨立 macOS 移植。使用 SwiftUI、ScreenCaptureKit、Network.framework，無第三方套件、無雲端帳號、分享時不需網際網路。

## 下載與使用

1. 到 [Releases](https://github.com/AndyJuang/ScreenTaskMac/releases) 下載 `ScreenTaskMac-0.1.0-arm64.zip`。
2. 解壓縮，將 **ScreenTask Mac.app** 拖到「應用程式」。適用 **M 系列處理器、macOS 13 Ventura 以上**。
3. 開啟程式；首次使用請在「系統設定 → 隱私權與安全性 → 螢幕錄製」（較新系統稱「螢幕與系統音訊錄製」）允許 ScreenTask Mac，再結束並重新開啟。若出現區域網路或防火牆提示，請允許連入。
4. 選擇螢幕及 Wi-Fi／乙太網路 IP，按「開始分享」。不要選 `127.0.0.1` 給其他裝置使用。
5. 將觀看網址交給同網路的裝置，例如 `http://192.168.1.10:7070/`。分享者按「停止分享」就會關閉服務。

目前發行包為 **ad-hoc 簽署，尚未經 Apple Developer ID 簽署與公證**。下載後若 Gatekeeper 阻擋，請確認來源後，在「系統設定 → 隱私權與安全性」選擇「仍要打開」。不需要關閉整台電腦的安全機制。也可以自行從原始程式碼建置。

## 功能

- Wi-Fi／乙太網路離線分享，手機、平板與桌面瀏覽器觀看。
- 多螢幕選擇（每次分享一個完整螢幕）、滑鼠游標、JPEG 品質與擷取間隔。
- 指定 IPv4 介面與連接埠；預設只接受所選介面同一子網路的來源。
- 私人模式使用 HTTP Basic 帳密驗證，涵蓋觀看頁與所有圖片端點。
- 觀看端暫停／繼續、全螢幕、符合視窗／原始大小、更新間隔、斷線重連。
- 選單列控制、開啟程式時自動分享／最小化、複製網址、執行紀錄。
- 一般設定保存於 UserDefaults；密碼僅在勾選後，於開始分享時存入 macOS 鑰匙圈。未保存的密碼不寫入磁碟。
- 可同時有多個觀看者，沒有授權人數限制；頻寬與硬體效能仍有限。

完整對照與平台差異見 [功能對照表](docs/FEATURES.md)。本程式分享畫面，不含音訊、遠端操控、AirPlay 或網際網路穿透。

## 網路與隱私

HTTP 畫面與 Basic 帳密**未加密**，適合可信任的區域網路；私人模式不是 TLS。若需跨網路使用，請透過受信任 VPN。預設不開放其他子網路；「允許其他子網路連線」只放寬來源檢查，不會設定路由器、連接埠轉送或防火牆。請勿把服務直接暴露於網際網路。

畫面只留在記憶體，不寫入圖片檔或上傳雲端。每個請求回傳最新 JPEG；慢速觀看者不會累積歷史畫面。HTTP 接收標頭上限 16 KiB、每條連線上限 10 秒、同時處理上限 256 條連線，超量會重試。這是資源保護，並非保證「無限」人數。瀏覽器可能保留已看過的畫面或自行截圖；停止分享無法回收接收者已有的內容。

## 從原始程式碼建置

只需要 Apple Command Line Tools（Swift 5.9 以上），不需要額外套件或完整 Xcode：

```sh
xcode-select --install
git clone https://github.com/AndyJuang/ScreenTaskMac.git
cd ScreenTaskMac
bash scripts/build-app.sh
open "dist/ScreenTask Mac.app"
```

安裝包位於 `dist/`。建置腳本固定產生 arm64，最低部署版本為 macOS 13。其他架構不在本版本支援範圍。

## 測試

```sh
swift run --disable-sandbox ScreenTaskCoreTests
bash scripts/build-app.sh
python3 scripts/smoke-test.py
```

回歸測試不依賴 XCTest，因此只有 Command Line Tools 也能執行。HTTP 整合測試啟動真正的 loopback 服務、以人工 JPEG 驗證公開／私人模式、多請求、HEAD、錯誤路徑及惡意標頭；**測試模式不擷取螢幕**。真實螢幕授權與跨裝置測試另見 [驗證紀錄](docs/VALIDATION.md)。

## 架構

- `ScreenTaskCore`：HTTP 解析、驗證、固定路由、子網路檢查與 Network.framework listener。
- `ScreenTaskMac`：原生介面、鑰匙圈、網路介面列舉、ScreenCaptureKit 擷取與 JPEG 編碼。
- `Resources/index.html`：所有樣式與程式均內嵌的離線觀看頁。

## 授權與致謝

Copyright © 2026 AndyJuang. 採 **GPL-3.0-or-later**，詳見 [LICENSE](LICENSE)。

功能參考 ScreenTask，感謝原作者 Eslam Hamouda、Wagih ElBedeawi 及社群貢獻者。原始專案 README 聲明 GPL v3 或更新版本。本移植重新撰寫 Swift 與網頁程式，未使用上游 Logo、Bootstrap 或 Windows 程式碼；不代表上游官方 macOS 發行版。參考版本與來源見 [NOTICE](NOTICE)。
