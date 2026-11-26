// Includes material adapted from AudioCap by Guilherme Rambo (copyright 2024).
// Upstream material retains BSD-2-Clause; see docs/Rambo-BSD-2-Clause.txt.

import Foundation
import AudioToolbox

// Sole definition of CoreAudioError
enum CoreAudioError: LocalizedError {
    case general(String)
    case propertyReadError(property: String, osStatus: OSStatus)
    case propertySizeError(property: String, osStatus: OSStatus)
    case operationNotSupportedForObject(String)
    case invalidPID(pid_t)

    public var errorDescription: String? {
        switch self {
        case .general(let message):
            return message
        case .propertyReadError(let property, let osStatus):
            return "Error reading property '\(property)': OSStatus \(osStatus)."
        case .propertySizeError(let property, let osStatus):
            return "Error reading size for property '\(property)': OSStatus \(osStatus)."
        case .operationNotSupportedForObject(let message):
            return message
        case .invalidPID(let pid):
            return "Invalid process identifier: \(pid)."
        }
    }
}

// MARK: - Constants

extension AudioObjectID {
    /// Convenience for `kAudioObjectSystemObject`.
    static let system = AudioObjectID(kAudioObjectSystemObject)
    /// Convenience for `kAudioObjectUnknown`.
    static let unknown = kAudioObjectUnknown

    /// `true` if this object has the value of `kAudioObjectUnknown`.
    var isUnknown: Bool { self == .unknown }

    /// `false` if this object has the value of `kAudioObjectUnknown`.
    var isValid: Bool { !isUnknown }
}

// MARK: - Concrete Property Helpers

extension AudioObjectID {

    /// Reads the value for `kAudioHardwarePropertyDefaultOutputDevice`.
    /// This is the regular default output (speakers/headphones), not the "system sounds" output.
    static func readDefaultOutputDevice() throws -> AudioDeviceID {
        try AudioObjectID.system.readDefaultOutputDevice()
    }

    /// Reads the value for `kAudioHardwarePropertyDefaultInputDevice`.
    static func readDefaultInputDevice() throws -> AudioDeviceID {
        try AudioObjectID.system.readDefaultInputDevice()
    }

    /// Reads the value for `kAudioHardwarePropertyDefaultOutputDevice`, should only be called on the system object.
    /// This is the regular default output (speakers/headphones), not the "system sounds" output.
    func readDefaultOutputDevice() throws -> AudioDeviceID {
        try requireSystemObject()
        return try read(kAudioHardwarePropertyDefaultOutputDevice, defaultValue: AudioDeviceID.unknown)
    }

    /// Reads the value for `kAudioHardwarePropertyDefaultInputDevice`, should only be called on the system object.
    func readDefaultInputDevice() throws -> AudioDeviceID {
        try requireSystemObject()
        return try read(kAudioHardwarePropertyDefaultInputDevice, defaultValue: AudioDeviceID.unknown)
    }

    /// Reads the value for `kAudioDevicePropertyDeviceUID` for the device represented by this audio object ID.
    func readDeviceUID() throws -> String { try readString(kAudioDevicePropertyDeviceUID) }

    /// Reads the value for `kAudioTapPropertyFormat` for the device represented by this audio object ID.
    func readAudioTapStreamBasicDescription() throws -> AudioStreamBasicDescription {
        try read(kAudioTapPropertyFormat, defaultValue: AudioStreamBasicDescription())
    }

    private func requireSystemObject() throws {
        if self != .system { throw CoreAudioError.operationNotSupportedForObject("Only supported for the system object.") }
    }
}

// MARK: - Generic Property Access

extension AudioObjectID {

    func read<T>(_ selector: AudioObjectPropertySelector,
                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                    defaultValue: T) throws -> T
    {
        try read(AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element), defaultValue: defaultValue)
    }

    func read<T>(_ address: AudioObjectPropertyAddress, defaultValue: T) throws -> T {
        try read(address, defaultValue: defaultValue, inQualifierSize: 0, inQualifierData: nil)
    }

    func readString(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) throws -> String {
        try read(AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element), defaultValue: "" as CFString) as String
    }

    private func read<T>(_ inAddress: AudioObjectPropertyAddress, defaultValue: T, inQualifierSize: UInt32 = 0, inQualifierData: UnsafeRawPointer? = nil) throws -> T {
        var address = inAddress
        var dataSize: UInt32 = 0
        var err = AudioObjectGetPropertyDataSize(self, &address, inQualifierSize, inQualifierData, &dataSize)

        guard err == noErr else {
            throw CoreAudioError.propertySizeError(property: String(describing: address), osStatus: err)
        }

        var value: T = defaultValue
        err = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(self, &address, inQualifierSize, inQualifierData, &dataSize, ptr)
        }

        guard err == noErr else {
            throw CoreAudioError.propertyReadError(property: String(describing: address), osStatus: err)
        }
        return value
    }
}

// MARK: - Debugging Helpers

private extension UInt32 {
    var fourCharString: String {
        String(cString: [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF),
            0
        ])
    }
}

extension AudioObjectPropertyAddress: @retroactive CustomStringConvertible {
    public var description: String {
        let elementDescription = mElement == kAudioObjectPropertyElementMain ? "main" : mElement.fourCharString
        return "\(mSelector.fourCharString)/\(mScope.fourCharString)/\(elementDescription)"
    }
}

extension AudioObjectID {
    func getAllHardwareDevices() throws -> [AudioDeviceID] {
        try requireSystemObject()

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var err = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &dataSize)
        guard err == noErr else {
            throw CoreAudioError.propertySizeError(property: kAudioHardwarePropertyDevices.fourCharString, osStatus: err)
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        if deviceCount == 0 {
            return []
        }
        var deviceIDs = [AudioDeviceID](repeating: .unknown, count: deviceCount)

        err = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, &deviceIDs)
        guard err == noErr else {
            throw CoreAudioError.propertyReadError(property: kAudioHardwarePropertyDevices.fourCharString, osStatus: err)
        }
        return deviceIDs
    }
}

// MARK: - Microphone Threshold Feature

/*
 The Jotley app now supports separate noise thresholds for microphone and system audio.

 This feature ensures that:
 1. Background noise from the microphone is filtered out based on a configurable RMS threshold
 2. System audio continues to use its existing threshold

 How it works:
 - Each audio buffer is analyzed to determine if it's from the microphone or system audio
 - For microphone audio, a much higher threshold is applied (default: 10x the system audio threshold)
 - The threshold is configurable through the ProcessTapRecorder.setMicrophoneThreshold method

 Usage:
 ```
 let recorder = ProcessTapRecorder(tap: processTap)
 // To adjust microphone sensitivity (higher value = less sensitive)
 recorder.setMicrophoneThreshold(0.02) // Example value, adjust based on testing
 ```
 */

extension AudioDeviceID {
    func getTotalOutputChannelCount() throws -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size)
        if status == kAudioHardwareUnknownPropertyError || size == 0 { return 0 }
        guard status == noErr else { throw CoreAudioError.general("Cannot read output channel count: \(status)") }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        let result = AudioObjectGetPropertyData(self, &address, 0, nil, &size, memory)
        guard result == noErr else { throw CoreAudioError.general("Cannot read output buffers: \(result)") }
        return UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self))
            .reduce(0) { $0 + $1.mNumberChannels }
    }
}
