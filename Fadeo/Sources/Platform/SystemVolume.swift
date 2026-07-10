import Foundation
import CoreAudio
import AudioToolbox

/// Reads, sets, and observes the macOS system output volume so Fadeo's level stays a
/// single source of truth with the system, never a second async gain (see PLAN.md 6a).
///
/// Uses `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` on the default output
/// device, which abstracts over devices that only expose per-channel volume. Observation
/// is push-based via `AudioObjectAddPropertyListenerBlock` (no polling), and we re-subscribe
/// if the default output device changes (e.g. plugging in headphones).
@MainActor
final class SystemVolume {

    /// Called on the main queue whenever the system volume changes from anywhere.
    var onChange: ((Float) -> Void)?

    private var device: AudioObjectID = 0
    private var deviceBlock: AudioObjectPropertyListenerBlock?
    private var defaultBlock: AudioObjectPropertyListenerBlock?

    private var mainVolumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    // MARK: Lifecycle

    func start() {
        device = Self.defaultOutputDevice()
        subscribeToDevice()
        subscribeToDefaultDeviceChanges()
    }

    func stop() {
        removeDeviceListener()
        if let block = defaultBlock {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, DispatchQueue.main, block)
            defaultBlock = nil
        }
    }

    deinit { onChange = nil }

    // MARK: Read / write

    /// Current system output volume, 0…1.
    func current() -> Float? { Self.readVolume(device) }

    /// Set the system output volume, 0…1.
    func set(_ value: Float) {
        let v = max(0, min(1, value))
        Self.writeVolume(device, v)
    }

    // MARK: Subscriptions

    private func subscribeToDevice() {
        guard device != 0 else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, let v = Self.readVolume(self.device) else { return }
            self.onChange?(v)
        }
        let status = AudioObjectAddPropertyListenerBlock(device, &mainVolumeAddress, DispatchQueue.main, block)
        if status == noErr { deviceBlock = block }
    }

    private func removeDeviceListener() {
        guard device != 0, let block = deviceBlock else { return }
        AudioObjectRemovePropertyListenerBlock(device, &mainVolumeAddress, DispatchQueue.main, block)
        deviceBlock = nil
    }

    private func subscribeToDefaultDeviceChanges() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.removeDeviceListener()
            self.device = Self.defaultOutputDevice()
            self.subscribeToDevice()
            if let v = self.current() { self.onChange?(v) }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, DispatchQueue.main, block)
        if status == noErr { defaultBlock = block }
    }

    // MARK: CoreAudio plumbing

    private static func defaultOutputDevice() -> AudioObjectID {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return status == noErr ? id : 0
    }

    private static func readVolume(_ device: AudioObjectID) -> Float? {
        guard device != 0 else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)

        var main = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &main),
           AudioObjectGetPropertyData(device, &main, 0, nil, &size, &value) == noErr {
            return value
        }

        // Fallback for devices without a virtual-main property.
        var scalar = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &scalar),
           AudioObjectGetPropertyData(device, &scalar, 0, nil, &size, &value) == noErr {
            return value
        }
        return nil
    }

    private static func writeVolume(_ device: AudioObjectID, _ value: Float) {
        guard device != 0 else { return }
        var v = Float32(value)
        let size = UInt32(MemoryLayout<Float32>.size)

        var main = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &main),
           AudioObjectSetPropertyData(device, &main, 0, nil, size, &v) == noErr {
            return
        }

        var scalar = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectSetPropertyData(device, &scalar, 0, nil, size, &v)
    }
}
