import Foundation
import CoreAudio
import CoreMediaIO
import FadeoCore

/// Detects camera/mic *usage* (not capture — Fadeo never opens a stream itself), so this
/// needs no TCC permission prompt. Push-based: property listeners on each device fire when
/// something starts/stops using it. Devices are enumerated once at start; hot-plugged
/// devices connected after that won't be observed until the sensor restarts (acceptable
/// scope for v1 — most meetings use the built-in camera/mic).
@MainActor
final class MeetingSensor: Sensor {
    static let providedFields: Set<ContextField> = [.meeting, .camera, .mic]

    private var cameraListeners: [(CMIOObjectID, CMIOObjectPropertyListenerBlock)] = []
    private var micListeners: [(AudioObjectID, AudioObjectPropertyListenerBlock)] = []
    private var emit: ((ContextPatch) -> Void)?

    func start(emit: @escaping (ContextPatch) -> Void) {
        self.emit = emit
        subscribeCameras()
        subscribeMics()
        emitCurrent()
    }

    func stop() {
        for (device, block) in cameraListeners {
            var addr = Self.cameraRunningAddress
            CMIOObjectRemovePropertyListenerBlock(device, &addr, DispatchQueue.main, block)
        }
        cameraListeners.removeAll()

        for (device, block) in micListeners {
            var addr = Self.micRunningAddress
            AudioObjectRemovePropertyListenerBlock(device, &addr, DispatchQueue.main, block)
        }
        micListeners.removeAll()
        emit = nil
    }

    deinit {
        for (device, block) in cameraListeners {
            var addr = Self.cameraRunningAddress
            CMIOObjectRemovePropertyListenerBlock(device, &addr, DispatchQueue.main, block)
        }
        for (device, block) in micListeners {
            var addr = Self.micRunningAddress
            AudioObjectRemovePropertyListenerBlock(device, &addr, DispatchQueue.main, block)
        }
    }

    // MARK: Property addresses

    private static let cameraRunningAddress = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))

    private static let micRunningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    // MARK: Camera (CoreMediaIO)

    private func subscribeCameras() {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size > 0 else { return }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &devices) == noErr
        else { return }

        for device in devices {
            var runningAddr = Self.cameraRunningAddress
            guard CMIOObjectHasProperty(device, &runningAddr) else { continue }
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.emitCurrent() }
            }
            if CMIOObjectAddPropertyListenerBlock(device, &runningAddr, DispatchQueue.main, block) == noErr {
                cameraListeners.append((device, block))
            }
        }
    }

    private func anyCameraRunning() -> Bool {
        cameraListeners.contains { device, _ in
            var addr = Self.cameraRunningAddress
            var running: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            let status = CMIOObjectGetPropertyData(device, &addr, 0, nil, size, &size, &running)
            return status == noErr && running != 0
        }
    }

    // MARK: Microphone (CoreAudio)

    private func subscribeMics() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size > 0 else { return }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var devices = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devices) == noErr
        else { return }

        for device in devices {
            guard hasInputStreams(device) else { continue }
            var runningAddr = Self.micRunningAddress
            guard AudioObjectHasProperty(device, &runningAddr) else { continue }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.emitCurrent() }
            }
            if AudioObjectAddPropertyListenerBlock(device, &runningAddr, DispatchQueue.main, block) == noErr {
                micListeners.append((device, block))
            }
        }
    }

    private func hasInputStreams(_ device: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr && size > 0
    }

    private func anyMicRunning() -> Bool {
        micListeners.contains { device, _ in
            var addr = Self.micRunningAddress
            var running: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running)
            return status == noErr && running != 0
        }
    }

    // MARK: Emit

    private func emitCurrent() {
        let camera = anyCameraRunning()
        let mic = anyMicRunning()
        emit?(ContextPatch(
            apply: {
                $0.cameraActive = camera
                $0.micActive = mic
            },
            label: "meeting → camera=\(camera) mic=\(mic)"
        ))
    }
}
