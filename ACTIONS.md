# ACTIONS

Near-future feature backlog for Fadeo. The core app and the monetization/growth layer are
feature-complete (M0 to M5, see PLAN.md §17): five live sensors, the four-band resolver
with the Conflict Simulator, synth textures plus file/folder/playlist playback, the
Spotify/Apple Music conductor, licensing, opt-in diagnostics, notifications, update check,
ratings, resume-across-quit. So this file is no longer a status log. It is the "what next"
menu: features worth adding, why each earns its place, rough size, and whatever gates it.
Written 18 July 2026. This is a menu, not a schedule.

Sizing is rough: (S) a few hours, (M) about a day, (L) multi-day. "Push" means it fits the
no-polling efficiency contract (PLAN.md §11) as written; "poll" flags a tension to design
around before building.

## The one real blocker (gates everything below actually reaching users)

- **Signed, notarized build + a working auto-update.** Still blocked on a paid Apple
  Developer ID, so the app stays ad-hoc signed and first launch needs right-click > Open
  past Gatekeeper. Sparkle was removed because it breaks the window on the macOS 26/27 beta
  (PLAN.md §15). Once there is a Developer ID: notarize, then wire either a Sparkle retest
  on stable macOS or a small custom updater on top of the existing GitHub-release check
  (`UpdateChecker.swift` already knows the latest tag; it just needs a download-and-swap
  path). Everything else in this file is optional; this is the thing that turns "10
  downloads" into a clean public install. (L)

## Shortlist (best value for the effort)

1. **Idle / away trigger** (S-M) - the most-requested obvious gap: fade or pause when you
   leave the desk, resume when you come back.
2. **Headphones / output-device trigger** (M) - "only play through my headphones" is a
   near-universal ask for an ambient-audio app, and it prevents the embarrassing
   speakers-in-a-meeting moment.
3. **Workspace import / share** (M) - turns each user into a distribution channel and seeds
   a community preset library. Growth leverage, not just a feature.
4. **Starter preset library** (S-M) - three or four ready-made workspaces so a new user
   hears the point in the first minute instead of building config from empty.

## New triggers (sensors)

Each is a new `Sensor` implementation emitting a `ContextPatch`, plus the matching
`ContextField`, a `Match` condition in the resolver, and a Triggers-pane row. The plan
already anticipated all of these (PLAN.md §2 trigger table, §17 "Later").

- **Idle / away** (S-M, push-ish). Mechanism: a global `NSEvent` monitor stamps a
  last-input time on any activity (push, steady-state free); only when a workspace actually
  uses an "idle for N minutes" condition do we arm a single one-shot timer for that
  boundary. Do it this way rather than the naive `CGEventSourceSecondsSinceLastEventType`
  poll loop, which would violate the efficiency contract. No permission needed for a global
  monitor of activity presence. Enables: pause the ambience when you step away, or switch
  to a quieter "background" workspace.
- **Headphones / output device** (M, push). Mechanism: CoreAudio default-output-device
  property listener, plus IOBluetooth for the AirPods case. No TCC prompt. Enables a "play
  only on headphones" gate and "switch workspace when I plug in." Pairs naturally with
  per-output-device routing below.
- **Network / SSID** (M, push). Mechanism: CoreWLAN + reachability notifications. Enables
  "at the office" vs "at home" contexts. Honest caveat: on modern macOS reading the SSID
  needs Location permission, so this one carries a real prompt; frame it clearly in
  onboarding or make it opt-in from the Triggers pane.
- **Calendar** (M, push/lazy). Mechanism: EventKit with a store-changed observer, look only
  at the current/next event's busy state, never event contents. Enables pre-empting for a
  scheduled meeting before the camera/mic even light up (the MeetingSensor fires on device
  usage, which is a few seconds late for "join on time"). Needs Calendar permission.
- **Battery / power state** (S, push). Mechanism: IOPMPowerSource notifications. Enables
  "drop the synth DSP or pause on battery" for laptop users who care about runtime. Cheap,
  small, nice-to-have.
- **Browser URL / active tab** (L, poll-ish, permission-heavy). Mechanism: Accessibility
  (`AXUIElement`) or per-browser AppleScript to read the frontmost tab URL. Enables
  per-site workspaces (focus audio on docs, silence on YouTube). Rank this last: it needs
  the Accessibility prompt, the read is inherently polled per focus change, and it is
  brittle across browsers. High want, high cost.

## Audio and transitions

- **Per-output-device routing** (M). Send Fadeo's audio to a chosen device (e.g. always the
  built-in speakers, or always the desk DAC) independent of the system default. Listed in
  PLAN.md §17 "Later". Best built alongside the output-device sensor since they share the
  CoreAudio plumbing.
- **More ambient textures** (S each). The synth engine is deliberately extensible: a new
  texture is one case in `NoiseRenderer.Kind` + `nextSample()` + `calibratedGain` + the
  preset lists in `SoundEditor`/`SoundLibraryPane`. Candidates that fit the existing DSP
  style: cafe murmur, distant thunderstorm, campfire crackle, a "tuned" warm drone. Zero
  assets, keeps the tiny footprint.
- **DSP cost reduction** (M). A synth texture currently costs about 7-8% of one core while
  playing (idle stays ~0%). Not a blocker, but it is the single biggest number in Activity
  Monitor during use, and the efficiency pillar is a selling point. Worth a profiling pass:
  cheaper filters, block processing, or a lower internal sample rate for the noise bed.
- **Fade-curve editor** (M). PLAN.md §6/§10 promised a transition style plus a fade-curve
  editor; today transitions expose durations but not curve shape. Add a small picker
  (linear / equal-power / exponential) so crossfades between workspaces can be tuned. The
  sample-accurate ramp code in `InternalEngine` already computes gain per sample; this is
  mostly choosing the ramp function and a UI to pick it.

## Workspaces and sharing

- **Workspace import / share** (M). Export one workspace (or a whole config) as a small,
  human-readable snippet others can paste in. PLAN.md already flags wanting a share
  format for a future community library. This is the cheapest growth lever here:
  every shared "Deep Work that pauses for meetings" is an ad.
- **Starter preset library** (S-M). Ship three or four ready-made workspaces (Deep Work,
  Meetings-pause, Reading, Coding) a new user can add in one click. Right now a fresh
  install starts empty and inert (an empty `Match` never holds by design), so the first-run
  experience is "build it yourself." A preset library closes the gap between install and
  first "oh, that's the point."
- **Community preset gallery on the site** (L, cross-repo). The natural sequel to the two
  above: a page on puremac.yashashwi.me where people submit and browse shared workspaces,
  reusing the import/share format. Only worth it once there are users to populate it.

## Smaller polish

- **Optional reel cuts** (S). A landscape and a square version of the promo reel for the
  Product Hunt gallery and any square-format channel; current cut is 9:16 vertical.
- **Real-time trigger demo clip** (S-M). A short screen recording that actually shows a
  context switch driving an audio transition live, to sit next to the pane-by-pane reel.
  See the storyboard in `distribution-plan/` for the shot list; the recording has to be
  done by hand on the real machine, never by driving the live app from a script.
- **Per-workspace usage insight in-app** (S). The Usage pane tracks time and switches
  already; a small "which workspace earns its keep" summary (most-used, longest sessions)
  would make the local stats feel less like raw numbers.

## Deliberately not doing (so we stop re-proposing these)

- **A system-volume master** (menu-bar slider that reads/writes CoreAudio volume). Tried,
  built, removed: in real use it read as a second competing volume next to each workspace's
  own level. PLAN.md §6a. Do not reintroduce without a stronger reason than "the system
  should be the master"; that argument already lost to real-use feedback once.
- **Re-adding Sparkle as-is.** Merely constructing the updater controller breaks the main
  window at the AppKit level on the macOS 26/27 beta (zero accessibility, dead scroll
  views). Any updater must be retested for window health on stable macOS first (see the
  blocker section).
- **A polling loop for anything in steady state.** The whole efficiency contract is that
  Fadeo is invisible in Activity Monitor at idle. New periodic work must justify itself as
  push-based or a single armed next-boundary timer, never a tick loop (PLAN.md §11).
