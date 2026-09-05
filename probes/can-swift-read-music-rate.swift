// can-swift-read-music-rate.swift
//
// Answers one question: can a compiled Swift binary read Apple Music's play
// state and the current track's sample rate — and by which route?
//
// Decision 0001 proved the property exists and reports true rates for streamed
// tracks. It proved that with osascript. "A single .swift file compiled with
// swiftc can read it" is a different claim, and phase 2 depends on the second
// one, so it is probed rather than assumed.
//
// Three routes, in the order phase 2 would prefer them:
//
//   A  ScriptingBridge + KVC          no header, no protocols, no subprocess
//   B  ScriptingBridge + @objc proto  the single-file stand-in for a generated header
//   C  osascript subprocess           known to work; here as the control
//
// C exists so a failure in A or B is distinguishable from Music being closed or
// Automation being denied. If C fails too, the problem is not the route.
//
// Read-only. It asks Music questions and changes nothing. Expect one Automation
// permission prompt the first time — grant it.
//
//   swiftc -O probes/can-swift-read-music-rate.swift -o /tmp/can-swift-read-music-rate
//   /tmp/can-swift-read-music-rate
//
// Start Music playing something first.
//
// Part of lockstep — https://github.com/ryanlindsey/lockstep — MIT.

import Foundation
import ScriptingBridge

// 'kPSP' — MusicEPlSPlaying, from Music's sdef. Player state comes back as a
// four-character code wrapped in an NSNumber.
let musicPlaying: UInt32 = 0x6B50_5350

// --- route A: ScriptingBridge + KVC -----------------------------------------
// SBObject dispatches valueForKey: against the application's sdef, so scripting
// properties can be read by the names it declares — `player state` is
// "playerState", `sample rate` is "sampleRate". No generated header required,
// which matters because a single file compiled with swiftc has nowhere to put
// one.
func routeKVC() -> String {
    guard let music = SBApplication(bundleIdentifier: "com.apple.Music") else {
        return "no SBApplication for com.apple.Music"
    }
    // Never launch Music just to ask it a question.
    guard music.isRunning else { return "Music is not running" }
    guard let state = (music.value(forKey: "playerState") as? NSNumber)?.uint32Value else {
        return "playerState unreadable"
    }
    guard state == musicPlaying else {
        return String(format: "playerState = 0x%08X (not playing)", state)
    }
    guard let track = music.value(forKey: "currentTrack") as? SBObject else {
        return "currentTrack unreadable"
    }
    guard let hz = (track.value(forKey: "sampleRate") as? NSNumber)?.intValue else {
        return "sampleRate unreadable"
    }
    return "playing, sampleRate = \(hz)"
}

// --- route B: ScriptingBridge + an @objc protocol ----------------------------
// Route B does not compile, and that is this probe's answer for it rather than
// a defect to be worked around. `@objc optional` requirements are reachable
// only through the protocol existential, never through the concrete conforming
// type, so declaring `extension SBApplication: MusicScripting {}` adds nothing
// that can be called on a value typed `SBApplication`. Swift 6.3.3 rejects it:
//
//   can-swift-read-music-rate.swift:81:29: error: value of type 'SBApplication'
//     has no member 'playerState'
//   can-swift-read-music-rate.swift:85:26: error: value of type 'SBApplication'
//     has no member 'currentTrack'
//
// The declarations are kept here, commented, because the next reader will
// otherwise try exactly this and hit exactly this.
//
//   @objc protocol MusicTrackScripting {
//       @objc optional var sampleRate: Int { get }
//   }
//
//   @objc protocol MusicScripting {
//       @objc optional var playerState: UInt32 { get }
//       @objc optional var currentTrack: MusicTrackScripting { get }
//   }
//
//   extension SBApplication: MusicScripting {}
//
//   func routeProtocol() -> String {
//       guard let music = SBApplication(bundleIdentifier: "com.apple.Music") else {
//           return "no SBApplication for com.apple.Music"
//       }
//       guard music.isRunning else { return "Music is not running" }
//       guard let state = music.playerState else { return "playerState unreadable" }
//       guard state == musicPlaying else {
//           return String(format: "playerState = 0x%08X (not playing)", state)
//       }
//       guard let hz = music.currentTrack?.sampleRate ?? nil else { return "sampleRate unreadable" }
//       return "playing, sampleRate = \(hz)"
//   }
func routeProtocol() -> String {
    return "unavailable — does not compile; see the note above this function"
}

// --- route C: osascript, the control ----------------------------------------
func routeOsascript() -> String {
    let script = """
    tell application "Music"
      if it is running then
        (player state as text) & " | " & (sample rate of current track as text)
      else
        "not running"
      end if
    end tell
    """
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", script]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    do {
        try task.run()
    } catch {
        return "could not run osascript: \(error.localizedDescription)"
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else {
        return "osascript exited \(task.terminationStatus)"
    }
    return String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// --- report ------------------------------------------------------------------
let kvc = routeKVC()
let proto = routeProtocol()
let shell = routeOsascript()

print("route A  ScriptingBridge + KVC          \(kvc)")
print("route B  ScriptingBridge + @objc proto  \(proto)")
print("route C  osascript subprocess           \(shell)")
print("")

let kvcWorks = kvc.hasPrefix("playing, sampleRate =")
let protoWorks = proto.hasPrefix("playing, sampleRate =")
let shellWorks = shell.contains("|")

if !shellWorks {
    print("RESULT: even the control failed. Music is probably not playing, or")
    print("Automation permission was denied. Fix that and run this again —")
    print("nothing can be concluded about routes A and B until C works.")
    exit(1)
}
if kvcWorks {
    print("RESULT: route A works. Phase 2 reads Music in-process, no subprocess")
    print("per event. Copy routeKVC into reference/lockstep.swift.")
    exit(0)
}
if protoWorks {
    print("RESULT: route A failed, route B works. Phase 2 uses the @objc protocol")
    print("declarations. Record why A failed in decision 0012.")
    exit(0)
}
print("RESULT: only route C works. Phase 2 must shell out to osascript once per")
print("evaluation. That is a departure from design §8, which specified")
print("ScriptingBridge — record it in decision 0012 before implementing it.")
exit(0)
