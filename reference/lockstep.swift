// lockstep.swift
//
// Sets the default output device's sample rate — and verifies it took.
//
//   swiftc -O reference/lockstep.swift -o ~/bin/lockstep
//
//   lockstep            print device, current rate, and supported rates
//   lockstep 96000      set the rate to 96 kHz
//   lockstep --help     usage
//
// This is the reference implementation. You do not need it — it is what the
// specs in ../specs/ produce. See ./README.md.
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

let usage = """
usage: lockstep [<sample-rate> | --help]

  lockstep            print the default output device, its current rate,
                      and every rate it supports
  lockstep 96000      set the default output device to 96000 Hz
  lockstep --help     print this message
"""

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("lockstep: \(message)\n".utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())

guard let device = defaultOutputDevice() else {
    die("no default output device")
}

if arguments.isEmpty {
    let available = supportedRates(of: device)
    print("device:    \(name(of: device))")
    print("current:   \(currentRate(of: device).map { String(format: "%.0f Hz", $0) } ?? "unknown")")
    print("supported: \(available.isEmpty ? "none reported" : formatted(available))")
    exit(0)
}

if arguments[0] == "--help" || arguments[0] == "-h" {
    print(usage)
    exit(0)
}

guard let target = Double(arguments[0]), target > 0 else {
    die("not a sample rate: \(arguments[0])\n\n\(usage)")
}

let rates = supportedRates(of: device)
guard rates.contains(target) else {
    die("\(name(of: device)) does not support \(Int(target)) Hz\nsupported: \(formatted(rates))")
}

switch setRate(target, on: device) {
case .verified(let rate):
    print("\(name(of: device)) → \(Int(rate)) Hz")
case .failed(let reason):
    die(reason)
}
