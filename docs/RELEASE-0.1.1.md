ScreenTask Mac 首個 Apple Silicon 版本，適用 macOS 13 以上。

下載 `ScreenTaskMac-0.1.1-arm64.zip`，解壓縮後將 App 拖到「應用程式」。首次開啟請允許螢幕錄製及區域網路連線，再重新開啟程式。

包含瀏覽器觀看、私人帳密、多螢幕來源選擇、JPEG 品質與間隔、游標、選單列、自動開始／最小化、全螢幕及斷線重連。

已驗證 arm64 建置／簽章、核心回歸測試、搬移安裝包後的真實 HTTP 整合測試，以及本機真實螢幕傳送、暫停／繼續、全螢幕與停止。

發行包使用 ad-hoc 簽署，尚未經 Apple 公證。若 Gatekeeper 阻擋，確認來源後使用系統設定的「仍要打開」。HTTP 未加密，請在可信任網路使用。第二台實體裝置及多實體螢幕測試尚未執行，詳見 docs/VALIDATION.md。

GPL-3.0-or-later。致謝 EslaMx7/ScreenTask 原始專案；本專案是獨立 macOS 移植。
