import CoreGraphics

enum OptionKey { case left, right }

let leftOptionKeyCode: Int64 = 58
let rightOptionKeyCode: Int64 = 61
// Device-dependent bits NX_DEVICELALTKEYMASK / NX_DEVICERALTKEYMASK; CGEventFlags has no per-side flag.
let leftOptionDeviceBit: UInt64 = 0x20
let rightOptionDeviceBit: UInt64 = 0x40

func decodeOption(keyCode: Int64, flags: UInt64) -> (key: OptionKey, down: Bool, bare: Bool)? {
    let key: OptionKey
    switch keyCode {
    case leftOptionKeyCode: key = .left
    case rightOptionKeyCode: key = .right
    default: return nil
    }
    let down = flags & (key == .left ? leftOptionDeviceBit : rightOptionDeviceBit) != 0
    let bare = CGEventFlags(rawValue: flags).intersection([.maskCommand, .maskControl, .maskShift, .maskSecondaryFn]).isEmpty
    return (key, down, bare)
}
