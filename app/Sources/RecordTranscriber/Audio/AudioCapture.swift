import AudioToolbox
import CoreAudio
import Foundation
import os

/// AudioCapture records the microphone and everything else playing on the
/// machine, mixed to one mono stream.
///
/// Both sources go into a single aggregate device rather than two capture paths,
/// so Core Audio owns the clock synchronization between them. Two independent
/// clocks drift apart over the length of a meeting, and reconciling them
/// afterwards is a worse problem than configuring the aggregate correctly once.
///
/// The system audio comes from a Core Audio process tap, native since macOS
/// 14.4 and needing no virtual audio driver.
final class AudioCapture {
    struct Levels: Equatable {
        var microphone: Float = 0
        var system: Float = 0
    }

    /// onAudio is called on the audio thread with one block of mixed mono
    /// samples. The buffer is valid only for the duration of the call, and the
    /// handler must not block, allocate, or wait on a lock a slow thread holds.
    var onAudio: ((UnsafeBufferPointer<Float>) -> Void)?

    private(set) var sampleRate: Double = 48000

    /// maximumFramesPerBlock bounds the mixing scratch buffer. Core Audio asks
    /// for far less than this per callback; anything larger is split.
    private static let maximumFramesPerBlock = 16384

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var micChannels = 0
    private let mixed = UnsafeMutablePointer<Float>.allocate(capacity: maximumFramesPerBlock)
    private let systemScratch = UnsafeMutablePointer<Float>.allocate(capacity: maximumFramesPerBlock)

    private var currentLevels = Levels()
    private let levelsLock = UnfairLock()

    deinit {
        stop()
        mixed.deallocate()
        systemScratch.deallocate()
    }

    /// levels is the most recent peak of each source. It is read from the main
    /// thread by the meter and written from the audio thread, which is why it
    /// sits behind a lock rather than being observed directly.
    var levels: Levels {
        levelsLock.locked { currentLevels }
    }

    func start() throws {
        let inputDeviceID: AudioObjectID = try CoreAudioProperty.value(
            AudioObjectID(kAudioObjectSystemObject),
            kAudioHardwarePropertyDefaultInputDevice,
            label: "default input device")
        guard inputDeviceID != kAudioObjectUnknown else {
            throw CoreAudioError(call: "find default input device", status: kAudioHardwareBadDeviceError)
        }

        let inputUID = try CoreAudioProperty.string(
            inputDeviceID, kAudioDevicePropertyDeviceUID, label: "input device UID")
        micChannels = try CoreAudioProperty.inputChannelCounts(inputDeviceID).reduce(0, +)

        // A mono global tap excluding nothing captures everything else playing.
        // This process produces no audio, so there is nothing to feed back.
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.name = "Record Transcriber"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted

        try checkCoreAudio("create process tap",
                           AudioHardwareCreateProcessTap(description, &tapID))

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Record Transcriber",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: inputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: inputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]

        do {
            try checkCoreAudio(
                "create aggregate device",
                AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID))

            sampleRate = try CoreAudioProperty.value(
                aggregateID, kAudioDevicePropertyNominalSampleRate, label: "sample rate")

            try checkCoreAudio(
                "install audio callback",
                AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) {
                    [weak self] _, inputData, _, _, _ in
                    self?.process(inputData)
                })
            try checkCoreAudio("start capture", AudioDeviceStart(aggregateID, procID))
        } catch {
            stop()
            throw error
        }
    }

    /// stop tears down every system resource the capture holds. It is safe to
    /// call more than once, and is called on every path out of recording,
    /// including a failed start: a leaked tap keeps a device alive for the rest
    /// of the login session.
    func stop() {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil

        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
        levelsLock.locked { currentLevels = Levels() }
    }

    /// process runs on the audio thread. It sums each source to mono, averaging
    /// within a source so a stereo one is not twice as loud as a mono one, then
    /// adds the two together.
    private func process(_ bufferList: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))

        var frames = 0
        for buffer in buffers where buffer.mNumberChannels > 0 {
            frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * Int(buffer.mNumberChannels))
            break
        }
        frames = min(frames, Self.maximumFramesPerBlock)
        guard frames > 0 else { return }

        // mixed accumulates the microphone, systemScratch the tap, so each can
        // be averaged over its own channel count before the two are added.
        var micCount = 0
        var systemCount = 0
        for index in 0..<frames {
            mixed[index] = 0
            systemScratch[index] = 0
        }

        var channelOffset = 0
        for buffer in buffers {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0, let raw = buffer.mData else { continue }
            let samples = raw.assumingMemoryBound(to: Float.self)

            for channel in 0..<channels {
                let isMicrophone = channelOffset + channel < micChannels
                let destination = isMicrophone ? mixed : systemScratch
                if isMicrophone { micCount += 1 } else { systemCount += 1 }
                for frame in 0..<frames {
                    destination[frame] += samples[frame * channels + channel]
                }
            }
            channelOffset += channels
        }

        let micScale = 1 / Float(max(1, micCount))
        let systemScale = 1 / Float(max(1, systemCount))
        var micPeak: Float = 0
        var systemPeak: Float = 0

        for index in 0..<frames {
            let microphone = mixed[index] * micScale
            let system = systemScratch[index] * systemScale
            micPeak = max(micPeak, abs(microphone))
            systemPeak = max(systemPeak, abs(system))
            mixed[index] = max(-1, min(1, microphone + system))
        }

        levelsLock.locked { currentLevels = Levels(microphone: micPeak, system: systemPeak) }
        onAudio?(UnsafeBufferPointer(start: mixed, count: frames))
    }
}
