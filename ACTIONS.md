# ACTIONS

Live status of the Fadeo work. Verified 17 July 2026.

## Verified this pass (re-checked, not just claimed)
- **Build**: `make build` -> BUILD SUCCEEDED (full Xcode, exit 0).
- **Core tests**: FadeoCore `swift test` -> 74 tests, 0 failures.
- **Resume at the exact spot** (your "continue at the exact second" ask): confirmed in code.
  - Local files: Fadeo does a real seek. `PlaybackBookmark.positionSeconds` + `queueIndex`
    are re-primed via `InternalEngine.primeResume`, with `currentSegmentStartFrame` added
    back so the reported position is the true one (a bug that made resumed files look stuck
    was already fixed).
  - Apple Music / Spotify: resumes at position too, but by design Fadeo does NOT seek. On
    resume it sends a bare `play` and never re-cues the link, so Music/Spotify continue from
    where they remember it, across a full Fadeo quit. This is the robust path (it avoids the
    flaky AppleScript `player position` read). Honest limit: if you quit Music/Spotify itself,
    position is theirs to keep, not Fadeo's.
- **End Session** control: `MenuBarContent` -> `AppController.endSession` -> banks usage,
  clears the resume bookmark, stops audio. Present.
- **Add Link host-detection**: `SoundLibraryPane` / `SoundEditor` read the URL host and pick
  the provider (music.apple.com, open.spotify.com, youtube), overriding the picker. Present.
- **Free-license reclaim**: `LicenseManager.pingActivation` posts the key to
  `/api/fadeo-activate`; the 7-day sweep lives in `portfolio/lib/fadeo-promo.js`. Present.
- **Free license emailed with the 7-day expiry line**: `portfolio/lib/send-license-email.js`
  sends the key and, for giveaway keys, the "activate by <date> (7 days), unused codes expire"
  line. Present.
- **Non-collapsible sidebar + scroll fix**: `RootView` is a fixed-width `HStack` shell (no
  NavigationSplitView), Sparkle removed. Builds and the panes render (screenshots below).

## New this pass (the deliverables you asked for)
- **Screenshots**: fresh, consistent set of six panes at 1800x1264 (Now, Workspaces, Sound
  Library, Precedence, Triggers, Usage), shot with the sanctioned read-only method. Config
  verified byte-identical afterward. The three that already existed came out byte-for-byte
  identical (the capture is deterministic), so nothing on the site changed; Now / Triggers /
  Usage are new. All in `portfolio/public/puremac/fadeo/screenshot-*.png`.
- **Promo reel**: `fadeo-reel.mp4` (vertical 1080x1920, ~18s) + `fadeo-reel.gif` (400px,
  8.6 MB). Brand-designed (slate/teal, the waveform-taper motif, SF type): title card, three
  fast context beats, then the app pane by pane, over a soft brown-noise bed. Built from the
  clean screenshots, no real desktop on screen, so it is safe to post. In the same folder.
- **DISTRIBUTION.md**: finalised. Assets section now points at the real files; the Day 0
  "cut a GIF" task is marked done. Reads first-person, no em dashes.

## Standing done (earlier sessions, still holding)
- Website: Alcove-style hero + interactive context-switcher demo; email-capture footer +
  `/api/fadeo-subscribe` (Redis dedupe) + admin subscribers view; hydration/a11y/overflow fixes.
- API: per-IP cap on free-license claims; Gumroad + Stripe webhooks reviewed; diagnostics
  ingestion + admin dashboard.
- App code review: playback-ended cleanup (the false "playing" desync), ScheduleSensor
  wall-clock boundary, quit-while-paused bookmark keep, usage attribution, stableId re-pin,
  engine-start guard, order/repeat on resume.
- CLAUDE.md project-status + screenshot-method docs refreshed.

## Remaining / not done
- [ ] **FEATURE.md** is still missing. You asked once for a simple two-section
  "implemented / planned later", one line each. Never created. Small task; say the word.
- [ ] **Packaging + notarization** blocked on an Apple Developer ID. App stays ad-hoc signed,
  so first launch needs right-click > Open past Gatekeeper. This is the one real blocker to a
  clean public download.
- [ ] **Auto-update** absent. Sparkle was removed (it broke the window on the macOS beta).
  Needs a different integration or a stable-macOS retest before shipping.
- [ ] **Internal-noise CPU** sits around 7-8% of one core while a synth texture plays.
  Idle is still ~0%. DSP optimization deferred, not a blocker.
- [ ] **Optional reel cuts**: a landscape / square version for the Product Hunt gallery
  (current cut is 9:16), and a licensed music bed if IG/TikTok become channels.
- [ ] App icon / logo redesign is yours in progress; do not regenerate `assets/appicon/`.

## Not committed
Everything above is local and uncommitted in both repos (Fadeo + portfolio), pending your
review and a "push".
