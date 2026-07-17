# Hacker News: Show HN

**URL field:** https://puremac.yashashwi.me/puremac/fadeo

**Title:**
Show HN: Fadeo, a macOS app that plays and fades audio based on what I'm doing

**First comment (post right after submitting):**

I kept manually starting brown noise when I opened my editor, pausing it for calls, and switching to a playlist on my admin desktop. Fadeo does that switching for me.

It watches cheap signals: the frontmost app, which desktop Space you are on, whether the camera or mic is live, the current Focus mode, and time of day. You define audio "workspaces" with rules, it resolves which one wins, and it shows you why it chose. A live camera or mic pauses whatever is playing, so a meeting mutes it without me touching anything.

For sound it either synthesizes ambient textures on device (brown, pink, white noise, plus rain, ocean, wind, fan, no audio files shipped) or drives Spotify or Apple Music, including a specific playlist.

Two things I cared about. It is event driven with no polling, so it sits near 0% CPU when nothing changes. And it never touches your system volume; each workspace has its own level, your volume keys stay yours.

The part I am happiest with architecturally: the precedence logic that decides which rule wins is a pure Swift package with zero dependencies and no OS calls, so it is fully unit tested without a Mac in the loop. The OS glue on top (a private CoreGraphics Space read, MediaRemote commands, CoreMediaIO and CoreAudio listeners for the mic and camera) stays thin behind a small sensor protocol.

Free and open source (GPLv3). Honest heads up: I do not have an Apple Developer ID yet, so the app is ad-hoc signed. On first launch you right-click the app and choose Open to get past Gatekeeper. I would rather say that here than have you hit it cold. macOS 14 and up. The first 100 people can grab a free lifetime license on the site, though it is free to use regardless.

Happy to answer anything about the DSP, the private bridges, or the resolver design. Code: https://github.com/yashashwi-s/Fadeo

**Notes:** no exclamation marks, no "excited", answer every reply, do not ask anyone to
upvote.
