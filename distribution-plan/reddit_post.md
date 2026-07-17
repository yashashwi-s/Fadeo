# Subreddit: r/macapps or r/SideProject

**Title:** I built a free macOS app that plays, pauses, and switches your audio automatically based on what you're doing

**Body:**

Hey everyone,

I kept doing the same little chore all day: start brown noise when I open my editor, scramble to pause it when a call comes in, then move to another desktop for email and want something completely different. I wanted my Mac to just handle it.

So I built **Fadeo**, a menu bar app that picks what audio plays based on context instead of me choosing by hand. It is free and open source.

*[Attach the demo reel here: assets/marketing/fadeo-reel-landscape.mp4, or a GIF of it. The music in the reel literally pauses the moment the app decides to pause, which is the whole point.]*

**What it does:**
- **Reacts to real context:** the frontmost app, the desktop Space you are on, whether your camera or mic is live (so a meeting pauses your audio automatically), your Focus mode, and the time of day.
- **Tells you why:** a Now screen shows the active workspace and the exact reason it won, so the automation is never a mystery.
- **Your sound, or its own:** it synthesizes ambient textures on device (brown, pink, white noise, rain, ocean, wind, fan, no files shipped), or it conducts Spotify or Apple Music, including a specific playlist.
- **Never touches your system volume:** each workspace has its own level. Your volume keys stay yours.
- **Basically invisible:** it is event driven with no polling, so it sits near 0% CPU when nothing is happening.

**Why it is a bit different:**
- It automates instead of making you press play. Ambient-sound apps are great, but they are still manual.
- It does not lock you into its own library. Bring your own Spotify and Apple Music.
- The precedence engine (which rule wins when several match) is a pure Swift package tested without a Mac in the loop, so the behavior is predictable rather than magic.

**Free forever and open source (GPLv3).** There is an optional pay-what-you-want lifetime license ($2 minimum) that only removes a small occasional reminder, nothing is gated. The first 100 licenses are free on the site right now if you want to skip even that.

**Honest note:** no Apple Developer ID yet, so it is ad-hoc signed and the first launch needs a right-click then Open to clear Gatekeeper. Saying it up front.

**Download, demo video, and screenshots:** https://puremac.yashashwi.me/puremac/fadeo
**Source:** https://github.com/yashashwi-s/Fadeo

Or install via Homebrew:
```bash
brew tap yashashwi-s/tap
brew trust yashashwi-s/tap
brew install --cask fadeo
```

macOS 14 and up. This is the first public release, so I would genuinely love to hear where it breaks or what you would want next.
