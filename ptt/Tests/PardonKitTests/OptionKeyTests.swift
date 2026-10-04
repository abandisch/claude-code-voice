import Testing
@testable import PardonKit

@Suite struct OptionKeyTests {
    @Test func decode() {
        func decodes(_ code: Int64, _ flags: UInt64, _ key: OptionKey, _ down: Bool, _ bare: Bool) -> Bool {
            guard let d = decodeOption(keyCode: code, flags: flags) else { return false }
            return d.key == key && d.down == down && d.bare == bare
        }
        check("decode: left down", decodes(58, 0x80120, .left, true, true))
        check("decode: right down", decodes(61, 0x80140, .right, true, true))
        check("decode: left up", decodes(58, 0x100, .left, false, true))
        check("decode: down with Shift is not bare", decodes(58, 0xA0122, .left, true, false))
        check("decode: left up while right is held", decodes(58, 0x80140, .left, false, true))
        check("decode: right up while left is held", decodes(61, 0x80120, .right, false, true))
        check("decode: down with Command is not bare", decodes(58, 0x180120, .left, true, false))
        check("decode: down with Control is not bare", decodes(58, 0xC0120, .left, true, false))
        check("decode: down with Fn is not bare", decodes(58, 0x880120, .left, true, false))
        check("decode: non-Option keycode is nil", decodeOption(keyCode: 56, flags: 0x20102) == nil)
    }
}
