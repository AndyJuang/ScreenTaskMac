# Initial native macOS port

Request: reproduce ScreenTask's Windows LAN screen-sharing features for M-series Macs and publish openly on AndyJuang's GitHub.

Implemented native application, HTTP core, offline browser viewer, optional Keychain storage, multi-display source selection, quality/cursor/interval/network/startup controls, menu bar, app packaging, GPL attribution, CI and tests.

Reference audit and differences are recorded in docs/FEATURES.md. Evidence and physical-device coverage limitations are recorded in docs/VALIDATION.md. GATES.md tracks delivery checks.

Notable corrections during validation:
- Moved SwiftPM resources inside Contents/Resources so strict app signing succeeds.
- Added installed-bundle lookup and relocation testing so binaries do not depend on the development checkout.
- Used device RGB for synthetic JPEG generation to avoid named-color warnings filling subprocess pipes.
- Fixed CSS overriding the hidden attribute, so disconnected viewers hide old frames.
- Limited incomplete request lifetime/size and active connections; authentication runs before route lookup.

Release scope: 0.1.1, ad-hoc-signed arm64 app, source under GPL-3.0-or-later. Version 0.1.1 supersedes the initial 0.1.0 tag so the published tag includes the Swift 6 CI fix. Manual coverage limits remain documented rather than represented as verified.
