// device-capabilities.swift
//
// Reports the current default output device and every sample rate it supports.
// Read-only: this probe never changes a setting.
//
//   swiftc -O probes/device-capabilities.swift -o /tmp/device-capabilities
//   /tmp/device-capabilities
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
    // Most USB DACs report discrete rates (mMinimum == mMaximum). A few report a
    // continuous span; show both ends so the reader can see which they have.
    return ranges
        .flatMap { $0.mMinimum == $0.mMaximum ? [$0.mMinimum] : [$0.mMinimum, $0.mMaximum] }
        .sorted()
}

guard let device = defaultOutputDevice() else {
    FileHandle.standardError.write(Data("no default output device\n".utf8))
    exit(1)
}

let rates = supportedRates(of: device)
print("device:    \(name(of: device))  (id \(device))")
print("current:   \(currentRate(of: device).map { String(format: "%.0f Hz", $0) } ?? "unknown")")
print("supported: \(rates.isEmpty ? "none reported" : rates.map { String(format: "%.0f", $0) }.joined(separator: ", "))")
