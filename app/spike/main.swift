// Spike: prove that a Core Audio process tap can capture system audio from an
// ad-hoc signed bundle on this machine, alongside the microphone, through a
// single aggregate device so Core Audio owns the clock sync between them.
//
// Throwaway. See agent-os/specs/2026-09-01-0255-macos-recording-app/plan.md,
// Task 2. It records for a fixed duration and writes three WAV files plus a log
// reporting the peak level of each source, so "both sources arrived" is a number
// rather than a listening impression.

import AVFoundation
import AppKit
import AudioToolbox
import CoreAudio
import Foundation

// MARK: - Configuration

let captureSeconds = 15.0
let outputDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/record-transcriber-spike")

// MARK: - Logging

// The bundle is launched through LaunchServices so that macOS attributes the
// permission prompts to it rather than to the terminal that started it, which
// means stdout goes nowhere. The log file is the only record.
final class Log {
    private let handle: FileHandle?

    init(path: URL) {
        try? FileManager.default.createDirectory(at: path.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path.path, contents: nil)
        handle = try? FileHandle(forWritingTo: path)
    }

    func line(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "\(stamp) \(message)\n"
        FileHandle.standardError.write(Data(text.utf8))
        handle?.write(Data(text.utf8))
    }
}

let log = Log(path: outputDirectory.appendingPathComponent("spike.log"))

// MARK: - Core Audio helpers

struct CoreAudioError: Error, CustomStringConvertible {
    let call: String
    let status: OSStatus

    var description: String { "\(call) failed: \(fourCC(status)) (\(status))" }
}

/// fourCC renders an OSStatus the way Core Audio spells it in its headers, since
/// most of its errors are printable four-character codes rather than numbers.
func fourCC(_ status: OSStatus) -> String {
    let bits = UInt32(bitPattern: status)
    let bytes = [UInt8(truncatingIfNeeded: bits >> 24), UInt8(truncatingIfNeeded: bits >> 16),
                 UInt8(truncatingIfNeeded: bits >> 8), UInt8(truncatingIfNeeded: bits)]
    guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }) else { return String(status) }
    return "'" + String(bytes: bytes, encoding: .ascii)! + "'"
}

func check(_ call: String, _ status: OSStatus) throws {
    guard status == noErr else { throw CoreAudioError(call: call, status: status) }
}

func address(_ selector: AudioObjectPropertySelector,
             _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
    -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                               mElement: kAudioObjectPropertyElementMain)
}

func fixedSizeProperty<T>(_ objectID: AudioObjectID,
                          _ selector: AudioObjectPropertySelector,
                          _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                          _ label: String) throws -> T {
    var addr = address(selector, scope)
    var size = UInt32(MemoryLayout<T>.size)
    let buffer = UnsafeMutablePointer<T>.allocate(capacity: 1)
    defer { buffer.deallocate() }
    try check("AudioObjectGetPropertyData(\(label))",
              AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, buffer))
    return buffer.pointee
}

func stringProperty(_ objectID: AudioObjectID,
                    _ selector: AudioObjectPropertySelector,
                    _ label: String) throws -> String {
    var addr = address(selector)
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    // Core Audio hands back a +1 reference, so it is taken as retained rather
    // than read through a managed CFString variable.
    var value: Unmanaged<CFString>?
    try check("AudioObjectGetPropertyData(\(label))",
              AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, &value))
    guard let value else { throw CoreAudioError(call: label, status: kAudioHardwareUnspecifiedError) }
    return value.takeRetainedValue() as String
}

/// inputChannelCounts reports the channel count of each input stream, in the
/// order the IOProc will present them. An aggregate device lists its sub-device
/// streams before its tap streams, which is how the two sources are told apart.
func inputChannelCounts(_ deviceID: AudioObjectID) throws -> [Int] {
    var addr = address(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeInput)
    var size: UInt32 = 0
    try check("AudioObjectGetPropertyDataSize(stream configuration)",
              AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size))

    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                               alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    try check("AudioObjectGetPropertyData(stream configuration)",
              AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, raw))

    let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    return list.map { Int($0.mNumberChannels) }
}

// MARK: - Capture buffers

/// Capture holds the three mono tracks. Buffers are preallocated so the IOProc,
/// which runs on a real-time thread, never allocates.
final class Capture {
    let capacity: Int
    let mic: UnsafeMutablePointer<Float>
    let system: UnsafeMutablePointer<Float>
    private(set) var frames = 0
    private(set) var micPeak: Float = 0
    private(set) var systemPeak: Float = 0

    /// micChannels is how many leading channels of the IOProc's input belong to
    /// the microphone; everything after them comes from the tap.
    let micChannels: Int

    init(capacity: Int, micChannels: Int) {
        self.capacity = capacity
        self.micChannels = micChannels
        mic = .allocate(capacity: capacity)
        system = .allocate(capacity: capacity)
        mic.initialize(repeating: 0, count: capacity)
        system.initialize(repeating: 0, count: capacity)
    }

    deinit {
        mic.deallocate()
        system.deallocate()
    }

    var isFull: Bool { frames >= capacity }

    func append(_ bufferList: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: bufferList))

        // Every buffer carries the same frame count; the first one sets it.
        var frameCount = 0
        for buffer in buffers where buffer.mNumberChannels > 0 {
            frameCount = Int(buffer.mDataByteSize) /
                (MemoryLayout<Float>.size * Int(buffer.mNumberChannels))
            break
        }
        guard frameCount > 0 else { return }
        let writable = min(frameCount, capacity - frames)
        guard writable > 0 else { return }

        let base = frames
        for index in 0..<writable {
            mic[base + index] = 0
            system[base + index] = 0
        }

        var channelOffset = 0
        var micCount = 0
        var systemCount = 0

        for buffer in buffers {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0, let raw = buffer.mData else { continue }
            let samples = raw.assumingMemoryBound(to: Float.self)

            for channel in 0..<channels {
                let isMic = channelOffset + channel < micChannels
                let destination = isMic ? mic : system
                for frame in 0..<writable {
                    destination[base + frame] += samples[frame * channels + channel]
                }
                if isMic { micCount += 1 } else { systemCount += 1 }
            }
            channelOffset += channels
        }

        // Average rather than sum, so a stereo source is not twice as loud as a
        // mono one before the two tracks are mixed.
        for index in 0..<writable {
            if micCount > 1 { mic[base + index] /= Float(micCount) }
            if systemCount > 1 { system[base + index] /= Float(systemCount) }
            micPeak = max(micPeak, abs(mic[base + index]))
            systemPeak = max(systemPeak, abs(system[base + index]))
        }

        frames = base + writable
    }
}

// MARK: - WAV output

/// writeWAV writes mono 16-bit PCM, which is what `afplay` and ffmpeg both open
/// without argument.
func writeWAV(_ url: URL, samples: UnsafePointer<Float>, count: Int, sampleRate: Double) throws {
    var data = Data()
    let byteCount = count * 2

    func append<T>(_ value: T) {
        withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
    }

    data.append(contentsOf: Array("RIFF".utf8))
    append(UInt32(36 + byteCount))
    data.append(contentsOf: Array("WAVEfmt ".utf8))
    append(UInt32(16))                      // PCM header size
    append(UInt16(1))                       // format: PCM
    append(UInt16(1))                       // channels
    append(UInt32(sampleRate))
    append(UInt32(sampleRate) * 2)          // byte rate
    append(UInt16(2))                       // block align
    append(UInt16(16))                      // bits per sample
    data.append(contentsOf: Array("data".utf8))
    append(UInt32(byteCount))

    var pcm = [Int16](repeating: 0, count: count)
    for index in 0..<count {
        let clamped = max(-1, min(1, samples[index]))
        pcm[index] = Int16(clamped * 32767)
    }
    pcm.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }

    try data.write(to: url)
}

// MARK: - Microphone permission

/// requestMicrophoneAccess blocks the calling thread until the user answers.
/// It must not run on the main thread: macOS presents the prompt through the
/// main run loop, and blocking that run loop means the prompt never appears.
func requestMicrophoneAccess() -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
        return true
    case .denied, .restricted:
        return false
    default:
        break
    }

    var granted = false
    let answered = DispatchSemaphore(value: 0)
    AVCaptureDevice.requestAccess(for: .audio) { allowed in
        granted = allowed
        answered.signal()
    }
    answered.wait()
    return granted
}

// MARK: - Spike

func runSpike() throws {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    log.line("bundle: \(Bundle.main.bundleIdentifier ?? "<none>")")
    log.line("output: \(outputDirectory.path)")

    log.line("requesting microphone access")
    guard requestMicrophoneAccess() else {
        log.line("FAIL: microphone access denied")
        return
    }
    log.line("microphone access granted")

    // 1. The microphone, which becomes the aggregate device's clock master.
    let inputDeviceID: AudioObjectID = try fixedSizeProperty(
        AudioObjectID(kAudioObjectSystemObject),
        kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal,
        "default input device")
    guard inputDeviceID != kAudioObjectUnknown else {
        log.line("FAIL: no default input device")
        return
    }
    let inputUID = try stringProperty(inputDeviceID, kAudioDevicePropertyDeviceUID, "input device UID")
    let inputName = (try? stringProperty(inputDeviceID, kAudioObjectPropertyName, "input device name")) ?? "?"
    let micChannels = try inputChannelCounts(inputDeviceID).reduce(0, +)
    log.line("input device: \(inputName) [\(inputUID)], \(micChannels) input channel(s)")

    // 2. The tap. A mono global tap excluding nothing captures everything else
    //    playing on the machine; this process itself produces no audio, so there
    //    is nothing to feed back.
    let tapDescription = CATapDescription(monoGlobalTapButExcludeProcesses: [])
    tapDescription.name = "Record Transcriber Spike Tap"
    tapDescription.uuid = UUID()
    tapDescription.isPrivate = true
    tapDescription.muteBehavior = .unmuted

    var tapID = AudioObjectID(kAudioObjectUnknown)
    log.line("creating process tap (this is where macOS asks for audio capture permission)")
    try check("AudioHardwareCreateProcessTap", AudioHardwareCreateProcessTap(tapDescription, &tapID))
    defer {
        AudioHardwareDestroyProcessTap(tapID)
        log.line("tap destroyed")
    }
    log.line("tap created: id \(tapID), uid \(tapDescription.uuid.uuidString)")

    if let tapFormat: AudioStreamBasicDescription = try? fixedSizeProperty(
        tapID, kAudioTapPropertyFormat, kAudioObjectPropertyScopeGlobal, "tap format") {
        log.line("tap format: \(tapFormat.mSampleRate) Hz, \(tapFormat.mChannelsPerFrame) channel(s)")
    }

    // 3. One aggregate device holding both, so Core Audio does the drift
    //    compensation instead of us reconciling two independent clocks.
    let aggregateDescription: [String: Any] = [
        kAudioAggregateDeviceNameKey: "Record Transcriber Spike",
        kAudioAggregateDeviceUIDKey: UUID().uuidString,
        kAudioAggregateDeviceMainSubDeviceKey: inputUID,
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceIsStackedKey: false,
        kAudioAggregateDeviceTapAutoStartKey: true,
        kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: inputUID]],
        kAudioAggregateDeviceTapListKey: [[
            kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
            kAudioSubTapDriftCompensationKey: true,
        ]],
    ]

    var aggregateID = AudioObjectID(kAudioObjectUnknown)
    try check("AudioHardwareCreateAggregateDevice",
              AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID))
    defer {
        AudioHardwareDestroyAggregateDevice(aggregateID)
        log.line("aggregate device destroyed")
    }

    let counts = try inputChannelCounts(aggregateID)
    let sampleRate: Float64 = try fixedSizeProperty(
        aggregateID, kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal,
        "aggregate sample rate")
    log.line("aggregate device: id \(aggregateID), \(sampleRate) Hz, input streams \(counts)")
    guard counts.reduce(0, +) > micChannels else {
        log.line("FAIL: aggregate exposes \(counts.reduce(0, +)) channels but the mic alone has \(micChannels) — the tap contributed nothing")
        return
    }

    // 4. Capture.
    let capture = Capture(capacity: Int(sampleRate * captureSeconds), micChannels: micChannels)
    let finished = DispatchSemaphore(value: 0)
    var procID: AudioDeviceIOProcID?

    try check("AudioDeviceCreateIOProcIDWithBlock",
              AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) {
                  _, inputData, _, _, _ in
                  capture.append(inputData)
                  if capture.isFull { finished.signal() }
              })
    defer {
        if let procID { AudioDeviceDestroyIOProcID(aggregateID, procID) }
    }

    log.line("recording \(Int(captureSeconds))s — play something audible now")
    try check("AudioDeviceStart", AudioDeviceStart(aggregateID, procID))
    _ = finished.wait(timeout: .now() + captureSeconds + 5)
    try check("AudioDeviceStop", AudioDeviceStop(aggregateID, procID))

    // 5. Report and write.
    log.line("captured \(capture.frames) frames (\(String(format: "%.1f", Double(capture.frames) / sampleRate))s)")
    log.line(String(format: "microphone peak: %.4f", capture.micPeak))
    log.line(String(format: "system audio peak: %.4f", capture.systemPeak))

    let mixed = UnsafeMutablePointer<Float>.allocate(capacity: capture.frames)
    defer { mixed.deallocate() }
    for index in 0..<capture.frames {
        mixed[index] = max(-1, min(1, capture.mic[index] + capture.system[index]))
    }

    try writeWAV(outputDirectory.appendingPathComponent("mic.wav"),
                 samples: capture.mic, count: capture.frames, sampleRate: sampleRate)
    try writeWAV(outputDirectory.appendingPathComponent("system.wav"),
                 samples: capture.system, count: capture.frames, sampleRate: sampleRate)
    try writeWAV(outputDirectory.appendingPathComponent("mixed.wav"),
                 samples: mixed, count: capture.frames, sampleRate: sampleRate)
    log.line("wrote mic.wav, system.wav, mixed.wav")

    // The exit criterion, stated as a threshold so the result is not a judgement
    // call. -60 dBFS is below anything a real source produces and above the
    // noise a silent stream carries.
    let floorLevel: Float = 0.001
    if capture.micPeak > floorLevel, capture.systemPeak > floorLevel {
        log.line("PASS: both sources captured")
    } else {
        log.line("FAIL: mic above floor: \(capture.micPeak > floorLevel), system above floor: \(capture.systemPeak > floorLevel)")
    }
}

// An NSApplication is not decoration here: without one the process is not
// registered as something that can present UI, so the permission prompts are
// never issued and the request callback never fires. `.accessory` keeps it out
// of the Dock. The work runs off the main thread because the prompts are
// presented on the main run loop.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

DispatchQueue.global(qos: .userInitiated).async {
    do {
        try runSpike()
    } catch {
        log.line("FAIL: \(error)")
    }
    log.line("done")
    DispatchQueue.main.async { NSApp.terminate(nil) }
}

application.run()
