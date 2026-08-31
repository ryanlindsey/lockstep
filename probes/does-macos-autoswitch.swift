// does-macos-autoswitch.swift
//
// Answers one question: does anything in macOS correct the output device's
// sample rate to match what is playing? If something does, lockstep is
// unnecessary and you should stop here.
//
// THIS PROBE CHANGES A SETTING. It forces the default output device to a
// supported rate that deliberately does not match your source, watches for
// 8 seconds, then restores the rate it found. Expect a click or a brief
// dropout. Start playing something first — the result is only meaningful
// during playback.
//
//   swiftc -O probes/does-macos-autoswitch.swift -o /tmp/does-macos-autoswitch
//   /tmp/does-macos-autoswitch
//
// Part of lockstep — https://github.com/ryanlindsey/lockstep — MIT.

import CoreAudio
import Foundation

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

func currentRate(of device: AudioDeviceID) -> Double? {
    var addr = address(kAudioDevicePropertyNominalSampleRate)
    var rate = Float64(0)
    var size = UInt32(MemoryLayout<Float64>.size)
    let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &rate)
    return status == noErr ? rate : nil
}

func supportedRates(of device: AudioDeviceID) -> [Double] {
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
        .flatMap { $0.mMinimum == $0.mMaximum ? [$0.mMinimum] : [$0.mMinimum, $0.mMaximum] }
        .sorted()
}

@discardableResult
func forceRate(_ target: Double, on device: AudioDeviceID) -> Bool {
    var addr = address(kAudioDevicePropertyNominalSampleRate)
    var value = Float64(target)
    let status = AudioObjectSetPropertyData(
        device, &addr, 0, nil, UInt32(MemoryLayout<Float64>.size), &value)
    return status == noErr
}

// Poll until the device reports `target`, or give up. A noErr status is not
// proof the driver applied the change — the same rule lockstep itself follows.
func settles(at target: Double, on device: AudioDeviceID) -> Bool {
    for _ in 0..<20 {
        usleep(50_000)
        if currentRate(of: device) == target { return true }
    }
    return false
}

// Restoring is a rate change like any other, so it is read back too. Saying
// "restored" without checking would be the same unproven claim the probe exists
// to warn about — and would leave a reader's DAC at the wrong rate in silence.
func restore(_ original: Double, on device: AudioDeviceID) {
    forceRate(original, on: device)
    if settles(at: original, on: device) {
        print("restored to \(Int(original)) Hz")
    } else {
        let observed = currentRate(of: device).map { String(format: "%.0f", $0) } ?? "unknown"
        FileHandle.standardError.write(Data(
            "WARNING: could not restore \(Int(original)) Hz — device reports \(observed) Hz.\n"
                .utf8))
    }
}

guard let device = defaultOutputDevice(), let original = currentRate(of: device) else {
    FileHandle.standardError.write(Data("no default output device\n".utf8))
    exit(1)
}

// Pick a supported rate that is deliberately wrong: the highest available,
// unless we are already there, in which case the lowest.
let rates = supportedRates(of: device)
guard let lowest = rates.first, let highest = rates.last, lowest != highest else {
    FileHandle.standardError.write(
        Data("device reports fewer than two distinct rates; nothing to test\n".utf8))
    exit(1)
}
let wrong = (original == highest) ? lowest : highest

print("original rate: \(Int(original)) Hz")
print("forcing:       \(Int(wrong)) Hz  (deliberately wrong)")
guard forceRate(wrong, on: device) else {
    FileHandle.standardError.write(Data("could not set the rate; aborting\n".utf8))
    exit(1)
}

// Confirm the device actually arrived before treating any later change as a
// correction. Without this, a device that advertises a rate it cannot hold
// looks identical to macOS auto-switching — and would tell you, wrongly, that
// you do not need lockstep.
guard settles(at: wrong, on: device) else {
    restore(original, on: device)
    print("")
    print("INCONCLUSIVE: the device advertises \(Int(wrong)) Hz but would not hold it.")
    print("Nothing can be concluded about auto-switching.")
    exit(1)
}

print("watching for 8 seconds…")
var corrected = false
var unreadable = false
for tick in 1...16 {
    usleep(500_000)
    // A failed read is not a correction. Treating it as one — the device was
    // unplugged, or CoreAudio returned an error — would tell the reader that
    // something follows the source and that they do not need lockstep.
    guard let now = currentRate(of: device) else {
        print(String(format: "  t+%.1fs: could not read the rate", Double(tick) * 0.5))
        unreadable = true
        break
    }
    print(String(format: "  t+%.1fs: %.0f Hz", Double(tick) * 0.5, now))
    if now != wrong { corrected = true; break }
}

restore(original, on: device)
print("")
if unreadable {
    print("INCONCLUSIVE: the device stopped reporting its rate — was it unplugged?")
    print("Nothing can be concluded about auto-switching.")
    exit(1)
}
print(corrected
    ? "RESULT: something corrected the rate — lockstep may be unnecessary on this system."
    : "RESULT: nothing corrected the rate — macOS does not follow the source. lockstep has a job.")
