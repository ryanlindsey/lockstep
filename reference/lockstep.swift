// lockstep.swift
//
// Sets the default output device's sample rate — and verifies it took.
//
//   swiftc -O reference/lockstep.swift -o ~/bin/lockstep
//
//   lockstep            print device, current rate, and supported rates
//   lockstep 96000      set the rate to 96 kHz
//   lockstep --watch --devices "A,B"
//                       follow Apple Music onto an allowlisted device
//   lockstep --help     usage
//
// This is the reference implementation. You do not need it — it is what the
// specs in ../specs/ produce. See ./README.md.
//
// Part of lockstep — https://github.com/ryanlindsey/lockstep — MIT.

import CoreAudio
import Foundation
import ScriptingBridge

func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
}

func defaultOutputDevice() -> AudioDeviceID? {
    var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
    guard status == noErr, device != 0 else { return nil }
    return device
}

// Read as Unmanaged<CFString>, not CFString. Unmanaged is a trivial type, so
// forming a pointer to it is safe; pointing CoreAudio at a CFString variable
// directly is an ARC hazard and warns.
func name(of device: AudioDeviceID) -> String {
    var addr = address(kAudioObjectPropertyName)
    var unmanaged: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &unmanaged)
    guard status == noErr, let cfName = unmanaged?.takeRetainedValue() else {
        return "(unknown)"
    }
    return cfName as String
}

func currentRate(of device: AudioDeviceID) -> Double? {
    var addr = address(kAudioDevicePropertyNominalSampleRate)
    var rate = Float64(0)
    var size = UInt32(MemoryLayout<Float64>.size)
    let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &rate)
    return status == noErr ? rate : nil
}

func supportedRanges(of device: AudioDeviceID) -> [AudioValueRange] {
    var addr = address(kAudioDevicePropertyAvailableNominalSampleRates)
    var size = UInt32(0)
    guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr else { return [] }
    let count = Int(size) / MemoryLayout<AudioValueRange>.size
    guard count > 0 else { return [] }
    var ranges = [AudioValueRange](
        repeating: AudioValueRange(mMinimum: 0, mMaximum: 0), count: count)
    guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &ranges) == noErr else {
        return []
    }
    return ranges
}

// Endpoints, for display. Most USB DACs report discrete rates (mMinimum ==
// mMaximum); a few report a continuous span, and both ends are shown.
func rates(in ranges: [AudioValueRange]) -> [Double] {
    ranges
        .flatMap { $0.mMinimum == $0.mMaximum ? [$0.mMinimum] : [$0.mMinimum, $0.mMaximum] }
        .sorted()
}

// Membership has to consult the ranges, not the flattened endpoints: a device
// reporting a continuous span supports every rate between its two ends, and
// checking against the endpoint list alone would reject rates it accepts.
func supports(_ rate: Double, _ ranges: [AudioValueRange]) -> Bool {
    ranges.contains { rate >= $0.mMinimum && rate <= $0.mMaximum }
}

enum SetResult {
    case verified(Double)
    case failed(String)
}

func setRate(_ target: Double, on device: AudioDeviceID) -> SetResult {
    var addr = address(kAudioDevicePropertyNominalSampleRate)
    var value = Float64(target)
    let status = AudioObjectSetPropertyData(
        device, &addr, 0, nil, UInt32(MemoryLayout<Float64>.size), &value)
    guard status == noErr else {
        return .failed("CoreAudio rejected the change (status \(status))")
    }
    // A noErr status is not proof. CoreAudio can report success for a change the
    // driver has not applied, and a USB DAC needs a moment to relock its clock.
    // Poll for up to a second, then report what the device actually says.
    for _ in 0..<20 {
        usleep(50_000)
        if let now = currentRate(of: device), now == target {
            return .verified(now)
        }
    }
    let observed = currentRate(of: device).map { String(format: "%.0f", $0) } ?? "unknown"
    return .failed("device reports \(observed) Hz after the change")
}

func formatted(_ rates: [Double]) -> String {
    rates.map { String(format: "%.0f", $0) }.joined(separator: ", ")
}

// --- phase 2: watching -------------------------------------------------------

// Line-buffer stdout. launchd redirects it to a file, and a block-buffered
// stream holds hours of events in memory before any of them reach the log —
// including the events an acceptance test is sitting there waiting to read.
// This is one line and it is not optional.
func lineBufferStdout() {
    setvbuf(stdout, nil, _IOLBF, 0)
}

let timestamps = ISO8601DateFormatter()

// One line per event: timestamp, verb, reason. The verb is the second
// whitespace-separated field, which is how test-lockstep-watch.sh reads it.
// Keep that shape — see specs/phase-2-automatic-switching.md.
func log(_ verb: String, _ reason: String) {
    let padded = verb.padding(toLength: 5, withPad: " ", startingAt: 0)
    print("\(timestamps.string(from: Date()))  \(padded)  \(reason)")
}

// The source seam. One protocol, one conformance, in this file, five lines.
// It marks where a second source would attach and is not package architecture —
// see docs/design/2026-08-30-repo-design.md §8. It returns play state and rate
// together because the gate needs both, and asking Music twice to answer one
// question costs an Apple Event for nothing.
struct SourceState {
    let isPlaying: Bool
    let rate: Double?
}

protocol NowPlayingSource {
    func currentState() -> SourceState?
}

// 'kPSP' — MusicEPlSPlaying. Player state arrives as a four-character code in
// an NSNumber.
let musicPlaying: UInt32 = 0x6B50_5350

struct MusicSource: NowPlayingSource {
    // SBObject dispatches valueForKey: against Music's sdef, so `player state`
    // and `sample rate` are readable by name with no generated header — which
    // matters, because a single file compiled with swiftc has nowhere to put
    // one. Proven by probes/can-swift-read-music-rate.swift before it was
    // written here.
    func currentState() -> SourceState? {
        guard let music = SBApplication(bundleIdentifier: "com.apple.Music") else { return nil }
        // Never launch Music just to ask it a question.
        guard music.isRunning else { return nil }
        guard let state = (music.value(forKey: "playerState") as? NSNumber)?.uint32Value,
              state == musicPlaying else {
            return SourceState(isPlaying: false, rate: nil)
        }
        guard let track = music.value(forKey: "currentTrack") as? SBObject,
              let hz = (track.value(forKey: "sampleRate") as? NSNumber)?.intValue,
              hz > 0 else {
            return SourceState(isPlaying: true, rate: nil)
        }
        return SourceState(isPlaying: true, rate: Double(hz))
    }
}

// Same family only. 44.1 kHz material belongs at 44.1, 88.2 or 176.4; converting
// it to 48 is the awkward resample lockstep exists to avoid. Multiples are tried
// before divisors because integer upsampling discards nothing and decimation
// does — see docs/decisions/0011-fallback-works-in-both-directions.md.
func chooseRate(for source: Double, from ranges: [AudioValueRange]) -> Double? {
    if supports(source, ranges) { return source }
    for factor in [2.0, 4.0, 8.0] where supports(source * factor, ranges) {
        return source * factor
    }
    for divisor in [2.0, 4.0] where supports(source / divisor, ranges) {
        return source / divisor
    }
    return nil
}

// Comma-separated, and it lives in the LaunchAgent's ProgramArguments — see
// docs/decisions/0009-allowlist-lives-in-the-launchd-plist.md. Returns nil for
// a missing or empty list, which the caller turns into an exit rather than into
// "watch everything".
// CoreAudio hands back the name the driver reports, and drivers are not careful:
// the reference DAC calls itself "CA DacMagic 200M 2.0 " — with a trailing space.
// A reader who copies that name out of `lockstep` into the plist copies a
// character they cannot see, and an exact match then fails forever with a log
// line that looks correct. Both sides are trimmed so the invisible character
// cannot decide anything — see
// docs/decisions/0012-device-names-are-matched-trimmed.md.
func matches(_ deviceName: String, _ allowed: [String]) -> Bool {
    let target = deviceName.trimmingCharacters(in: .whitespaces)
    return allowed.contains { $0.trimmingCharacters(in: .whitespaces) == target }
}

func allowlist(from arguments: [String]) -> [String]? {
    guard let flag = arguments.firstIndex(of: "--devices") else { return nil }
    let value = arguments.index(after: flag)
    guard value < arguments.endIndex else { return nil }
    let names = arguments[value]
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    return names.isEmpty ? nil : names
}

func evaluate(_ source: NowPlayingSource, allowing allowed: [String]) {
    guard let state = source.currentState() else {
        log("skip", "Music is not running")
        return
    }
    guard state.isPlaying else {
        log("skip", "Music is not playing")
        return
    }
    // The device is decided before the rate is. A device we were told not to
    // touch is skipped for that reason whatever Music happens to be reporting,
    // and mid-track-change Music reports no rate at all for a moment — so
    // asking about the rate first makes the skip reason depend on timing.
    //
    // Re-read the device every time. The default output changes underneath a
    // long-running agent — that is the whole point of the allowlist.
    guard let device = defaultOutputDevice() else {
        log("error", "no default output device")
        return
    }
    let deviceName = name(of: device)
    guard matches(deviceName, allowed) else {
        log("skip", "\(deviceName) is not in the allowlist")
        return
    }
    guard let sourceRate = state.rate else {
        log("skip", "Music reports no sample rate for the current track")
        return
    }
    let ranges = supportedRanges(of: device)
    guard let target = chooseRate(for: sourceRate, from: ranges) else {
        log("skip", "\(String(format: "%.0f", sourceRate)) Hz has no same-family match on \(deviceName)")
        return
    }
    // The no-op guard is a correctness rule, not an optimisation: a set call is
    // an audible dropout, and if Music emits a playerInfo in response to one,
    // this is the line that stops the loop.
    if let now = currentRate(of: device), now == target {
        log("noop", "already at \(String(format: "%.0f", target)) Hz")
        return
    }
    switch setRate(target, on: device) {
    case .verified(let rate):
        let note = rate == sourceRate
            ? ""
            : "  (source \(String(format: "%.0f", sourceRate)) Hz unsupported)"
        log("set", "\(String(format: "%.0f", rate)) Hz — verified\(note)")
    case .failed(let reason):
        log("error", reason)
    }
}

// 400 ms, superseded rather than queued. Five skips fire five notifications;
// only the last evaluation should run, and it should read the track that is
// actually playing by the time it does.
let debounceSeconds = 0.4
var generation = 0

func scheduleEvaluation(_ source: NowPlayingSource, allowing allowed: [String]) {
    generation += 1
    let mine = generation
    DispatchQueue.main.asyncAfter(deadline: .now() + debounceSeconds) {
        guard mine == generation else { return }
        evaluate(source, allowing: allowed)
    }
}

func watch(allowing allowed: [String]) {
    lineBufferStdout()
    let source = MusicSource()
    print("allowlist: \(allowed.joined(separator: ", "))")
    print("watching:  com.apple.Music.playerInfo, \(Int(debounceSeconds * 1000)) ms debounce")

    DistributedNotificationCenter.default().addObserver(
        forName: NSNotification.Name("com.apple.Music.playerInfo"),
        object: nil,
        queue: .main
    ) { _ in
        log("event", "playerInfo")
        scheduleEvaluation(source, allowing: allowed)
    }

    // Evaluate once at startup, so logging in mid-track does not leave the
    // device mismatched until the next track boundary.
    scheduleEvaluation(source, allowing: allowed)
    RunLoop.main.run()
}

let usage = """
usage: lockstep [<sample-rate> | --watch --devices "<names>" | --help]

  lockstep            print the default output device, its current rate,
                      and every rate it supports
  lockstep 96000      set the default output device to 96000 Hz
  lockstep --watch --devices "CA DacMagic 200M 2.0"
                      follow Apple Music's sample rate, but only when one of
                      the named devices is the default output
  lockstep --help     print this message
"""

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("lockstep: \(message)\n".utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())

// Above the device guard, deliberately. A watcher started at login before the
// DAC has enumerated must not die on the spot — it logs an error per evaluation
// and recovers when the device appears. The one-shot invocations below still
// need the guard, so it stays exactly where it is.
if arguments.first == "--watch" {
    guard let allowed = allowlist(from: arguments) else {
        die("""
            --watch requires --devices with at least one device name

            \(usage)
            """)
    }
    watch(allowing: allowed)
    exit(0)
}

guard let device = defaultOutputDevice() else {
    die("no default output device")
}

if arguments.isEmpty {
    let available = rates(in: supportedRanges(of: device))
    print("device:    \(name(of: device))")
    print("current:   \(currentRate(of: device).map { String(format: "%.0f Hz", $0) } ?? "unknown")")
    print("supported: \(available.isEmpty ? "none reported" : formatted(available))")
    exit(0)
}

if arguments[0] == "--help" || arguments[0] == "-h" {
    print(usage)
    exit(0)
}

// `.isFinite` is load-bearing: Double("inf") and Double("1e30") both parse and
// are both greater than zero, and formatting either as an Int traps.
guard let target = Double(arguments[0]), target.isFinite, target > 0 else {
    die("not a sample rate: \(arguments[0])\n\n\(usage)")
}

let ranges = supportedRanges(of: device)
guard !ranges.isEmpty else {
    die("\(name(of: device)) reports no sample rates")
}
guard supports(target, ranges) else {
    die("""
        \(name(of: device)) does not support \(arguments[0]) Hz
        supported: \(formatted(rates(in: ranges)))
        """)
}

switch setRate(target, on: device) {
case .verified(let rate):
    print("\(name(of: device)) → \(String(format: "%.0f", rate)) Hz")
case .failed(let reason):
    die(reason)
}
