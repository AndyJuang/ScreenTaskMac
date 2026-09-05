# Gates: ScreenTask for Mac

OWNS: **/*

Scope: Native Apple Silicon LAN screen sharing with upstream feature mapping, distributable app and public source.

- [x] G1: HTTP authorization, routing and LAN scope are exercised by regression tests
  CHECK: swift run --disable-sandbox ScreenTaskCoreTests
  EXPECT: All tests passed
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/zhuangzheyun/claudeai知識庫/VIBE_開發專案/ScreenTaskMac; path=8d877d837201/38 entries; EXPECT=matched; output-sha256=856c929966c98546a7b854ee033fffcea60087c6e6e2d1d1eec79ba6169c67db; output-bytes=191
- [x] G2: Release bundle contains an arm64 executable and valid ad-hoc signature
  CHECK: bash scripts/build-app.sh
  EXPECT: APP VERIFIED
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/zhuangzheyun/claudeai知識庫/VIBE_開發專案/ScreenTaskMac; path=8d877d837201/38 entries; EXPECT=matched; output-sha256=b169efe06bd67d1dca74ca3d3b59f973a3c67ce36f930c9c797e9446b4418c3f; output-bytes=376
- [x] G3: Real HTTP server serves frames and rejects unauthorized requests
  CHECK: python3 scripts/smoke-test.py
  EXPECT: HTTP SMOKE PASSED
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/zhuangzheyun/claudeai知識庫/VIBE_開發專案/ScreenTaskMac; path=8d877d837201/38 entries; EXPECT=matched; output-sha256=88ea6bbb4e55b3d1c900c85c75a3bdcdc09571e2f7be362aed359bb9cc2f7f31; output-bytes=18
- [x] G4: Native UI opens and actual screen capture reaches browser
  EVIDENCE: 2026-09-05 user-authorized loopback test displayed live ScreenCaptureKit frames in the browser; pause/resume, fullscreen/exit and server stop/reconnect were observed. The final rebuilt app window also opened successfully. Details and later ad-hoc-signature TCC caveat are in docs/VALIDATION.md.
- [x] G5: Public GitHub repository and downloadable release are reachable
  EVIDENCE: GitHub API verified public repo AndyJuang/ScreenTaskMac, tag v0.1.1 exactly at commit 2cea031, published non-draft latest Release, arm64 ZIP digest 4072cb7d57eef3d4094593bab8b7171d810c04966861a11895e40b8ba842227c, checksum asset, and passing GitHub Actions run 33939408940.
- [x] G6: Feature differences, setup, license and handoff are recorded
  EVIDENCE: README.md, docs/FEATURES.md, docs/VALIDATION.md, NOTICE, LICENSE, AI_MEMORY.md and tasks/2026-09-05-initial-port.md record usage, feature parity, limits, GPL attribution, architecture and handoff.
- [x] G7: Designed ScreenTask icon is packaged as the app's complete macOS icon set
  CHECK: bash scripts/build-app.sh
  EXPECT: ICON VERIFIED
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/zhuangzheyun/claudeai知識庫/VIBE_開發專案/ScreenTaskMac; path=8d877d837201/38 entries; EXPECT=matched; output-sha256=33129a2629b6283379326dfd77556c09d1213e648e6c0d7a978b37c069e0d027; output-bytes=390
