// Includes material adapted from AudioCap by Guilherme Rambo (copyright 2024).
// Upstream material retains BSD-2-Clause; see docs/Rambo-BSD-2-Clause.txt.

import OSLog
import AVFoundation
import AudioToolbox
import SwiftUI

extension Notification.Name {
    static let processTapRecordingStateChanged = Notification.Name("processTapRecordingStateChanged")
}

enum TapTarget {
    case systemAudio

    var loggingProcessName: String {
        return "SystemAudioOutput"
    }
}

@Observable
final class ProcessTap {

    typealias InvalidationHandler = (ProcessTap) -> Void

    let target: TapTarget
    let muteWhenRunning: Bool
    let logger: Logger

    private(set) var errorMessage: String? = nil

    init(muteWhenRunning: Bool = false) {
        self.target = .systemAudio
        self.muteWhenRunning = muteWhenRunning
        self.logger = Logger(subsystem: LocalPaths.bundleID, category: "\(String(describing: ProcessTap.self))(\(self.target.loggingProcessName))")
    }

    @ObservationIgnored
    private var processTapID: AudioObjectID = .unknown
    @ObservationIgnored
    private var aggregateDeviceID = AudioObjectID.unknown
    @ObservationIgnored
    private var deviceProcID: AudioDeviceIOProcID?
    @ObservationIgnored
    private(set) var tapStreamDescription: AudioStreamBasicDescription?
    @ObservationIgnored
    public var aggregateDeviceStreamDescription: AudioStreamBasicDescription?
    @ObservationIgnored
    private var invalidationHandler: InvalidationHandler?

    @ObservationIgnored
    private(set) var activated = false

    @MainActor
    func activate() {
        // Skip only when the tap is already prepared AND usable. A previous
        // activation that failed inside prepare() leaves `activated == true` but no
        // valid tap/stream description — in that state we must re-prepare instead of
        // skipping forever. Otherwise the first record on a fresh install (which can
        // fail before audio permission is granted) poisons every later attempt and
        // the user can never start a recording.
        if activated, aggregateDeviceStreamDescription != nil, processTapID.isValid {
            return
        }
        activated = true

        logger.debug(#function)
        self.errorMessage = nil

        do {
            try prepare()
        } catch {
            logger.error("\(error, privacy: .public)")
            self.errorMessage = error.localizedDescription
        }
    }

    func invalidate() {
        guard activated else { return }
        defer { activated = false }

        logger.debug(#function)

        invalidationHandler?(self)
        self.invalidationHandler = nil

        if aggregateDeviceID.isValid {
            var err: OSStatus

            err = AudioDeviceStop(aggregateDeviceID, deviceProcID)
            if err != noErr {
                logger.warning("Failed to stop aggregate device: \(err, privacy: .public)")
            }

            if let deviceProcID {
                err = AudioDeviceDestroyIOProcID(aggregateDeviceID, deviceProcID)
                if err != noErr {
                    logger.warning("Failed to destroy device I/O proc: \(err, privacy: .public)")
                }
                self.deviceProcID = nil
            }

            err = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            if err != noErr {
                logger.warning("Failed to destroy aggregate device: \(err, privacy: .public)")
            }
            aggregateDeviceID = .unknown
        }

        if processTapID.isValid {
            let errTapDestroy = AudioHardwareDestroyProcessTap(processTapID)
            if errTapDestroy != noErr {
                logger.warning("Failed to destroy audio tap: \(errTapDestroy, privacy: .public)")
            }
            self.processTapID = .unknown
        }
    }

    private func prepare() throws {
        logger.info("-[ProcessTap prepare] CALLED")
        errorMessage = nil

        // Global tap continues capturing apps that start after recording begins.
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.uuid = UUID()
        logger.info("-[ProcessTap prepare] tapDescription.uuid: \(tapDescription.uuid.uuidString)")
        tapDescription.muteBehavior = muteWhenRunning ? .mutedWhenTapped : .unmuted
        logger.info("-[ProcessTap prepare] tapDescription.muteBehavior: \(self.muteWhenRunning ? "mutedWhenTapped" : "unmuted")")

        var tapID: AUAudioObjectID = .unknown
        let errTapCreation = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        logger.info("-[ProcessTap prepare] AudioHardwareCreateProcessTap result: OSStatus \(errTapCreation), tapID: \(tapID)")

        guard errTapCreation == noErr else {
            self.errorMessage = "System audio tap creation failed with error \(errTapCreation)"
            logger.error("-[ProcessTap prepare] \(self.errorMessage ?? "Unknown error")")
            throw CoreAudioError.general(self.errorMessage ?? "Unknown error creating tap.")
        }

        self.processTapID = tapID
        logger.info("-[ProcessTap prepare] Process tap successfully created. self.processTapID: \(self.processTapID)")

        let allDeviceIDs = try AudioObjectID.system.getAllHardwareDevices()
        logger.info("-[ProcessTap prepare] allDeviceIDs (hardware devices) fetched. Count: \(allDeviceIDs.count). IDs: \(allDeviceIDs.map { String($0) }.joined(separator: ", "))")

        var outputUIDs: [String] = []
        for devID in allDeviceIDs {
            do {
                let outputChans = try devID.getTotalOutputChannelCount()
                if outputChans > 0 {
                    let devUID = try devID.readDeviceUID()
                    outputUIDs.append(devUID)
                    logger.info("-[ProcessTap prepare] Found output device: ID \(devID), UID \(devUID), OutputChannels \(outputChans)")
                }
            } catch {
                logger.warning("-[ProcessTap prepare] Ignored device \(devID) while checking output channels: \(error.localizedDescription)")
            }
        }

        if outputUIDs.isEmpty {
            logger.error("-[ProcessTap prepare] No hardware output devices found with output channels!")
            throw CoreAudioError.general("No hardware output devices found!")
        }
        logger.info("-[ProcessTap prepare] outputUIDs collected. Count: \(outputUIDs.count). UIDs: \(outputUIDs.joined(separator: ", "))")

        let systemOutputID: AudioDeviceID
        do {
            // Use the regular default output device (speakers/headphones), not the "system sounds" output
            // This avoids issues where virtual audio devices like BlackHole are set as system output
            systemOutputID = try AudioDeviceID.readDefaultOutputDevice()
            logger.info("-[ProcessTap prepare] Default output device ID: \(systemOutputID)")
        } catch {
            logger.error("-[ProcessTap prepare] Failed to read default output device ID: \(error.localizedDescription)")
            throw error
        }

        let mainSubdeviceUID: String
        do {
            mainSubdeviceUID = try systemOutputID.readDeviceUID()
            logger.info("-[ProcessTap prepare] Main subdevice UID (from default output): \(mainSubdeviceUID)")
        } catch {
            logger.error("-[ProcessTap prepare] Failed to read device UID for systemOutputID \(systemOutputID): \(error.localizedDescription)")
            throw error
        }

        let microphoneDeviceID: AudioDeviceID
        do {
            microphoneDeviceID = try AudioDeviceID.readDefaultInputDevice()
            logger.info("-[ProcessTap prepare] Default microphone device ID: \(microphoneDeviceID)")
            print("🎤 [ProcessTap prepare] Successfully found microphone device ID: \(microphoneDeviceID)")
        } catch {
            logger.error("-[ProcessTap prepare] Failed to read default microphone device ID: \(error.localizedDescription)")
            print("❌ [ProcessTap prepare] Failed to get microphone: \(error.localizedDescription)")
            throw error
        }

        let microphoneUID: String
        do {
            microphoneUID = try microphoneDeviceID.readDeviceUID()
            logger.info("-[ProcessTap prepare] Microphone UID: \(microphoneUID)")
            print("🎤 [ProcessTap prepare] Microphone UID: \(microphoneUID)")
        } catch {
            logger.error("-[ProcessTap prepare] Failed to read device UID for microphoneDeviceID \(microphoneDeviceID): \(error.localizedDescription)")
            print("❌ [ProcessTap prepare] Failed to read microphone UID: \(error.localizedDescription)")
            throw error
        }

        let aggregateDeviceName = "Tap-MicSysAgg-\(mainSubdeviceUID.prefix(8))"
        let subDeviceListForAggregate: [[String: String]] = [
            [kAudioSubDeviceUIDKey: mainSubdeviceUID],  // System audio first (more reliable)
            [kAudioSubDeviceUIDKey: microphoneUID]      // Microphone second
        ]
        let aggregateUID = UUID().uuidString

        let descriptionForAggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: aggregateDeviceName,
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: mainSubdeviceUID,  // Use system audio as main device
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceSubDeviceListKey: subDeviceListForAggregate,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]
        logger.info("-[ProcessTap prepare] Aggregate device description prepared: \(String(describing: descriptionForAggregate))")

        aggregateDeviceID = AudioObjectID.unknown
        do {
            let errAggDeviceCreation = AudioHardwareCreateAggregateDevice(descriptionForAggregate as CFDictionary, &aggregateDeviceID)
            logger.info("-[ProcessTap prepare] AudioHardwareCreateAggregateDevice result: OSStatus \(errAggDeviceCreation), aggregateDeviceID: \(self.aggregateDeviceID)")

            if errAggDeviceCreation != noErr {
                logger.error("-[ProcessTap prepare] AudioHardwareCreateAggregateDevice failed with error: \(errAggDeviceCreation).")
                AudioHardwareDestroyProcessTap(self.processTapID)
                self.processTapID = .unknown
                logger.info("-[ProcessTap prepare] Cleaned up processTapID \(self.processTapID) due to aggregate device creation failure.")
                throw CoreAudioError.general("Failed to create aggregate device: \(errAggDeviceCreation)")
            }
            logger.info("-[ProcessTap prepare] Aggregate device successfully created. self.aggregateDeviceID: \(self.aggregateDeviceID)")

            var deviceOutputASBD = AudioStreamBasicDescription()
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamFormat,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var propertyDataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)

            let status = AudioObjectGetPropertyData(
                self.aggregateDeviceID,
                &propertyAddress,
                0,
                nil,
                &propertyDataSize,
                &deviceOutputASBD
            )

            guard status == noErr else {
                logger.error("-[ProcessTap prepare] Failed to read aggregate device output stream format: OSStatus \(status)")
                AudioHardwareDestroyAggregateDevice(self.aggregateDeviceID)
                self.aggregateDeviceID = .unknown
                AudioHardwareDestroyProcessTap(self.processTapID)
                self.processTapID = .unknown
                throw CoreAudioError.propertyReadError(property: "AggregateDeviceOutputFormat", osStatus: status)
            }
            self.aggregateDeviceStreamDescription = deviceOutputASBD
            logger.info("-[ProcessTap prepare] Aggregate device output stream description read successfully: \(String(describing: self.aggregateDeviceStreamDescription))")

        } catch {
            logger.error("-[ProcessTap prepare] EXCEPTION during aggregate device creation or output format read: \(error.localizedDescription)")
            if self.processTapID.isValid && !(error is CoreAudioError && "\(error)".contains("ProcessTap")) {
                 AudioHardwareDestroyProcessTap(self.processTapID)
                 self.processTapID = .unknown
            }
            throw error
        }

        do {
            self.tapStreamDescription = try tapID.readAudioTapStreamBasicDescription()
            logger.info("-[ProcessTap prepare] Tap (processTapID \(tapID)) stream basic description read successfully: \(String(describing: self.tapStreamDescription))")
        } catch {
            logger.error("-[ProcessTap prepare] Failed to read audio tap stream basic description for tapID #\(tapID): \(error.localizedDescription)")
            if self.aggregateDeviceID.isValid { AudioHardwareDestroyAggregateDevice(self.aggregateDeviceID) }
            self.aggregateDeviceID = .unknown
            if self.processTapID.isValid { AudioHardwareDestroyProcessTap(self.processTapID) }
            self.processTapID = .unknown
            logger.info("-[ProcessTap prepare] Cleaned up aggregateDeviceID and processTapID due to tap stream description failure.")
            throw error
        }
        logger.info("-[ProcessTap prepare] COMPLETED SUCCESSFULLY")

    }

    func run(on queue: DispatchQueue, ioBlock: @escaping AudioDeviceIOBlock, invalidationHandler: @escaping InvalidationHandler) throws {
        assert(activated, "\(#function) called with inactive tap!")
        assert(self.invalidationHandler == nil, "\(#function) called with tap already active!")

        errorMessage = nil
        logger.debug("Run tap!")
        self.invalidationHandler = invalidationHandler

        var err = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue, ioBlock)
        guard err == noErr else {
            // Leave the tap re-runnable on failure: clear the handler we just set so a
            // retry doesn't trip the `invalidationHandler == nil` assertion.
            self.invalidationHandler = nil
            throw CoreAudioError.general("Failed to create device I/O proc: \(err)")
        }

        err = AudioDeviceStart(aggregateDeviceID, deviceProcID)
        guard err == noErr else {
            if let deviceProcID { AudioDeviceDestroyIOProcID(aggregateDeviceID, deviceProcID) }
            self.deviceProcID = nil
            self.invalidationHandler = nil
            throw CoreAudioError.general("Failed to start audio device: \(err)")
        }
    }

    deinit { invalidate() }

}
