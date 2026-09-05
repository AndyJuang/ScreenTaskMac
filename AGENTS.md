# ScreenTask Mac contributor instructions

Read AI_MEMORY.md and docs/VALIDATION.md first. Preserve GPL notices.
Keep runtime dependency-free and minimum target macOS 13 / arm64.
Never record real screen captures, credentials, or private network details in the repository.
HTTP and UI test fixtures must use synthetic frames. Live capture verification requires user consent and loopback.
Run core regression tests, the app build and HTTP smoke tests for changes affecting capture or transport.
Write significant decisions and remaining validation in tasks/ and AI_MEMORY.md.
