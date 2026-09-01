import CoreAudio
import Foundation

/// CoreAudioError carries the four-character code Core Audio actually returns,
/// because "exit status -10851" is not something anyone can act on.
struct CoreAudioError: LocalizedError {
    let call: String
    let status: OSStatus

    var errorDescription: String? { "\(call) failed: \(fourCharacterCode(status)) (\(status))" }
}

/// fourCharacterCode renders an OSStatus the way Core Audio spells it in its
/// headers, falling back to the number when it is not printable.
func fourCharacterCode(_ status: OSStatus) -> String {
    let bits = UInt32(bitPattern: status)
    let bytes = [UInt8(truncatingIfNeeded: bits >> 24), UInt8(truncatingIfNeeded: bits >> 16),
                 UInt8(truncatingIfNeeded: bits >> 8), UInt8(truncatingIfNeeded: bits)]
    guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }),
          let text = String(bytes: bytes, encoding: .ascii) else { return String(status) }
    return "'\(text)'"
}

func checkCoreAudio(_ call: String, _ status: OSStatus) throws {
    guard status == noErr else { throw CoreAudioError(call: call, status: status) }
}

enum CoreAudioProperty {
    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static func value<T>(_ objectID: AudioObjectID,
                         _ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                         label: String) throws -> T {
        var addr = address(selector, scope)
        var size = UInt32(MemoryLayout<T>.size)
        let buffer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { buffer.deallocate() }
        try checkCoreAudio("read \(label)",
                           AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, buffer))
        return buffer.pointee
    }

    static func string(_ objectID: AudioObjectID,
                       _ selector: AudioObjectPropertySelector,
                       label: String) throws -> String {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        // Core Audio hands back a +1 reference, so it is taken as retained
        // rather than read through a managed CFString variable.
        var value: Unmanaged<CFString>?
        try checkCoreAudio("read \(label)",
                           AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, &value))
        guard let value else {
            throw CoreAudioError(call: "read \(label)", status: kAudioHardwareUnspecifiedError)
        }
        return value.takeRetainedValue() as String
    }

    /// inputChannelCounts reports the channel count of each input stream, in the
    /// order an IOProc presents them. An aggregate device lists its sub-device
    /// streams before its tap streams, which is how the microphone is told apart
    /// from the system audio.
    static func inputChannelCounts(_ deviceID: AudioObjectID) throws -> [Int] {
        var addr = address(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        try checkCoreAudio("size of stream configuration",
                           AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size))

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        try checkCoreAudio("read stream configuration",
                           AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, raw))

        let list = UnsafeMutableAudioBufferListPointer(
            raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.map { Int($0.mNumberChannels) }
    }
}
