import Cocoa

protocol HotkeyMonitorDelegate: AnyObject {
    func hotkeyDidActivate()
    func hotkeyDidDeactivate()
}

/// Monitors for the Right Option key (0x3D) via CGEventTap.
/// Supports push-to-talk (hold) and toggle (press on/off) modes.
final class HotkeyMonitor {
    weak var delegate: HotkeyMonitorDelegate?

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isActive = false
    private let keyCode: UInt16

    init(keyCode: UInt16 = Config.hotkeyKeyCode) {
        self.keyCode = keyCode
    }

    func start() {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        // We need to use a C-style callback. Store self pointer via user info.
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: hotkeyCallback,
            userInfo: userInfo
        ) else {
            NSLog("[HotkeyMonitor] Failed to create event tap. Is accessibility enabled?")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[HotkeyMonitor] Event tap started for keycode 0x%02X", keyCode)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isActive = false
    }

    /// Called from the C callback on flagsChanged events.
    fileprivate func handleFlagsChanged(_ event: CGEvent) {
        let kc = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard kc == keyCode else { return }

        let flags = event.flags
        // Right Command sets .maskCommand. Check if the flag is now present.
        let keyDown = flags.contains(keyCode == 0x36 || keyCode == 0x37 ? .maskCommand : .maskAlternate)

        switch Config.activationMode {
        case .pushToTalk:
            if keyDown && !isActive {
                isActive = true
                delegate?.hotkeyDidActivate()
            } else if !keyDown && isActive {
                isActive = false
                delegate?.hotkeyDidDeactivate()
            }
        case .toggle:
            // Toggle on key-down only (when flag appears).
            if keyDown {
                if isActive {
                    isActive = false
                    delegate?.hotkeyDidDeactivate()
                } else {
                    isActive = true
                    delegate?.hotkeyDidActivate()
                }
            }
        }
    }
}

/// C-function callback for CGEvent tap.
private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Re-enable the tap if it was disabled by the system.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo = userInfo {
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = monitor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .flagsChanged, let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    monitor.handleFlagsChanged(event)

    return Unmanaged.passUnretained(event)
}
