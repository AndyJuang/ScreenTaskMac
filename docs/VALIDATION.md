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

## 0.1.3: persistent connections and install location

- Background: on 2026-09-05 this Mac (macOS 26.6.2, build 25G83) kernel-panicked while a quarantined, App-Translocated build was serving frames. The panic was a `vnode_vid` call on a NULL vnode inside the AppleSystemPolicy and Sandbox MAC hooks, which run for each new inbound network flow of the process. The old viewer opened one connection per frame, so it drove those hooks continuously.
- Connection churn, measured with `netstat -an` TIME_WAIT counts after 20 s of one Chromium viewer against the same synthetic server: 0.1.2 build 140 closed connections, 0.1.3 build 0-1. Asserted in `scripts/viewer-test.py`.
- Concurrent sockets per viewer, measured server-side: 2 in every engine (the stream plus the connection its 3-second HEAD heartbeat rides on). The 256-connection table is therefore about 128 viewers.
- Core regression tests grew to 7 groups: keep-alive framing (`Connection: keep-alive` with `Content-Length`), the `/stream.mjpg` route, multipart part framing, and authentication now also covering the stream route.
- Loopback integration adds: three sequential requests over one socket with no leftover bytes, a multipart stream carrying three or more JPEG parts on one connection with no `Content-Length`, and `Connection: close` still closing.
- Viewer behaviour verified in Chromium, WebKit and Firefox with `scripts/viewer-test.py`, against the real app in `--smoke-server` mode: stream starts and renders changing frames, the interval field is disabled while streaming, pause releases the stream connection and four pause/resume cycles end with fewer open sockets than they started with (2 to 1 in all three engines), a stopped sharer is reported within a few seconds and the viewer reconnects by itself when the sharer returns, and a browser that cannot stream falls back to per-frame polling. All three engines passed on 2026-09-05, twice in a row.
- Two regressions were found and fixed by that test before release: a dying multipart stream fires no `error` event on the `<img>` in Chromium or WebKit, so a stopped sharer used to leave a frozen last frame and never reconnect (now detected by a 3-second HEAD heartbeat); and a reconnect attempt during an outage used to be mistaken for an unsupported browser and downgraded the session to polling permanently.
- Note for future tests: Firefox renders multipart frames correctly but `drawImage` of that `<img>` onto a canvas returns its first frame, so liveness must be sampled from rendered screenshots.

### Adversarial review, round one, 2026-09-05

A fresh-context review of the 0.1.3 diff found the following; each was fixed and covered by a test before release.

- Stream connections had no deadline at all: `disarm` was called when a connection became a stream and nothing re-armed it, and there was no TCP keepalive. The reviewer filled all 256 slots from one peer with streams that never read, and the server was still wedged 35 s later, refusing every new connection. Fixed with a per-peer cap of 24 connections, TCP keepalive (30 s idle, 3 probes), and a 10-second deadline on every write, including stream frames. See the second round below: the first version of this fix was itself wrong.
- Pause and hidden tabs leaked a connection and kept streaming in WebKit: clearing `img.src` does not cancel an in-flight `multipart/x-mixed-replace` load there, so a paused Safari viewer kept receiving frames (31 frames in 6 s) and every pause/resume cycle left another socket open. Chromium needed the `src` clear; Safari needed `window.stop()` and a replaced element. All three are now done together, and the test counts sockets across four pause cycles.
- `scripts/viewer-test.py` itself was unreliable: a fixed 4-second sleep raced the viewer's 6-second stream watchdog, and fixed ports let one run's TIME_WAIT sockets contaminate the next. It now polls for state transitions and takes a fresh port per engine.
- The heartbeat treated the sharer's own 503 "no frame yet" as a disconnection, so a viewer opened between the server binding its port and the first captured frame flapped between "waiting" and "sharing stopped" every few seconds. 503 is now a wait. The heartbeat also had no timeout, so a Wi-Fi drop with no RST left it hanging while the page still claimed to be watching; it now aborts after 5 s.
- `downgrade()` was one-way: a tab opened during any outage was pinned to per-frame polling for the life of the page. It now retries the stream every 30 s.
- A request with a body desynced a kept-alive connection, because the body is never read and was parsed as the next request. Such a request is now answered with `Connection: close`.
- The install prompt could race autostart: `Relocator.relocating` was only set after the user clicked, and MainActor work runs during `NSAlert.runModal`, so an autostarting instance could bind the port and start capturing from the translocated bundle while the dialog was still open. The flag is now set before the prompt, and a declined or failed relocation resumes the startup it held back.
- Documentation claims were corrected in the same pass: sockets per viewer (2, not 1), over-cap connections (dropped without a response, not retried), stream connections being exempt from the idle timeout, and what a slow viewer can still accumulate.
- Reviewed and found clean: queue confinement of all server state, client-table leaks and UUID reuse, deadlock on `stop()`, HTTP framing on persistent connections (401/404/405/431, pipelining rejection, HEAD, HTTP/1.0, slow-loris at 10.0 s, idle keep-alive at 19.6 s), authentication re-running on every request of a reused connection, quarantine removal covering the whole bundle, `MainActor.assumeIsolated` in the app delegate, and object-URL handling in polling mode.

### Adversarial review, round two (the fixes themselves), 2026-09-05

- The write deadline freed the client's slot but could not take its socket down. Cancelling a connection whose peer stopped reading emits no FIN: the socket sits in the persist state holding undelivered frames. The reviewer measured four waves of eight stalling sockets from one peer growing 8 → 16 → 24 → 32 with 4.70 MB of kernel send buffer and still climbing — the per-peer cap was defeated and the leak was unbounded, which is worse than the defect it replaced. Fixed three ways: a stalled write now resets its connection (`forceCancel`) instead of closing it gracefully; a cancelled client keeps its place in the table until the connection actually reports `.cancelled`, so stalling cannot buy new slots; and `persistTimeout` / `connectionDropTime` (30 s) let the kernel drop what is left. Re-measured on the fixed build: the same attack plateaus at 16 live sockets, healthy clients are served throughout, and every stalled socket is gone about 20 s after the last wave. `scripts/smoke-test.py` now runs a two-wave version of it.
- Graceful closes stay graceful: only the write deadline resets a connection. `Connection: close` responses were briefly reset instead of closed by the first version of the fix, which would have discarded a response the client had not read yet; the smoke test caught it.
- The 30-second retry that was supposed to lift a viewer out of polling was cleared by any pause or tab switch and never re-armed, so a phone that locked its screen once stayed on per-frame polling for the life of the page. `begin()` now re-arms it, and the viewer test drives a visibility change and waits for the upgrade.
- Replacing the `<img>` to cancel Safari's stream left a src-less image visible, so a paused viewer showed a broken-image glyph and its alt text instead of a message. The replacement image now stays hidden and pausing says so.
- `window.stop()` rejects the in-flight heartbeat, and the bare `catch` read that as the sharer disconnecting: pausing at the wrong moment made a paused page announce a lost connection. The heartbeat now ignores a result whose stream generation has moved on, and `lost()` checks that the viewer is still watching.
- Corrected again in the docs: the per-viewer buffer is about 147 KB, not a full 4 MiB socket buffer; the "about 128 viewers" figure needs several source addresses, since one address is capped at 24 connections, i.e. about 12 viewers.
- Reviewed and found sound in this round: the deadline state machine itself (measured first request 10.0 s, idle keep-alive 20.0 s, an idle stream surviving 55 s with a silent publisher), completions arriving after a close, the peer string being address-only, `requiredLocalEndpoint` still honoured with custom TCP options, header parsing including duplicate headers and `Content-Length: 0`, `HEAD /stream.mjpg`, the relocation and resume path, and the test suites themselves (11 clean runs, no flakes).

## Remaining coverage limits

- No second physical LAN device was available. Actual Wi-Fi/router isolation, macOS firewall prompts and Safari/iOS fullscreen behavior require testing on the target network/device.
- Only one physical display was attached; multi-display selection uses ScreenCaptureKit's display list but switching among multiple attached monitors was not exercised.
- Keychain persistence and automatic startup/minimization are implemented, but were not enabled on this user's machine during the test.
- No claim of measured maximum viewer capacity or video-call-grade latency. It is JPEG polling intended for presentations, not audio/video streaming.
- No Apple Developer ID certificate or notarization has been used. The build script's signing and notarization path (`SCREENTASK_SIGN_IDENTITY`, `SCREENTASK_NOTARY_PROFILE`) is therefore unexercised; only the ad-hoc branch has been run.
- The kernel panic has not been reproduced deliberately and cannot be proven fixed. 0.1.3 removes the traffic pattern that preceded it and steers the app out of App Translocation; that is mitigation, not a verified kernel fix.
- The install-to-Applications flow (confirmation dialog, replacing an existing copy, quarantine removal, relaunch) is implemented but has not been run interactively on this machine; it needs a user-driven test from a downloaded, quarantined copy.
- Stream mode was exercised on loopback only. Behaviour over real Wi-Fi with a phone or tablet viewer, including iOS Safari, is still untested.
- A stalled viewer still buffers inside the kernel: `.contentProcessed` fires when the transport accepts the bytes, so about 147 KB per socket queues before the write stalls. The 10-second deadline then resets that connection, and the socket disappears within roughly 20 s. This is measured on loopback with synthetic frames; the same path with real full-screen JPEGs has not been measured.
- The per-peer cap of 24 means one LAN host can still hold 24 idle stream slots. That is deliberate headroom for several devices behind one address, not a claim that a hostile peer has no effect.
