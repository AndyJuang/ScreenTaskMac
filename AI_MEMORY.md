# ScreenTask Mac project memory

- Independent native macOS implementation inspired by EslaMx7/ScreenTask, GPL-3.0-or-later.
- Target: Apple Silicon, macOS 13+, Swift 5.9+; no external runtime dependencies.
- SwiftUI UI, ScreenCaptureKit screen capture, CoreImage JPEG encoding, Network.framework HTTP.
- Viewers poll immutable in-memory JPEG; no microphone/audio/remote control/cloud service.
- Default network scope: selected IPv4 interface and its subnet. Private mode protects every route with HTTP Basic (not encrypted).
- Store ordinary settings in UserDefaults; save passwords only on explicit opt-in to Keychain.
- Build: bash scripts/build-app.sh. Tests: swift run --disable-sandbox ScreenTaskCoreTests; python3 scripts/smoke-test.py.
- Resource bundles belong under Contents/Resources for code signing. ViewerResource locates installed resources without relying on the development checkout.
- Test mode --smoke-server serves synthetic frames on loopback, never captures the user's screen.
- Public repository: https://github.com/AndyJuang/ScreenTaskMac
- v0.1.2 adds the committed designed app icon source at Assets/AppIcon-Source.png and packages a complete AppIcon.icns.
- v0.1.2 uses ad-hoc signing, no Developer ID/notarization. Do not describe as notarized.
