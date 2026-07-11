# Fadeo — Architecture & Build Plan

> Your Mac plays the right sound for what you're doing, automatically — and you
> control exactly how "right" is defined, down to the app, the desktop, and the second.

**Platform:** macOS 14+ (target macOS 26 "Tahoe"). Native Swift / SwiftUI.
**Shape:** a *full application* (real main window, deep preferences, workspace editor)
**plus** a lightweight menu-bar companion for at-a-glance control.
**Distribution:** open source, direct-download, Developer-ID signed & notarized;
**paid license with WinRAR-style soft nags** (fully functional unlicensed).

---

## 0. The pillars are hard constraints, not goals

1. **High customizability** — nothing hardcoded. Every trigger, timing value, fade
   curve, precedence rule, and fallback is *data*, never an assumption baked into code.
   The resolution core is a pure function over that data.
2. **High efficiency** — a daemon that runs all day must be invisible in Activity
   Monitor. **Target: idle CPU ≈ 0.0%, resident memory single-digit MB headless, zero
   polling in steady state.** Every choice below is filtered through this.
3. **It's a product people pay for** — best-in-class depth *and* polish. Open source,
   but the official signed build is licensed (soft nag, never a functional lockout).

These pull the same way: a data-driven, event-driven design is simultaneously the most
customizable (sensors/actuators exist only when a rule needs them) and the cheapest
(nothing runs unless the OS pushes an event).

---

## 1. Product shape — one binary, two surfaces

| Surface | What it is | When it's shown |
|---|---|---|
| **Main app window** | Full SwiftUI app: dashboard, **workspace editor**, sound library, precedence & transitions, triggers, preferences, energy dashboard, advanced YAML editor, license | when the user opens it |
| **Menu-bar companion** | `MenuBarExtra`: current workspace + what's playing, play/pause + volume, snooze automation, manual override, quick workspace toggles, live context line | always (agent) |

**Dual activation policy (the key trick):** the process runs as `.accessory`
(menu-bar-only agent, no Dock icon, App-Nap-friendly) in steady state. When the main
window opens, it flips to `.regular` (Dock icon, full app, menus); when the last window
closes it flips back to `.accessory`. **This satisfies "a real full app" and "an
invisible background daemon" at the same time** — no compromise.

---

## 2. What the research established (the four load-bearing findings)

| # | Finding | Consequence |
|---|---------|-------------|
| **1** | Since **macOS 15.4**, `mediaremoted` enforces entitlements: third-party apps can't **read** now-playing (`MRMediaRemoteGetNowPlayingInfo`→nil), but **commands still work** (`MRMediaRemoteSendCommand`: play/pause/next/volume). Reading needs [`ungive/mediaremote-adapter`](https://github.com/ungive/mediaremote-adapter): shell to `/usr/bin/perl` (implicitly entitled via `com.apple.*` id), stream JSON. BSD-3, Swift-callable. | We **control** playback for free; reading current track is **lazy & optional**. |
| **2** | Detecting **which** Space you're on needs private APIs (`CGSCopyManagedDisplaySpaces`); symbols drift across releases. Public notification only says *a* space changed. | Space-by-index lives behind a **version-guarded shim** that degrades gracefully. |
| **3** | **Notarization does NOT scan for private APIs** — only App Store *review* does. A Developer-ID, notarized, **non-sandboxed** app may use the Perl adapter, private CGS APIs, Accessibility. | Distribution = direct download + notarize. App Store would kill half the triggers. |
| **4** | Every v1 trigger is **event-driven / push** — including "in a meeting" (observe CoreMediaIO/CoreAudio *usage* → **no camera/mic permission prompt**). | Detection layer runs **zero-polling** in steady state — the whole basis of Activity-Monitor invisibility. |

### Trigger cost table (v1 bolded)

| Trigger | API | Model | Cost |
|---|---|---|---|
| **Frontmost app** | `NSWorkspace.didActivateApplicationNotification` | push | ~free |
| **Space / desktop** | `activeSpaceDidChangeNotification` + private CGS read | push | ~free |
| **In a meeting** | CoreMediaIO cam + CoreAudio mic `…IsRunningSomewhere` listeners | push | ~free, no TCC prompt |
| **Focus / DND** | FSEvents watch on `~/Library/DoNotDisturb/DB/Assertions.json` | push | ~free |
| **Time / schedule** | one `DispatchSourceTimer` → next rule boundary, large tolerance | 1 coalesced wake | ~free |
| Idle · Browser URL · Network/SSID · Battery · Headphones · Calendar *(later)* | CGEventSource · AX/AppleScript · CoreWLAN · IOPM · IOBluetooth · EventKit | push / lazy | ~free / on-demand |

---

## 3. Architecture — layers behind an event bus

```
┌─ SENSORS (event-driven; each owns ONE OS signal; lazily activated) ─────────┐
│  AppFocus · SpaceChange · Meeting(cam/mic) · Focus/DND · Time/Schedule       │
│  A sensor no active workspace references registers ZERO observers.           │
└───────────────────────────┬─────────────────────────────────────────────────┘
                            │ ContextPatch (debounced/coalesced)
┌───────────────────────────▼─────────────────────────────────────────────────┐
│  CONTEXT STORE — one merged snapshot of "what's happening right now"          │
└───────────────────────────┬─────────────────────────────────────────────────┘
                            │ Context
┌───────────────────────────▼─────────────────────────────────────────────────┐
│  RESOLVER — PURE FUNCTION  resolve(Context, Workspaces, Settings) → Decision  │
│   1. override band   2. candidate set   3. tiebreak chain   4. fallback       │
│   emits: {activeWorkspace?, source, volume, transition} + WHY (for inspector) │
│   100% unit-testable, no OS involved                                          │
└───────────────────────────┬─────────────────────────────────────────────────┘
                            │ Decision
┌───────────────────────────▼─────────────────────────────────────────────────┐
│  RECONCILER — diff desired vs current audio state, emit only the delta        │
└───────────────────────────┬─────────────────────────────────────────────────┘
                            │ minimal commands
┌───────────────────────────▼─────────────────────────────────────────────────┐
│  ACTUATORS (only those a workspace uses are instantiated)                     │
│  ├ ExternalConductor  MediaRemote cmds + Spotify/Music AppleScript (+lazy read)│
│  └ InternalEngine     AVAudioEngine: play/loop/crossfade/fade; freed when idle │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Workspaces are the user-facing model; they *compile* to the resolver's inputs.** The
GUI edits Workspaces (intuitive); a power user can edit the same thing as YAML. Both
lower to one representation the pure resolver evaluates. This is how we get friendly
*and* infinitely customizable without two engines.

---

## 4. The Workspace model (the user-facing concept)

A **Workspace** is a named context with a sound behavior. Example: *Deep Work*,
*Design*, *Gaming*, *Meetings*, *Reading*.

```yaml
# ~/Library/Application Support/Fadeo/config.yaml  (source of truth; hot-reloaded)
version: 1
settings:
  evaluationDebounceMs: 300
  tiebreak: [stickiness, specificity, priority, recency]   # user-orderable
  fallback: keepCurrent          # keepCurrent | resumePrevious | silence
  fallbackFadeMs: 1500
  defaults: { fadeInMs: 800, fadeOutMs: 800, crossfadeMs: 1200,
              enterDelayMs: 1200, exitDelayMs: 400, minDwellMs: 15000 }

workspaces:
  - id: deep-work
    name: "Deep Work"
    color: "#67E4D2"
    priority: 80                 # explicit rank (tiebreak fallback)
    match:                       # ALL listed dimensions must hold (configurable any/all)
      apps:
        - { bundle: "com.apple.dt.Xcode", strength: strong }
        - { bundle: "com.microsoft.VSCode", strength: strong }
        - { bundle: "com.tinyspeck.slackmacgap", strength: weak }   # won't yank you in
      spaces: [1]                # optional extra constraint → raises specificity
      focus: ["work"]            # optional
      timeBetween: ["09:00","18:00"]
    sound:
      source: "internal:preset:brown-noise"
      volume: 0.6
      perApp:                    # optional overrides for a member app
        "com.apple.dt.Xcode": { volume: 0.7 }
    timing: { fadeInMs: 1200, minDwellMs: 20000 }   # overrides defaults

  - id: meetings
    name: "Meetings"
    override: true               # OVERRIDE BAND — pre-empts everything while it matches
    match: { meeting: true }     # camera OR mic live (configurable)
    sound: { action: pause, fadeOutMs: 300 }

  - id: gaming
    name: "Gaming"
    priority: 50
    match: { apps: [{ bundle: "com.valvesoftware.steam", strength: strong }] }
    sound: { source: "external:spotify:playlist:37i9dQ...", volume: 0.5, crossfadeMs: 1500 }
```

**Anatomy of a workspace:** identity (name/color/icon), **match** (which apps / spaces /
times / focus / meeting activate it), **sound** (source + volume + action), optional
**per-app overrides**, optional **timing** overrides, **priority**, and two special
flags: `override` (pre-empt band) and per-app `strength` (`strong` vs `weak`).

**Sources** (any workspace): `external:spotify:playlist:<id>`, `external:appleMusic:<id>`,
`external:command` (just play/pause whatever's playing), `internal:file:<path>`,
`internal:folder:<path>`, `internal:playlist:<id>`, `internal:preset:<name>` (rain /
brown-noise / lofi / …). **Actions:** `play`, `pause`, `stop`, `setVolume`, `duck`,
`resumePrevious`, `doNothing`.

**Source philosophy — DECIDED: bring-your-own first.** The core attitude is *your* sound:
your Spotify/Apple Music playlists and your own files/folders. We *also* bundle a small
royalty-free **starter set** (rain, brown/pink noise, lo-fi loops) so a fresh install
makes sound immediately — but BYO is the headline, presets are the on-ramp.

**Local playback — DECIDED, implemented: three granularities, so "your own files" means
exactly what the user wants it to mean, not just "one file":**
- `internal:file:<path>` — a single file.
- `internal:folder:<path>` — every supported audio file in that folder (non-recursive),
  in filename order or shuffled.
- `internal:playlist:<id>` — a **user-curated subset** of specific files, referenced by
  id against `Config.localPlaylists` (`LocalPlaylist { id, name, paths }`). This is the
  "select a few tracks from a folder" case — an explicit, user-picked list rather than a
  filter rule, so it's exactly as customizable as the user wants (a GUI picker to build
  these lands with the Sound Library pane in M4; the data model exists now).

**Playback order & repeat — genuine per-workspace controls, not hardcoded**, via
`Sound.order` (`sequential` | `shuffle`) and `Sound.repeatMode` (`off` | `one` | `all`,
default `all` so ambient folders/playlists loop naturally). Only meaningful for
multi/single-file internal sources; ignored for presets and external sources (those apps
manage their own playback order).

Streaming (Spotify/Apple Music) and local playback are peers, not alternatives — a
workspace picks whichever `source` fits, and different workspaces can freely mix the two
(e.g. "Deep Work" plays a local folder, "Commute" plays a Spotify playlist).

---

## 5. Precedence & conflict resolution — the deep problem, solved

**The situation you raised:** the same app can belong to two workspaces. You're in
Workspace **C** (its music playing). You switch to app **X**, which is a member of
**A** *and* **B** (not C). Which workspace wins, and what should the audio do?

Resolution runs as **four ordered bands**; the answer is deterministic *and* tuned for
least surprise:

### Band 1 — Override (pre-emptive)
Any workspace flagged `override: true` whose match holds wins outright, ignoring
everything else. Default: *Meetings* (`meeting: true`). → "Instant mute the second a
call starts" always beats app/space workspaces. When the override stops matching, we
fall back through the lower bands (and typically **resume** what was playing).

### Band 2 — Candidate set
Collect every non-override workspace whose `match` currently holds. Membership requires
the frontmost app be a member **and** any extra constraints (space/time/focus) hold. A
workspace whose match has no conditions at all is never a candidate — an empty match is
inert, not a catch-all, so a freshly created workspace stays silent until you give it a
condition.
- **0 candidates →** Band 4 (Fallback).
- **1 candidate →** it's active. Done.
- **>1 →** Band 3.

### Band 3 — Tiebreak chain (user-orderable; default below)
Apply strategies in order until one workspace wins:

1. **Stickiness (continuity).** If the *currently active* workspace is still a
   candidate, **keep it** — don't change the music just because you tabbed to a shared
   app. *(In your scenario C is NOT a candidate — X∉C — so stickiness doesn't fire, and
   we correctly proceed to choose between A and B.)*
2. **Specificity.** The workspace whose match is *more constrained* wins — more matched
   dimensions = more intentional (app+space+time ⟩ app-only). If A also pins "Space 1"
   and you're on Space 1, **A beats B** (app-only). Usually "the workspace that cares
   most about this exact situation."
3. **Priority.** Explicit user rank (drag to order). Decides genuine ties where A and B
   list only the app. Whatever you ranked higher wins — total user control.
4. **Recency.** Most-recently-active of the candidates ("do what I did last time").
   Off by default (can surprise); opt-in.
5. **Stable id.** Final deterministic tiebreak so behavior is *never* random.

### Band 4 — Fallback (no candidate)
Governed by `settings.fallback`:
- **`keepCurrent`** (default) — inertia: keep whatever's sounding. → *"I tabbed to an
  app no workspace claims; don't disrupt my flow."*
- **`resumePrevious`** — restore the last external track/state.
- **`silence`** — fade out.

### The `weak` membership knob (the elegant answer to "shared apps shouldn't yank me")
A member app can be `strength: weak` (a.k.a. *ambient*). A weak member **activates its
workspace only if no other workspace is already active** — it never pulls you *out* of
your current context. So marking Slack/Notes/Finder as `weak` across workspaces means
tabbing to them from Deep Work **keeps Deep Work's music**, while `strong` members do
switch context. `strong` (default) + `weak` + `keepCurrent` fallback cover essentially
every "minute" preference about disruption.

### Worked example (your exact case), fully determined
> In **C** (music C). Switch to **X ∈ {A, B}**, X∉C.
> 1. No override matches. 2. C drops out (X∉C); candidates = {A,B}. 3. Tiebreak:
>    stickiness N/A (C not a candidate) → specificity: if only A also matches your
>    current Space/time, **A wins**; else → priority: your rank decides. 4. Transition
>    C→A uses A's `fadeInMs`/`crossfadeMs` and C's `fadeOutMs` (or the global transition
>    style). If instead you'd rather X *not* change anything, mark X `weak` in A and B →
>    with `keepCurrent`, **C's music simply continues**.

### Trust: the Conflict Inspector / Simulator
Because these are "minute points," the UI must make them legible:
- **Live "why this workspace" line** on the dashboard: *"Deep Work — won by specificity
  (Space 1) over Gaming."*
- **Simulator** in Precedence settings: pick a hypothetical context (app + space + time
  + meeting) → see which workspace would win and *which band/strategy decided it*, before
  it ever happens. This is what makes deep precedence usable instead of mysterious.

---

## 6. Timing & transitions (deep customization surface)

Every timing value exists at **global default** level and is **overridable per
workspace** (and, where sensible, per app-in-workspace):

| Knob | Meaning |
|---|---|
| `fadeInMs` / `fadeOutMs` | ramp when a workspace's sound starts / stops |
| `crossfadeMs` | overlap when switching source A→B |
| `enterDelayMs` | **grace** — ignore a context that lasts < this (don't react to a 1s tab-through) |
| `exitDelayMs` | linger before acting on leaving |
| `minDwellMs` | **hysteresis** — hold a workspace ≥ this before it can be switched away (anti-flap) |
| transition style | per-pair: `crossfade` \| `fadeOutThenIn` \| `hardCut` |
| fade **curve** | linear \| equal-power \| exponential (visual editor; ties to the waveform-taper brand motif) |

Combined with `evaluationDebounceMs`, these absorb rapid app-switch bursts so the audio
never thrashes. All user-tunable; sensible defaults ship.

---

## 6a. Volume model: one concept, not two (core feature)

**DECIDED (revised after hands-on use):** Fadeo does not read, write, or mirror the macOS
system volume at all, and has no volume control of its own in the menu bar. There is
exactly **one** volume concept in the whole app: each workspace's own **per-source/per-app
mix level** (`Sound.volume` + `perApp`) — "brown-noise sits at 0.6", "rain at 0.45", "Xcode
a touch louder". This is not a "master" and was never meant to compete with one; it behaves
like a channel fader, not a system-wide control.

**Why the earlier system-volume-mirroring design got cut:** an early version added a
menu-bar slider that read/wrote the actual system volume live (via CoreAudio
`kAudioHardwareServiceDeviceProperty_VirtualMainVolume`), reasoning that Fadeo's "master"
should just be the real system volume rather than a second async one. In practice, having
*both* a per-workspace mix level *and* a menu-bar volume control reads as two competing
volumes, which is exactly the confusion it was meant to avoid — simpler to have only one.
`Platform/SystemVolume.swift` and the menu-bar slider were removed entirely.

**What's unchanged:** macOS scales every app's output by the system output volume at the
hardware layer regardless — `AVAudioEngine`'s output is already affected by it, and Fadeo
still never multiplies by it in software (nothing to get wrong now, since we don't touch
CoreAudio's volume properties at all). Effective loudness = `baseline × calibration` (our
own gain) `× systemVolume` (applied by the hardware, invisibly, same as any other app).

**Two-layer model (down from three):**
1. **Per-source / per-app baseline (the mix)** — `Sound.volume` + `perApp`, `0…1`,
   Fadeo-relative. Edited per workspace in the Workspace editor.
2. **Perceptual calibration (per source)** — a fixed per-source correction so equal
   baseline numbers *sound* equally loud (white noise reads far louder than brown at the
   same RMS). Applied automatically in `InternalEngine.calibratedGain`; not applied to
   user files (pre-mastered content) or external sources (the target app owns that).

For **external** players, the baseline maps to that app's own `sound volume` (AppleScript);
system volume, physical volume keys, and Control Center remain the only way to change
overall loudness — exactly as if Fadeo weren't there, which is the point.

---

## 7. Data model (pure core)

```swift
struct Context {                 // one merged snapshot the resolver reasons over
    var frontmostApp: String?    // bundle id
    var frontmostWindowTitle: String?      // later (AX)
    var activeSpace: SpaceRef?   // {display, index?, uuid} — index nil if shim degraded
    var cameraActive, micActive: Bool
    var inMeeting: Bool          // derived, configurable (cam && / || mic)
    var focusMode: String?       // "work" | "personal" | nil
    var localTime: Date
    var idleSeconds: TimeInterval?          // later
    var stamp: Date
}

struct Decision {                // resolver output
    var activeWorkspace: WorkspaceID?
    var target: AudioTarget      // source + volume + action
    var transition: Transition   // fades / crossfade / delay
    var reason: ResolutionTrace  // which band/strategy decided — for the inspector
}

func resolve(_ ctx: Context, _ ws: [Workspace], _ s: Settings) -> Decision   // PURE
```

The resolver, the tiebreak chain, YAML (de)serialization, and validation live in
`FadeoCore` and are **100% unit-tested with zero OS dependencies** — feed a Context,
assert a Decision. That test suite *is* the guarantee behind the customizability pillar.

---

## 8. Actuators

**`ExternalConductor`** — conducts the player you already use.
- Transport (play/pause/next/volume, system-wide): `MRMediaRemoteSendCommand` — no
  entitlement needed, the reliable path.
- App-specific (switch to a named Spotify/Music item; ramp *that app's* volume for a
  fade): ScriptingBridge / AppleScript.
- **Read** current track (only for rules like "don't override if already playing"): lazy
  `mediaremote-adapter` Perl stream — spawned on demand, torn down after. Bundled in
  `Fadeo.app/Contents/Resources/`.
- Keeps its own desired-state tracker to survive AppleScript flakiness (never depends on
  reading back).

**`InternalEngine`** — self-contained player.
- `AVAudioEngine` + player node(s) + mixer; local files + bundled ambient presets;
  gapless loop; fades via mixer `outputVolume` ramp; crossfade via two nodes.
- **Deallocated when idle** — no workspace wants internal audio → engine stopped, HAL
  released → 0% CPU.

Only actuators referenced by active workspaces are instantiated.

---

## 9. Config system (GUI ⇄ file, two-way, hot-reload)

- **Source of truth:** `~/Library/Application Support/Fadeo/config.yaml` — readable,
  comment-friendly, version-controllable, schema-versioned.
- **GUI → file:** editor mutates in-memory model → atomic write.
- **File → app:** FSEvents watch → parse → **validate** → hot-swap atomically. On error:
  **keep last-good config**, show a clear banner (never crash, never silently break).
- Conflict policy: last-writer-wins, always validated. A bad edit can't take down the
  daemon or leave audio undefined.

---

## 10. App structure & UI

**Main window — sidebar navigation:**

| Pane | Contents |
|---|---|
| **Now / Dashboard** | current workspace + what's playing; live context (app · space · meeting · focus · time); **"why this workspace" trace**; manual override |
| **Workspaces** | list + editor: name/color/icon; **add apps** (picker, drag, or "capture frontmost"); spaces/time/focus/meeting constraints; source; volume; **per-app strength & overrides**; timing overrides |
| **Sound Library** | connect Spotify/Apple Music; add local files/folders; ambient presets; preview |
| **Precedence & Transitions** | drag-order the **tiebreak chain**; fallback behavior; global fades/delays/dwell; transition style + **fade-curve editor**; **Conflict Simulator** |
| **Triggers** | enable/disable sensors; define "meeting" (cam and/or mic); name your Spaces |
| **Preferences** | general; launch at login (`SMAppService`); updates (Sparkle); **Energy dashboard** (live CPU/events — the efficiency proof); permissions status & re-request; backup/export |
| **Advanced** | raw **YAML editor** (two-way); import/export; rule inspector; logs |
| **About / License** | logo; version; license status; buy/activate; OSS repo link; the soft nag |

**Menu-bar companion (`MenuBarExtra`) — simple yet genuinely useful:**
current workspace + what's playing · play/pause + volume slider · **snooze automation**
(15m / 1h / until tomorrow / until quit) · **manual override** to a workspace (once /
for 1h / until context changes) · toggle a workspace on/off · live context line
(app · space · meeting) · **Open Fadeo** (→ flips to `.regular`, opens main window).

---

## 11. Efficiency engineering — the "invisible in Activity Monitor" contract

Per Apple's [Energy Efficiency Guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/index.html):

1. **Zero polling in steady state** — all OS push (`NSWorkspace`, CoreMediaIO/CoreAudio
   listeners, FSEvents, Space-change). Only timer = schedule sensor's single
   next-boundary `DispatchSourceTimer` (large `tolerance`), disarmed when no time rule.
2. **Lazy sensors & actuators** — start only sensors whose fields some enabled workspace
   references; disabled = zero observers = zero cost.
3. **Debounced/coalesced evaluation** — rapid app-switch bursts → one `resolve`.
4. **Reconciler emits only diffs** — no redundant AppleScript/IPC.
5. **`AVAudioEngine` torn down when unused** — releases HAL, 0% CPU.
6. **App-Nap-friendly** — `.accessory` in steady state; no `beginActivity` unless audio
   is actually playing; registered OS events still wake us.
7. **Perl adapter only while a read-rule is active** — short-lived / streamed, then killed.
8. **Sleep/wake** — tear down engine on `willSleep`; re-read context + re-evaluate on
   `didWake`.
9. **No web view, no Electron, single process.** Main window created lazily, released on
   close (→ back to `.accessory`).
10. **Self-instrumentation** — Energy dashboard shows live events/sec + current Context,
    so a runaway observer is caught immediately.

**Ship gate:** idle CPU ≈ 0.0% over 10 min; RSS < ~15 MB headless, < ~40 MB with window
open; no Fadeo-attributable wakeups in `powermetrics` while idle.

---

## 12. Permissions & entitlements

| Capability | Mechanism | Prompt? | Notes |
|---|---|---|---|
| Frontmost app / Space | `NSWorkspace` notifications | No | free |
| Camera/mic **in-use** | CoreMediaIO / CoreAudio device properties | **No** | observing usage ≠ capturing → no TCC |
| Focus / DND | read `~/Library/DoNotDisturb/DB/Assertions.json` | No | user-readable |
| Control Spotify / Music | AppleEvents / ScriptingBridge | **Yes** (Automation) | `NSAppleEventsUsageDescription`; onboarding explains |
| Window title / URL *(later)* | Accessibility (`AXUIElement`) | **Yes** (Accessibility) | wizard deep-links the pane |
| Login start | `SMAppService` (macOS 13+) | No | modern; no hand-written plist |
| MediaRemote cmds / adapter read | private framework via Perl | No | unsandboxed; not App-Store-eligible |

Hardened runtime, non-sandboxed. First-run wizard requests **only what enabled
workspaces need** (no Automation prompt if no external-player workspace exists).

---

## 13. Licensing, trial & monetization (open source + WinRAR-style soft nag)

**Nothing is ever gated by a premium tier — every feature works from first launch,
forever.** Payment funds development and clears the nag; it never unlocks functionality.

- **Price: $2 lifetime.** Deliberately trivial — impulse-cheap, honor-system, "just pay
  the $2." One-time, no subscription.
- **14-day trial, then soft nags.** After 14 days, an unlicensed copy shows a gentle,
  dismissible reminder (on-launch, occasional; plus a quiet "unlicensed" pill in About).
  **Never interrupts audio, never fires during a meeting/Focus** (Fadeo of all apps must
  respect that).
- **The nag offers two ways to make it go away:**
  1. **Buy the $2 lifetime license**, or
  2. **Answer a short survey + opt into anonymous usage diagnostics.** Either path
     satisfies the nag. This trades "money" for "feedback + signal", so users who won't
     pay still help the product, and the developer gets real usage insight.
- **Free-license giveaway (launch gimmick):** for a limited window, `puremac.yashashwi.me/fadeo`
  shows a **"Generate free lifetime license"** button, **capped at the first ~100**. Those
  keys are ordinary offline licenses — permanent, no nag.
- **Offline validation.** License = an **Ed25519-signed blob**; the app bundles the public
  key and verifies locally. **No phone-home at runtime** (privacy + zero background network
  cost). Online only at the moment of purchase / free-key generation / manual refresh.
- **License-of-source: DECIDED — GPLv3** + a separate paid key for the official binary
  ("open core / paid convenience & support"). `LICENSE` (GPLv3) committed from day one.
- Licensing module stays tiny and offline — **no** steady-state cost.

### 13a. Usage diagnostics (opt-in, privacy-first)
- **Opt-in from first run** (offered in onboarding) *and* toggleable anytime in Preferences
  — and it's one of the two nag-clearing paths above.
- **Anonymous.** Random install id, no personal data, no config contents. Coarse signals
  only: app version/OS, # workspaces, switches/day, which sensors/sources are used,
  crash counts, trial→license conversion. Enough for the developer to *see how it's used*,
  nothing identifying.
- **Batched & cheap.** Buffered locally, flushed infrequently over `NSURLSession` (respects
  the efficiency pillar — never chatty). Endpoint on the PureMac hub (§15).
- Because it's GPLv3 and opt-in, the whole scheme is transparent and auditable.
- **Built**: `DiagnosticsUploader.swift` sends `UsageStats.shareableSummary` at most once a
  day, only when `DiagnosticsPreference.isEnabled`, fire-and-forget (a failed/skipped send
  just retries next launch — no queue, no retry loop). Ingestion + an admin-secret-gated
  dashboard (`puremac.yashashwi.me/fadeo/diagnostics`) live in the `portfolio` repo
  (`lib/fadeo-diagnostics.js`, `app/api/fadeo-diagnostics/route.js`), backed by the same
  Redis instance the free-license giveaway already uses.

### 13b. Notifications system
- macOS user notifications via `UNUserNotificationCenter` for: trial expiry, the soft nag,
  update available, free-key confirmation, config errors, and (opt-in) "switched to
  workspace X". **Suppressed during meetings/Focus**; rate-limited; all individually
  toggleable. In-app banner equivalents for anything shown while the window is open.

---

## 14. Brand & design system

- **Logo (v2, redesigned):** teal waveform **tapering to nothing** on a slate squircle,
  literally the *fade* metaphor. Rebuilt from a real superellipse (exponent 5, matching
  Apple's own icon curvature) rather than a CSS-style rounded-rect, spanning near the
  full 1024 canvas (macOS does not auto-mask app icons the way iOS does, so the squircle
  has to be baked into the artwork), with an actual background gradient + soft highlight
  for depth instead of a flat fill. Source: `assets/redesign/fadeo-icon.svg`, regenerated
  via `scripts/gen-icon.py` (requires `librsvg`, `brew install librsvg`). Deployed to:
  - `assets/logo/fadeo-logo.png` / `fadeo-logo-square-1024.png` — README / in-app / social
  - `assets/appicon/fadeo-appicon-1024.png` — app-icon master (the AppIcon set / `.icns`
    is generated from it via `scripts/make-assets.sh`)
- **Palette:** accent **teal `#67E4D2`**, surface **slate `#5A6A7A`**; derive a full
  tonal scale. **Dark-first** (matches the icon), full light mode too.
- **Motif:** the waveform taper reappears as the **fade-curve editor**, transition
  animations, and loading states, one visual language throughout.

---

## 15. Distribution & the PureMac hub

- **Home: `puremac.yashashwi.me`** — a clean, minimal storefront/hub (on the `yashashwi.me`
  domain) for the developer's Mac apps: **Fadeo**, **Tableau** (photo-widget for macOS),
  and future apps. One consistent, great-looking landing surface.
- **Fadeo is downloaded only from `puremac.yashashwi.me/fadeo`** going forward (not GitHub
  Releases for the *binary* — source stays on GitHub). The page hosts the download, the
  **Sparkle appcast**, purchase ($2), the **capped free-license generator**, and the
  **diagnostics ingestion** endpoint.
- **Signing:** Developer ID Application, **hardened runtime**, **non-sandboxed**.
- **Notarize:** `notarytool` submit → staple (no private-API scan — confirmed safe).
- **Auto-update:** [Sparkle](https://sparkle-project.org), EdDSA-signed appcast on the hub.
- **Bundle:** `mediaremote-adapter` framework + `.pl` + ambient presets in `Resources/`.
- Site work (storefront, license service, diagnostics dashboard) is **its own track**,
  post-M5 for the app; scoped separately. Recorded here so the app's licensing/diagnostics
  interfaces are designed to match from the start.

---

## 16. Project layout (SPM core + Xcode app)

```
Fadeo/
├─ Packages/FadeoCore/            # SPM — pure, 100% unit-tested (the correctness core)
│  ├─ Context / ContextPatch / ContextField
│  ├─ Workspace / Settings model + YAML codable + validator
│  ├─ resolve(Context,Workspaces,Settings)→Decision   # bands + tiebreak chain
│  ├─ Precedence simulator (same code the UI simulator calls)
│  └─ Reconciler (pure diff)
├─ Fadeo/                         # Xcode app target (dual activation policy)
│  ├─ App/                        # window + sidebar, MenuBarExtra, onboarding, license
│  ├─ Sensors/                    # AppFocus · Space(+CGS shim) · Meeting · Focus/Schedule
│  ├─ Actuators/                  # ExternalConductor · InternalEngine
│  ├─ Platform/                   # CGS shim · MediaRemote bridge · adapter runner · TCC
│  └─ Resources/                  # adapter · presets · AppIcon · Info.plist
├─ assets/                        # logo + appicon masters
└─ PLAN.md
```

Rationale: the part that must be *correct* (resolver + precedence) has no Mac in its
test loop; OS glue is thin and swappable.

---

## 17. Build order (milestones — each is a runnable app)

| M | Deliverable | Proves |
|---|---|---|
| **M0** | Full-app skeleton: **dual activation policy** (window ⇄ menu-bar agent), sidebar shell, `MenuBarExtra`, login-start (`SMAppService`), config load + hot-reload, **Energy dashboard / context inspector**, AppIcon from master | shell + "full app + companion" duality + efficiency baseline (idle≈0%) |
| **M1** | **Vertical slice:** Workspace model + AppFocus sensor + resolver + reconciler + `InternalEngine` with fades. Create a workspace, add an app, hear it work. | the whole pipeline end-to-end; first usable build |
| **M2** | **Precedence engine** (4 bands + tiebreak chain) + **Conflict Simulator**; `ExternalConductor` (MediaRemote + Spotify/Music) | the deep customization + conducting real players |
| **M3** ✅ | Remaining v1 sensors: Space (CGS shim) · Meeting (cam/mic) · Focus/Schedule (FSEvents + boundary timer). Also: real lazy sensor activation (a sensor starts only if an enabled workspace's `match` needs its fields) | all four triggers live |
| **M4** ✅ | Full **Workspace editor UI** + Sound Library + Precedence UI + Conflict Simulator + Triggers UI (live sensor status) + two-way YAML editor | both halves of the customizability pillar |
| **M5** (core done ✅, monetization/packaging deferred) | Done: **permissions/onboarding** (one-screen, real permission surface, includes the diagnostics opt-in) · **energy dashboard** (self-reported RSS + active sensor count) · **usage statistics** (local always-on tracking of time/switches per workspace, a Usage pane, and an opt-in coarse shareable summary) · **diagnostics now actually transmit** (`DiagnosticsUploader.swift` → the PureMac hub's ingestion endpoint + admin dashboard) · **resume-across-quit** (internal files and Apple Music/Spotify pick up at the exact position after a full quit, not just a brief pause) · real app icons throughout · searchable app picker · reset-to-defaults in Precedence. **Deferred, by user decision**: licensing ($2/14-day trial/soft nag), Sparkle updater, notarization/signing, brand/logo redesign in progress by the user | core app is feature-complete; monetization + distribution are the remaining work |
| Later | Idle · browser URL · network/SSID · battery · headphones · calendar sensors; preset library; per-output-device routing; workspace import/share | breadth |
| Site | **PureMac hub** (`puremac.yashashwi.me/fadeo`): storefront, download + Sparkle appcast, purchase, capped free-license generator, **diagnostics dashboard ✅** | remaining pieces (Sparkle appcast, download) blocked on Developer ID + notarization |

---

## 18. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Private CGS Space symbols drift | version-guarded shim; degrade to "space changed, index unknown"; app-based workspaces keep working |
| Apple locks MediaRemote *commands* too | lean on AppleScript per-app control; InternalEngine unaffected; read-adapter already optional |
| AppleScript flakiness (Spotify `current track`) | prefer commands + our own desired-state tracker; never depend on read-back |
| Precedence feels mysterious to users | live "why this workspace" trace + Conflict Simulator + `weak`/`keepCurrent` knobs |
| Audio thrash on rapid switching | debounce + `enterDelay` + `minDwell` hysteresis, all tunable |
| OSS lets anyone strip the nag | expected (WinRAR honor system); paid = signed convenience + support; keep nag tasteful |
| Menu-bar/window SwiftUI inflates RSS | window lazy/released → back to `.accessory`; measured against ship gate |

---

## 19. Open questions (not blocking M0–M1)

- ~~Ambient preset library~~ — **DECIDED:** BYO (files/playlists + Spotify/Apple Music)
  first, with a bundled royalty-free starter set alongside.
- ~~Source license~~ — **DECIDED:** GPLv3 + paid key.
- `resumePrevious` fidelity across external players (exact track vs. just resume)?
- Multi-display Spaces: per-display workspaces, or the active display's space is *the* space?
- Workspace import/share format for a future community library.

---

*Sources: [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) ·
[LyricFever #94 (15.4 lockdown)](https://github.com/aviwad/LyricFever/issues/94) ·
[Apple: Spaces identification](https://developer.apple.com/forums/thread/71058) ·
[Apple: notarizing](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) ·
[private API + notarization](https://developer.apple.com/forums/thread/702740) ·
[Energy Efficiency Guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/index.html) ·
[Focus mode via Assertions.json](https://gist.github.com/drewkerr/0f2b61ce34e2b9e3ce0ec6a92ab05c18) ·
[CoreMediaIO camera-in-use](https://developer.apple.com/documentation/coremediaio)*
