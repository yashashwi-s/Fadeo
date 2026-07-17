# Stop babysitting your Mac's audio: let it follow what you're doing

If you work with sound on all day, you know the little chore. You start some focus noise when you sit down. A meeting pops up and you dive for the pause button. You move to email and you want something calmer. You are the one doing all the switching, every time, all day.

I got tired of it, so I built a free tool to fix it: **Fadeo**.

Fadeo is a lightweight macOS menu bar app that plays, pauses, and switches your audio automatically based on what you are actually doing, and then shows you why it made each choice.

*[Insert the demo reel or a screenshot of the Now screen here. In the reel, the music pauses the moment the app decides to pause, which is the whole idea.]*

### What it reacts to

- **The app you are in.** Open your editor and your focus sound starts. Switch to a browser and it can do something different.
- **Meetings.** When your camera or mic goes live, Fadeo pauses whatever is playing, then brings it back when the call ends. You never blast music into a call again.
- **Your desktop Space, your Focus mode, and the time of day.** Different context, different sound, without you touching anything.

You set up "workspaces" once, with simple rules, and Fadeo resolves which one wins. If it ever does something surprising, the Now screen tells you exactly why.

### Why it is better than the usual options

- **It automates.** Ambient-sound apps are lovely, but you still press play. Fadeo does not make you.
- **It uses your music.** It can generate ambient sound on device (brown, pink, white noise, rain, ocean, wind, fan), or it can drive your own Spotify and Apple Music, including a specific playlist. You are not locked into someone else's library or a subscription.
- **It respects your Mac.** It is event driven, so it sits near 0% CPU when nothing is happening, and it never touches your system volume. Your volume keys keep working exactly as before.

### How to get it

Because it is a free, independent tool, it is not in the Mac App Store, but installing it takes under a minute.

Method 1: Direct download
1. Go to the site: https://puremac.yashashwi.me/puremac/fadeo
2. Download the app, drag it to Applications, and launch it.
3. Because I am an indie developer without a paid Apple account yet, macOS will ask you to confirm the first time. Just right-click the app and choose Open.

Method 2: Homebrew
```bash
brew tap yashashwi-s/tap
brew trust yashashwi-s/tap
brew install --cask fadeo
```

It is completely free and open source, and the first 100 people get a free lifetime license. macOS 14 and up.

Your Mac should already know when to play the right thing, and when to shut up. Give Fadeo a try and let your audio follow you instead of the other way around.

Project and source: https://github.com/yashashwi-s/Fadeo
