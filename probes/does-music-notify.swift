// does-music-notify.swift
//
// Answers one question: is com.apple.Music.playerInfo delivered on this macOS,
// and does its payload already carry what phase 2 needs?
//
// Design §12 assumed the notification fires and never checked. Phase 2's whole
// trigger mechanism rests on it, so it gets checked before anything is built on
// top of it.
//
// Read-only. It observes; it changes nothing and makes no sound.
//
//   swiftc -O probes/does-music-notify.swift -o /tmp/does-music-notify
//   /tmp/does-music-notify
//
// Start Music playing first, then skip a few tracks, then pause, then play.
// With nothing playing there is nothing to be notified about.
//
// Part of lockstep — https://github.com/ryanlindsey/lockstep — MIT.

import Foundation

// Line-buffer stdout so each notification appears as it arrives rather than in
// one block at exit. A probe you cannot watch in real time is much less useful
// when the thing you are checking is timing.
setvbuf(stdout, nil, _IOLBF, 0)

let started = Date()
var count = 0

print("watching com.apple.Music.playerInfo for 60 seconds")
print("skip a few tracks, then pause, then play again")
print("")

DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name("com.apple.Music.playerInfo"),
    object: nil,
    queue: .main
) { note in
    count += 1
    print(String(format: "t+%.2fs  notification %d", Date().timeIntervalSince(started), count))
    let payload = note.userInfo ?? [:]
    if payload.isEmpty {
        print("    (no userInfo)")
    }
    for (key, value) in payload.sorted(by: { "\($0.key)" < "\($1.key)" }) {
        print("    \(key) = \(value)")
    }
    print("")
}

DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
    print("")
    guard count > 0 else {
        print("RESULT: nothing fired in 60 seconds.")
        print("Either Music was not running, or com.apple.Music.playerInfo is not")
        print("delivered here. Phase 2 needs the polling trigger instead — see")
        print("docs/decisions/0010-what-tells-the-watcher-a-track-changed.md.")
        exit(1)
    }
    print("RESULT: \(count) notifications in 60 seconds. The notification fires.")
    print("")
    print("Read the keys above, not this sentence: if one of them carries the")
    print("play state, the gate can read it without an Apple Event. If one")
    print("carries a sample rate, the ScriptingBridge query is unnecessary.")
    exit(0)
}

RunLoop.main.run()
