# Spike Result — system audio capture

**Verdict: pass.** Core Audio process taps work from an ad-hoc signed bundle on this
machine. Nothing in the plan changes; the ScreenCaptureKit fallback is not needed.

Run on macOS 26.6.2, Apple Silicon, 2026-09-01. Code: `app/spike/main.swift`.

## What was measured

```
input device: Micrófono de MacBook Pro [BuiltInMicrophoneDevice], 1 input channel(s)
tap created: id 150, uid 998DE2D4-375A-4933-BAAE-5BB61005A6A6
tap format: 48000.0 Hz, 1 channel(s)
aggregate device: id 151, 48000.0 Hz, input streams [1, 1]
captured 720000 frames (15.0s)
microphone peak: 0.0318
system audio peak: 0.3784
PASS: both sources captured
```

Confirmed independently with `ffmpeg -af volumedetect` on the three WAV files the spike
wrote: `system.wav` peaks at −8.4 dB (the sound played during the capture), `mic.wav` at
−30.0 dB (room noise; nobody spoke), and all three are exactly 15.00 s of 48 kHz mono.

720000 frames is 15.0 s at 48 kHz to the sample. The aggregate device delivered both
sources on one clock with no drift and no dropouts, which is the reason for putting the
microphone and the tap in one aggregate rather than running two capture paths.

## What the spike settled

**A mono global tap is enough.** `CATapDescription(monoGlobalTapButExcludeProcesses: [])`
yields a 1-channel 48 kHz tap. Since the recording format is mono anyway, this avoids a
stereo-to-mono mixdown in our own code.

**Channel order is sub-devices first, taps second.** The aggregate reported input streams
`[1, 1]`: the microphone's channel, then the tap's. Telling the two sources apart is a
matter of counting the sub-device's channels, which is what `Capture.micChannels` does.

**No prompt for the tap itself.** macOS asked for microphone access and nothing else;
`AudioHardwareCreateProcessTap` succeeded without a second prompt. The Info.plist keeps
`NSAudioCaptureUsageDescription` regardless, since its absence is what would make the call
fail on a system that does ask.

## What it cost to learn

**An `NSApplication` is mandatory, and this is the trap worth remembering.** The first run
hung for minutes on `AVCaptureDevice.requestAccess` with no prompt on screen and, tellingly,
no entry for the bundle anywhere in `tccd`'s log. A bundled executable without an
`NSApplication` is not registered as something that can present UI, so the prompt is never
issued and the completion handler never fires. The fix is three lines:

```swift
let application = NSApplication.shared
application.setActivationPolicy(.accessory)   // bundled, but no Dock icon
application.run()
```

with the audio work moved to a background queue, because the prompt is presented on the
main run loop and blocking that run loop reproduces the same hang. The real app carries
this over: `Recorder` never requests permission from the main thread.

## Reproducing

```sh
sh app/spike/build.sh
open bin/AudioSpike.app          # records 15 s, then quits
cat ~/Library/Application\ Support/record-transcriber-spike/spike.log
```
