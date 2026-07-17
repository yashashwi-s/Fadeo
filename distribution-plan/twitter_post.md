# Twitter / X

**Main post (attach the demo reel):**

Your Mac should already know when to shut up. 🎧

Meet **Fadeo**: a free, open-source menu bar app that plays, pauses, and switches your audio based on what you're doing. Open your editor, it plays. A call starts, it pauses. Move desktops, it switches. And it tells you why.

▶️ In the clip, the music pauses the exact moment the app decides to.

🎚️ On-device ambient sound, or your own Spotify / Apple Music
🧠 Reacts to your app, desktop, meetings, Focus, and time
🔇 Never touches your system volume
🪶 Event driven, near 0% CPU at idle

Free forever. First 100 lifetime licenses are free.
🔗 https://puremac.yashashwi.me/puremac/fadeo

macOS 14+ · open source (GPLv3) · first launch needs right-click > Open (ad-hoc signed for now)

#macOS #MacApps #SwiftUI #IndieDev #OpenSource #MacSetup @Apple

**Optional reply / thread hook:**

Nerdy bit: the logic that decides which rule wins is a pure Swift package with zero dependencies, unit tested without a Mac in the loop. The OS glue (private CGS Space read, MediaRemote, mic/camera listeners) stays thin behind a small sensor protocol. Code: https://github.com/yashashwi-s/Fadeo
