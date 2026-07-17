# How I built a context-aware audio engine for macOS that stays near 0% CPU

## A case study on an event-driven sensor pipeline, a pure Swift resolver, and free distribution via Homebrew.

I spend all day alt-tabbing, and my background audio never keeps up. I start brown noise when I open my editor, scramble to pause it when a call comes in, and switch it when I move to another desktop. I wanted my Mac to just do that. So I built Fadeo, a menu bar app that plays, pauses, and switches audio based on what you are doing. Here is how it works under the hood, and how I shipped it for free without the Apple Developer tax.

### 1. The whole thing is a pipeline, and the core is pure

The design is a one-way flow: sensors emit small context patches, a store merges them into a single snapshot, a resolver turns that snapshot into a decision, a reconciler diffs the decision against what is actually playing, and an actuator carries out only the delta.

The important part is that the resolver, the piece that decides which of your rules wins, is a pure function with no OS calls. It lives in its own Swift package with zero dependencies. You feed it a context and a config, and it returns a decision plus a human-readable reason. Because it never touches AppKit or the file system, it is unit tested without a Mac in the loop, and the behavior is deterministic instead of magic. That test suite is the actual guarantee behind "it does what you configured."

### 2. Every trigger is push, not poll

The efficiency goal was blunt: invisible in Activity Monitor at idle. That rules out timers and polling. So every signal is event driven:

- Frontmost app: NSWorkspace activation notifications.
- Desktop Space: the public space-changed notification plus a private CoreGraphics read for the index, behind a version-guarded shim that degrades gracefully.
- Meetings: CoreMediaIO and CoreAudio property listeners on camera and mic usage. Observing usage is not capturing, so this needs no camera or microphone permission prompt.
- Focus mode: an FSEvents watch on the Do Not Disturb assertions file.
- Schedules: a single next-boundary timer, armed for the next relevant time across all rules, and fully disarmed when no rule uses time.

Sensors are also lazily activated. A sensor whose fields no active rule references registers zero observers. At idle, with nothing changing, there is nothing running.

### 3. Sound without shipping a single audio file

For ambient sound, Fadeo does not ship loops. It synthesizes textures in a real-time render block: brown, pink, and white noise, plus rain, ocean, wind, and fan as DSP variations. No files, no looping seams, a tiny footprint, and the engine is fully torn down when nothing wants internal audio, so idle cost drops to zero. For your own music, a separate conductor drives Spotify and Apple Music through MediaRemote transport commands and AppleScript for playlist targeting, so you bring your own library instead of being locked into mine. And it never writes your system volume; each workspace mixes at its own relative level.

### 4. The distribution problem

Fadeo uses private frameworks and observes device usage, so it is not a Mac App Store app. Distributing a signed and notarized app outside the store needs a $99/year Apple Developer account, and this is a free, open-source tool. For now I distribute it ad-hoc signed, which means the first launch needs a right-click then Open to clear Gatekeeper. I say that up front everywhere, because hitting it cold feels broken when it is not.

### 5. Publishing to Homebrew

Homebrew Casks let people install securely from the terminal without notarization. The process:

1. Build the app with xcodebuild, ad-hoc signed.
2. Wrap the .app into a .dmg with hdiutil.
3. Host a Ruby cask in a homebrew-tap repo.

Then anyone can install it with:

brew tap yashashwi-s/tap
brew trust yashashwi-s/tap
brew install --cask fadeo

### Conclusion

The interesting constraint was doing all of this while staying invisible at idle. A push-based sensor layer, a pure resolver you can trust because it is tested without a Mac, and Homebrew for distribution got me the exact tool I wanted, for free.

It is open source (GPLv3), and the first 100 people get a free lifetime license. Code and download:
https://github.com/yashashwi-s/Fadeo
https://puremac.yashashwi.me/puremac/fadeo
