# Validation

## Environment

- 2026-09-05, arm64 macOS host, Apple Swift 6.3.3 Command Line Tools.
- Deployment target: macOS 13. Other macOS versions and M-series generations have not all been physically tested.

## Automated verification

- Five regression groups: routing / frame readiness; Basic authentication on every route including malformed credentials; malformed and duplicate HTTP headers; HEAD / Content-Length / no-store; actual IPv4 subnet restriction with positive and negative controls.
- Release app: arm64 Mach-O, Info.plist validation, deep strict ad-hoc code-signature validation, ZIP with SHA-256 checksum.
- Designed icon source is committed as a 1254 × 1254 RGBA PNG. The build creates all macOS 16–1024 px representations, packages `AppIcon.icns`, and verifies the icon file plus `CFBundleIconFile` metadata before signing.
- Real loopback integration: app copied to a temporary installation path, synthetic JPEG response, public/private modes, 48 requests over 12 concurrent workers per mode, HEAD, forbidden paths, unsupported methods, oversized/malformed headers, process termination closes listener.
- Synthetic mode does not invoke screen capture.

## Interactive verification

- Native app opened and displayed source, network, quality, access, startup settings and status.
- User explicitly authorized live screen-capture testing on loopback.
- ScreenCaptureKit produced real frames; browser displayed the Mac screen at http://127.0.0.1:7070/.
- Pause / resume and fullscreen / exit worked in the in-app Chromium browser.
- Stop closed the listener and triggered reconnect UI. An image hidden-style conflict discovered here was fixed before release.

## Remaining coverage limits

- No second physical LAN device was available. Actual Wi-Fi/router isolation, macOS firewall prompts and Safari/iOS fullscreen behavior require testing on the target network/device.
- Only one physical display was attached; multi-display selection uses ScreenCaptureKit's display list but switching among multiple attached monitors was not exercised.
- Keychain persistence and automatic startup/minimization are implemented, but were not enabled on this user's machine during the test.
- No claim of measured maximum viewer capacity or video-call-grade latency. It is JPEG polling intended for presentations, not audio/video streaming.
- No Apple Developer ID certificate or notarization has been used.
