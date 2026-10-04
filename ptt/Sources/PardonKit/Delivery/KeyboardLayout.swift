import Carbon
import CoreGraphics

// Must run on the main thread (Text Input Sources).
func currentPasteKeyCode() -> CGKeyCode {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
          let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return pasteKeyCode }
    let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
    guard let bytes = CFDataGetBytePtr(data) else { return pasteKeyCode }
    let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
    // No dead keys: each code is translated on its own, never as part of a sequence.
    func translate(_ code: CGKeyCode, modifiers: UInt32) -> String? {
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
                                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, chars.count, &length, &chars)
        return status == noErr && length > 0 ? String(utf16CodeUnits: chars, count: length) : nil
    }
    return withExtendedLifetime(source) {
        pasteKey(command: { translate($0, modifiers: UInt32(cmdKey >> 8) & 0xFF) },
                 plain: { translate($0, modifiers: 0) })
    }
}
