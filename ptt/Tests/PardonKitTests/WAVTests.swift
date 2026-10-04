import Testing
@testable import PardonKit

@Suite struct WAVTests {
    @Test func header() {
        let wav = wavData(samples: [0, 1, -1, 32767, -32768], sampleRate: sampleRate)
        let expected: [UInt8] = [
            0x52, 0x49, 0x46, 0x46, 46, 0, 0, 0, 0x57, 0x41, 0x56, 0x45,
            0x66, 0x6D, 0x74, 0x20, 16, 0, 0, 0, 1, 0, 1, 0,
            0x80, 0x3E, 0, 0, 0x00, 0x7D, 0, 0, 2, 0, 16, 0,
            0x64, 0x61, 0x74, 0x61, 10, 0, 0, 0,
            0, 0, 1, 0, 0xFF, 0xFF, 0xFF, 0x7F, 0x00, 0x80,
        ]
        check("wav: 44-byte header + data, exact bytes", Array(wav) == expected)
        check("wav: empty sample array is a bare 44-byte header", wavData(samples: [], sampleRate: sampleRate).count == 44)
    }
}
