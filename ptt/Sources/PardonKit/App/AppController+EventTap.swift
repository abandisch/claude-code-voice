import ApplicationServices
import CoreGraphics
import Foundation

extension AppController {
    // MARK: Event tap

    func checkTap() {
        if AXIsProcessTrusted() {
            if let tap = tap {
                if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            } else {
                createTap()
            }
        } else if tap != nil {
            removeTap()
            abortSession()
        }
        refreshUI()
    }

    func createTap() {
        let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        // Must stay minimal, return the event unmodified, and never read characters.
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<AppController>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = controller.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                DispatchQueue.main.async { controller.abortSession() }
            } else if event.getIntegerValueField(.eventSourceUserData) != pardonEventTag {
                let code = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let location = event.location
                let t = now()
                DispatchQueue.main.async { controller.handle(type, code, flags, location, t) }
            }
            return Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        tapSource = source
    }

    func removeTap() {
        guard let port = tap else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source = tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(port)
        tap = nil
        tapSource = nil
    }

    func handle(_ type: CGEventType, _ code: Int64, _ flags: CGEventFlags, _ location: CGPoint, _ t: TimeInterval) {
        // The tap sees a press on the pet before the pet does; it is not a chord.
        if isPetPress(type: type, onPet: pet?.contains(location) == true) { return }
        guard type == .flagsChanged, let option = decodeOption(keyCode: code, flags: flags.rawValue) else {
            return feed(machine.otherInput(at: t))
        }
        feed(option.down ? machine.optionDown(option.key, bare: option.bare, at: t) : machine.optionUp(option.key, at: t))
    }
}
