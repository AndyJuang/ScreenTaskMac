# Gates: ScreenTask for Mac

OWNS: **/*

Scope: Native Apple Silicon LAN screen sharing with upstream feature mapping, distributable app and public source.

- [x] G1: HTTP authorization, routing and LAN scope are exercised by regression tests
  CHECK: swift run --disable-sandbox ScreenTaskCoreTests
  EXPECT: All tests passed
  EVIDENCE 0.1.3: re-run 2026-09-05, "All tests passed: 7 regression groups" (keep-alive framing and the multipart stream route added).
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/zhuangzheyun/claudeai知識庫/VIBE_開發專案/ScreenTaskMac; path=8d877d837201/38 entries; EXPECT=matched; output-sha256=856c929966c98546a7b854ee033fffcea60087c6e6e2d1d1eec79ba6169c67db; output-bytes=191
- [x] G2: Release bundle contains an arm64 executable and valid ad-hoc signature
  CHECK: bash scripts/build-app.sh
  EXPECT: APP VERIFIED
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/zhuangzheyun/claudeai知識庫/VIBE_開發專案/ScreenTaskMac; path=8d877d837201/38 entries; EXPECT=matched; output-sha256=b169efe06bd67d1dca74ca3d3b59f973a3c67ce36f930c9c797e9446b4418c3f; output-bytes=376
- [x] G3: Real HTTP server serves frames and rejects unauthorized requests
  CHECK: python3 scripts/smoke-test.py
  EXPECT: HTTP SMOKE PASSED
  EVIDENCE 0.1.3: re-run 2026-09-05 with connection-reuse, multipart-stream and explicit-close checks added; "HTTP SMOKE PASSED".
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/zhuangzheyun/claudeai知識庫/VIBE_開發專案/ScreenTaskMac; path=8d877d837201/38 entries; EXPECT=matched; output-sha256=88ea6bbb4e55b3d1c900c85c75a3bdcdc09571e2f7be362aed359bb9cc2f7f31; output-bytes=18
- [x] G4: Native UI opens and actual screen capture reaches browser
  EVIDENCE: 2026-09-05 user-authorized loopback test displayed live ScreenCaptureKit frames in the browser; pause/resume, fullscreen/exit and server stop/reconnect were observed. The final rebuilt app window also opened successfully. Details and later ad-hoc-signature TCC caveat are in docs/VALIDATION.md.
- [x] G5: Public GitHub repository and downloadable release are reachable
  EVIDENCE: GitHub API verified public repo AndyJuang/ScreenTaskMac, tag v0.1.2 exactly at commit 31d9058, published non-draft latest Release, icon-bearing arm64 ZIP digest 17531f575530b7e88c99f814ebf67c7e1e0d2bf68ff9c3d5b06679311f79634d, checksum asset, and passing GitHub Actions run 33939814003.
- [x] G6: Feature differences, setup, license and handoff are recorded
  EVIDENCE: README.md, docs/FEATURES.md, docs/VALIDATION.md, NOTICE, LICENSE, AI_MEMORY.md and tasks/2026-09-05-initial-port.md record usage, feature parity, limits, GPL attribution, architecture and handoff.
- [x] G7: Designed ScreenTask icon is packaged as the app's complete macOS icon set
  CHECK: bash scripts/build-app.sh
  EXPECT: ICON VERIFIED
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/zhuangzheyun/claudeai知識庫/VIBE_開發專案/ScreenTaskMac; path=8d877d837201/38 entries; EXPECT=matched; output-sha256=33129a2629b6283379326dfd77556c09d1213e648e6c0d7a978b37c069e0d027; output-bytes=390
- [x] G8: One viewer holds one connection instead of one per frame
  CHECK: python3 scripts/viewer-test.py
  EXPECT: VIEWER TEST PASSED
  EVIDENCE: 2026-09-05. TIME_WAIT count after 20 s of one Chromium viewer: 140 closed connections on a rebuilt 0.1.2 worktree, 0-1 on 0.1.3. Concurrent sockets per viewer: 2 (stream plus heartbeat). Core tests and the loopback smoke test assert keep-alive framing and multipart stream framing directly; the smoke test also asserts the per-peer cap and that slots are released.
- [x] G9: The viewer page behaves correctly in Chromium, WebKit and Firefox
  CHECK: python3 scripts/viewer-test.py
  EXPECT: VIEWER TEST PASSED
  EVIDENCE: 2026-09-05, all three engines, two consecutive clean runs: live changing frames rendered from the stream, interval field disabled while streaming, pause releases the stream connection and four pause/resume cycles end at fewer sockets than they started with, stopped sharer reported within seconds, automatic reconnect when the sharer returns, and polling fallback when the stream is unavailable. Four real defects were found here and fixed before release (see docs/VALIDATION.md).
- [ ] G10: Install-to-Applications flow works on a real downloaded copy
  CHECK: manual — download the release ZIP in a browser, open the app from Downloads, accept the prompt, confirm it relaunches from /Applications and shares without a panic
  EXPECT: app runs from /Applications, screen recording re-authorized, sharing works
  EVIDENCE: pending. Implemented but never run interactively; it needs a quarantined copy and user interaction.
- [x] G11: Two adversarial reviews of the 0.1.3 diff leave no unaddressed defect
  EVIDENCE: 2026-09-05, two fresh-context reviews. Round one confirmed eight defects: streams exempt from every deadline (one peer could wedge all 256 slots), WebKit pause leaking a connection and continuing to stream, a flaky viewer test, a 503 startup window read as a disconnection, a heartbeat without a timeout, one-way polling downgrade, request-body desync on a kept-alive connection, and the relocation prompt racing autostart. Round two reviewed those fixes and confirmed four more, including that the write deadline freed a slot without taking the socket down, turning the original wedge into an unbounded socket leak (measured 8 to 32 sockets and 4.70 MB across four waves). All twelve are fixed and covered by tests: the same attack now plateaus at 16 sockets and drains within about 20 s. Findings, measurements and the areas reviewed clean are recorded in docs/VALIDATION.md.
