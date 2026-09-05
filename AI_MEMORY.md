# ScreenTask Mac project memory

- Independent native macOS implementation inspired by EslaMx7/ScreenTask, GPL-3.0-or-later.
- Target: Apple Silicon, macOS 13+, Swift 5.9+; no external runtime dependencies.
- SwiftUI UI, ScreenCaptureKit screen capture, CoreImage JPEG encoding, Network.framework HTTP.
- Viewers hold one persistent connection: `/stream.mjpg` is multipart/x-mixed-replace, other requests are keep-alive. Polling per frame is only the fallback for browsers that cannot stream. No microphone/audio/remote control/cloud service.
- Why persistent connections: one connection per frame drove the kernel's per-flow network policy hooks continuously and preceded a macOS 26.6.2 kernel panic. Do not reintroduce Connection: close per frame.
- A dying multipart stream fires no error event on an <img> in Chromium/WebKit, so the viewer detects a stopped sharer with a 3-second HEAD heartbeat. Firefox canvas drawImage of that <img> returns its first frame, so test liveness with rendered screenshots.
- Default network scope: selected IPv4 interface and its subnet. Private mode protects every route with HTTP Basic (not encrypted).
- Store ordinary settings in UserDefaults; save passwords only on explicit opt-in to Keychain.
- Build: bash scripts/build-app.sh. Tests: swift run --disable-sandbox ScreenTaskCoreTests; python3 scripts/smoke-test.py.
- Resource bundles belong under Contents/Resources for code signing. ViewerResource locates installed resources without relying on the development checkout.
- Test mode --smoke-server serves two synthetic frames alternately on loopback, never captures the user's screen; SmokeServer.run() never returns, so the relocation prompt cannot appear in tests.
- Relocator offers to install into /Applications because App Translocation runs quarantined copies from a read-only shadow mount. Keep the offer before the server starts listening.
- Optional viewer test: scripts/viewer-test.py drives Chromium/WebKit/Firefox through Playwright (dev-only, skips when absent). SCREENTASK_VIEWER_ENGINES narrows the engines.
- Public repository: https://github.com/AndyJuang/ScreenTaskMac
- v0.1.2 adds the committed designed app icon source at Assets/AppIcon-Source.png and packages a complete AppIcon.icns.
- Releases use ad-hoc signing, no Developer ID/notarization. Do not describe as notarized. scripts/build-app.sh has an unexercised Developer ID path behind SCREENTASK_SIGN_IDENTITY and SCREENTASK_NOTARY_PROFILE.
- 0.1.3 is prepared in the working tree: persistent connections, install-to-Applications, optional notarization path. Its interactive install flow (GATES G10) is still unverified.
